@tool
class_name DotWeaponArsenal
extends "dot_weapon_arsenal_state.gd"

## What one carrier holds, and the state machine that drives it.
##
## [b]It decides that a use happened. It never decides what the use hit.[/b] That is
## dot-combat's job, and the split is the same one dot-combat draws internally: this
## runs on the owning client [i]and[/i] on the server, and both reach the same
## [DotWeaponOutcome] from the same command. Collapsing the two gives you a client that
## decides who dies.
##
## [b]It is a pure function of the commands it is given.[/b] No device, no wall clock,
## no node lookups, no randomness, so a client can predict, a server re-run and a
## reconciliation replay re-run it to the same answer. See dot-combat's [DotSpread].
##
## [b]Every weapon-specific decision belongs to a [DotWeaponBehaviour].[/b] This file
## knows about slots, cadence, ammunition, reloading and switching, and deliberately
## knows nothing about pellets, arrows, arcs or beams. A game adding a weapon writes a
## behaviour; it does not touch this.


## Validates the catalogue and makes the arsenal usable.
##
## [b]Validates rather than trusts.[/b] A catalogue with a duplicate id hands a player
## the wrong weapon and nothing reports it, so the check happens once, at boot,
## headless, where somebody is watching.
func setup() -> DotResult:
	if catalogue == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "An arsenal needs a catalogue before it can be set up."
		)

	var res := catalogue.validate()
	if not res.ok:
		return res.wrap("The weapon catalogue is not valid.")

	_ready_for_use = true
	return DotResult.success(null)


func is_ready() -> bool:
	return _ready_for_use


## Loads round [param ammo] into weapon [param weapon_id]; an empty id goes back to the weapon's own.
func load_ammo(weapon_id: StringName, ammo: StringName) -> void:
	if ammo == &"":
		loaded_ammo.erase(weapon_id)
	else:
		loaded_ammo[weapon_id] = ammo


## The round loaded in [param weapon_id], or empty.
func ammo_of(weapon_id: StringName) -> StringName:
	return loaded_ammo.get(weapon_id, &"")


## Gives the carrier a weapon, in the slot its definition names.
##
## [param full] fills the magazine and tops the reserve pool up to the definition's
## [member DotWeaponDef.reserve]; a pickup off the floor usually wants it false.
func give(id: StringName, full: bool = true) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	var made := catalogue.instantiate(id, self)
	if not made.ok:
		return made

	var def := catalogue.get_def(id)

	if def.slot > max_slots:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s wants slot %d but this arsenal has %d." % [
				String(id), def.slot, max_slots
			],
			String(id)
		)

	var slot := DotWeaponSlot.make(def, made.value)
	slot.magazine = def.magazine if full else 0

	var held: DotWeaponSlot = _slots.get(def.slot, null)
	var stow := held != null and held.id() != id and weapons_in(def.slot).size() < slot_capacity() \
		and not _shelf_has(def.slot, id)
	var gone := held if (held != null and not stow) else null
	if carry != null and carry.enabled:
		var after: float = carried_weight() + carry.weight_of(def) - (carry.weight_of(gone.def) if gone != null else 0.0)
		if after > capacity() and carry.weight_of(def) > carry.weight_of(gone.def if gone != null else null):
			return DotResult.fail(
				DotError.CODE_QUOTA,
				"Too heavy: %s weighs %.1f and you carry %.1f of %.1f." % [
					def.display_name if def.display_name != "" else String(id),
					carry.weight_of(def), carried_weight(), capacity()
				],
				String(id)
			)

	if stow:
		_shelf_of(def.slot).append(held)
	elif held != null:
		_shelf_drop(def.slot, id)
	_slots[def.slot] = slot

	if def.ammo_type != &"":
		if _ammo.cap(def.ammo_type) <= 0 and def.reserve_cap() > 0:
			_ammo.set_cap(def.ammo_type, def.reserve_cap())
		if full and def.reserve > 0:
			var added := _ammo.add(def.ammo_type, def.reserve)
			if added > 0:
				ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))

	carried_changed.emit()

	if _current == 0:
		_force_select(def.slot)

	return DotResult.success(slot)


## Takes a weapon away. Switches off it first if it is the one in hand.
func take(slot: int) -> DotResult:
	if not _slots.has(slot):
		return DotResult.fail(DotError.CODE_INVALID, "Nothing in slot %d." % slot)

	if _current == slot and _shelf_of(slot).is_empty():
		var next := _first_other_slot(slot)
		_force_select(next)

	var behind := _shelf_of(slot)
	if behind.is_empty():
		_slots.erase(slot)
	else:
		_slots[slot] = behind.pop_front()
		if behind.is_empty():
			_shelf.erase(slot)
	carried_changed.emit()
	return DotResult.success(null)


func clear() -> void:
	_slots.clear()
	_shelf.clear()
	_current = 0
	_previous = 0
	_switch_done_tick = -1
	_reloading = false
	_burst_left = 0
	_charge_started = -1
	carried_changed.emit()




## Drops the heaviest stowed or held weapons (not the one in hand) until under the limit.
## Returns the ids dropped, in order.
func enforce_limit() -> Array[StringName]:
	var dropped: Array[StringName] = []
	while carry != null and carry.enabled and over_by() > 0.0001:
		var worst: DotWeaponSlot = null
		var worst_slot := 0
		for s: int in _slots:
			for w in weapons_in(s):
				if w == current():
					continue
				if worst == null or carry.weight_of(w.def) > carry.weight_of(worst.def):
					worst = w
					worst_slot = s
		if worst == null:
			break
		dropped.append(worst.id())
		if _slots[worst_slot] == worst:
			take(worst_slot)
		else:
			_shelf_of(worst_slot).erase(worst)
			carried_changed.emit()
	return dropped


## Brings the next weapon of the current slot into hand (pressing the slot key again). False when
## the slot holds one weapon.
func cycle_slot(tick: int) -> bool:
	var behind := _shelf_of(_current)
	if disabled or behind.is_empty() or not _slots.has(_current):
		return false
	_cancel_transient()
	behind.append(_slots[_current])
	_slots[_current] = behind.pop_front()
	var to := current()
	_switch_to = _current
	_holstering = false
	_switch_done_tick = tick + ticks_for(to.def, to.def.deploy_ticks)
	switched.emit(_current, _current)
	carried_changed.emit()
	return true




## Adds reserve ammunition. Returns how many rounds actually fitted.
func add_ammo(pool: StringName, amount: int) -> int:
	var added := _ammo.add(pool, amount)
	if added > 0:
		ammo_changed.emit(pool, _ammo.count(pool))
	return added


func is_switching() -> bool:
	return _switch_done_tick >= 0


## Begins a switch to [param slot]. Returns false if it cannot start.
##
## A switch is a holster followed by a deploy, and the weapon in hand stays usable
## until the holster finishes, which is what makes quick-switching a real technique
## rather than an instant teleport between weapons.
##
## [b]Asking again for the slot already being switched to is not a new switch.[/b] A command
## carries its slot every tick, and a switch restarted on each would push the holster
## deadline back for ever.
## The fire mode in hand ([enum DotWeaponDef.Fire]), or -1 with nothing held.
func fire_mode() -> int:
	var s := current()
	return s.fire_mode() if s != null else -1


## The modes the held gun lets the player choose between; one entry when it has no choice.
func fire_modes_available() -> Array[DotWeaponDef.Fire]:
	var s := current()
	var out: Array[DotWeaponDef.Fire] = []
	if s != null:
		out.append_array(s.def.allowed_fire_modes())
	return out


## Selects [param mode] on the held gun; false when the gun does not support it or is mid-burst.
func set_fire_mode(mode: DotWeaponDef.Fire) -> bool:
	var s := current()
	if s == null or _burst_left > 0 or _charge_started >= 0:
		return false
	var i := s.def.allowed_fire_modes().find(mode)
	if i < 0:
		return false
	if i != s.fire_mode_index:
		s.fire_mode_index = i
		fire_mode_changed.emit(_current, mode)
	return true


## Moves the held gun to its next allowed fire mode; false (nothing changes) when it has only one.
func cycle_fire_mode() -> bool:
	var s := current()
	if s == null:
		return false
	var modes := s.def.allowed_fire_modes()
	if modes.size() < 2:
		return false
	var next := modes[(clampi(s.fire_mode_index, 0, modes.size() - 1) + 1) % modes.size()]
	return set_fire_mode(next)


func select(slot: int, tick: int) -> bool:
	if disabled or slot == _current or not _slots.has(slot):
		return false

	if is_switching() and _switch_to == slot:
		return false

	var from := current()

	_switch_to = slot
	_holstering = true
	_switch_done_tick = tick + (ticks_for(from.def, from.def.holster_ticks) if from != null else 0)

	# A reload that survived a switch would finish into a magazine nobody is holding.
	_cancel_transient()

	return true


func select_next(tick: int) -> bool:
	var all := slots()
	if all.size() < 2:
		return false
	var at := all.find(_current)
	return select(all[(at + 1) % all.size()], tick)


func select_previous(tick: int) -> bool:
	var all := slots()
	if all.size() < 2:
		return false
	var at := all.find(_current)
	return select(all[(at - 1 + all.size()) % all.size()], tick)


func select_last(tick: int) -> bool:
	return select(_previous, tick) if _slots.has(_previous) else false


func _force_select(slot: int) -> void:
	var from := _current
	if from == slot:
		return
	if from != 0:
		_previous = from
	_current = slot
	_switch_done_tick = -1
	_holstering = false
	_cancel_transient()
	switched.emit(from, slot)


func _first_other_slot(besides: int) -> int:
	for s in slots():
		if s != besides:
			return s
	return 0


## Drops everything transient. A switch, a death and a correction all need this.
func _cancel_transient() -> void:
	_reloading = false
	_reload_done_tick = -1
	_burst_left = 0
	_charge_started = -1
	_charge_announced = false
	_held_ticks = 0
	_buffer_until = -1


func is_reloading() -> bool:
	return _reloading


## Begins a reload. Returns false when there is nothing to do.
func begin_reload(tick: int) -> bool:
	var slot := current()

	if disabled or slot == null or _reloading or is_switching():
		return false

	if not slot.def.uses_magazine() or slot.magazine_space() <= 0:
		return false

	if slot.def.ammo_type != &"" and not _ammo.has(slot.def.ammo_type, 1):
		return false

	_reloading = true
	_reload_done_tick = tick + ticks_for(
		slot.def,
		slot.def.reload_start_ticks if slot.def.reload_per_round
		else slot.def.reload_ticks
	)
	reload_started.emit(_current)
	return true


func cancel_reload() -> void:
	_reloading = false
	_reload_done_tick = -1


func _finish_reload(tick: int) -> void:
	var slot := current()
	if slot == null:
		_reloading = false
		return

	var def := slot.def
	var want := def.magazine - slot.magazine

	if def.reload_per_round:
		want = 1

	var took := want
	if def.ammo_type != &"":
		took = _ammo.take(def.ammo_type, want) if not def.infinite_reserve else want
		if def.infinite_reserve:
			took = want

	if took <= 0:
		_reloading = false
		_reload_done_tick = -1
		return

	slot.magazine += took
	slot.behaviour.reloaded(took)

	if def.ammo_type != &"":
		ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))

	# A per-round reload keeps going until the magazine is full or the reserve is dry.
	if (
		def.reload_per_round
		and slot.magazine_space() > 0
		and (def.infinite_reserve or _ammo.has(def.ammo_type, 1) or def.ammo_type == &"")
	):
		_reload_done_tick = tick + ticks_for(def, def.reload_ticks)
	else:
		_reloading = false
		_reload_done_tick = -1
		reload_finished.emit(_current, slot.magazine)


## Marks the start of a reconciliation replay.
##
## Everything still simulates; what changes is that every context is marked
## [member DotWeaponContext.replayed], so a behaviour and a listener can decline to
## make a sound, spawn an effect or bill a statistic a second time.
func begin_replay() -> void:
	_replaying = true


func end_replay() -> void:
	_replaying = false


func is_replaying() -> bool:
	return _replaying


## Runs one tick of one command. The only entry point a game needs.
##
## [param ctx] carries the carrier's origin, aim and posture for this tick; the arsenal
## fills in the tick, the index, the charge and the replay flag before handing it to a
## behaviour. Returns the outcome of a use, or a refusal with
## [member DotWeaponOutcome.used] false, which is the ordinary case on most ticks.
func simulate_tick(
	command: DotWeaponCommand,
	ctx: DotWeaponContext,
	previous: DotWeaponCommand = null
) -> DotWeaponOutcome:
	if not _ready_for_use:
		return DotWeaponOutcome.nothing("setup() has not been called.")

	ctx.tick = ctx.tick
	ctx.replayed = _replaying
	ctx.authority = authority
	var sprint_blocked := ctx.sprinting and ctx.sprint_blocks_aim
	ctx.aiming = command.is_pressed(DotWeaponCommand.BUTTON_AIM) and not sprint_blocked

	if disabled:
		return DotWeaponOutcome.nothing("The arsenal is disabled.")

	_advance_switch(ctx)
	_advance_reload(ctx.tick)

	var slot := current()
	if slot == null:
		return DotWeaponOutcome.nothing("Nothing in hand.")

	_apply_slot_request(command, ctx.tick)
	var wants_mode := command.is_pressed(DotWeaponCommand.BUTTON_FIRE_MODE)
	if wants_mode and not (previous != null and previous.is_pressed(DotWeaponCommand.BUTTON_FIRE_MODE)):
		var _changed := cycle_fire_mode()
	_run_behaviour_tick(slot, ctx)

	if is_switching():
		return DotWeaponOutcome.nothing("Switching.")

	if command.is_pressed(DotWeaponCommand.BUTTON_RELOAD) and not sprint_blocked:
		begin_reload(ctx.tick)

	return _advance_use(slot, command, ctx, previous)


## Whether [method simulate_tick] would only tick the weapon in hand: no button, no other slot
## asked for, nothing switching, reloading, charging or bursting, and a behaviour whose tick
## reads no context. A server asks it of every shooter to skip building a context.
func is_idle_for(command: DotWeaponCommand, previous: DotWeaponCommand) -> bool:
	if not _ready_for_use or disabled or command.buttons != 0 or (command.slot > 0 and command.slot != _current):
		return false

	if previous != null and previous.buttons != 0:
		return false

	if _switch_done_tick >= 0 or _reloading or _burst_left > 0 or _charge_started >= 0 or _buffer_until >= 0:
		return false

	var slot := current()
	return slot != null and not slot.behaviour.tick_needs_context()


## The spread cone half-angle the weapon in hand would fire with now, for a crosshair; 0 with none.
func spread_now() -> float:
	var slot := current()
	return slot.behaviour.spread_now() if slot != null else 0.0


## The crosshair gap scale of the weapon in hand (see [member DotWeaponBallistics.crosshair_scale]); 1 with none.
func crosshair_scale() -> float:
	var slot := current()
	if slot == null or slot.def == null:
		return 1.0
	if slot.def.crosshair_scale > 0.0:
		return slot.def.crosshair_scale
	if not (slot.def.tuning is DotWeaponBallistics):
		return 1.0
	return (slot.def.tuning as DotWeaponBallistics).crosshair_scale_for(slot.def.tags)


## The tick [method is_idle_for] promised: what [method simulate_tick] does for it, with no context.
func idle_tick() -> DotWeaponOutcome:
	_held_ticks = 0
	current().behaviour.tick(null)
	return DotWeaponOutcome.nothing("")


func _advance_switch(ctx: DotWeaponContext) -> void:
	if _switch_done_tick < 0 or ctx.tick < _switch_done_tick:
		return

	if _holstering:
		var from := current()
		if from != null:
			from.behaviour.holster(ctx)

		var previous_slot := _current
		_previous = _current
		_current = _switch_to
		_holstering = false

		var to := current()
		_switch_done_tick = ctx.tick + (ticks_for(to.def, to.def.deploy_ticks) if to != null else 0)
		switched.emit(previous_slot, _current)
		return

	# The deploy finished.
	_switch_done_tick = -1
	var deployed := current()
	if deployed != null:
		deployed.behaviour.deploy(ctx)
		_next_use_tick = maxi(_next_use_tick, ctx.tick)


func _advance_reload(tick: int) -> void:
	if _reloading and _reload_done_tick >= 0 and tick >= _reload_done_tick:
		_finish_reload(tick)


func _apply_slot_request(command: DotWeaponCommand, tick: int) -> void:
	if command.slot > 0:
		select(command.slot, tick)
	elif command.is_pressed(DotWeaponCommand.BUTTON_NEXT):
		select_next(tick)
	elif command.is_pressed(DotWeaponCommand.BUTTON_PREVIOUS):
		select_previous(tick)
	elif command.is_pressed(DotWeaponCommand.BUTTON_LAST):
		select_last(tick)


func _run_behaviour_tick(slot: DotWeaponSlot, ctx: DotWeaponContext) -> void:
	ctx.charge = _charge_value(slot, ctx.tick)
	ctx.held_ticks = _held_ticks
	slot.behaviour.tick(ctx)


func _charge_value(slot: DotWeaponSlot, tick: int) -> float:
	if _charge_started < 0 or not slot.def.is_charged():
		return 1.0
	return charge_for(slot.def, tick - _charge_started)


func _advance_use(
	slot: DotWeaponSlot,
	command: DotWeaponCommand,
	ctx: DotWeaponContext,
	previous: DotWeaponCommand
) -> DotWeaponOutcome:
	var def := slot.def
	var down := command.is_pressed(DotWeaponCommand.BUTTON_ATTACK)
	if ctx.sprinting and ctx.sprint_blocks_fire:
		down = false
	var was_down := previous != null and previous.is_pressed(
		DotWeaponCommand.BUTTON_ATTACK
	)

	if down:
		_held_ticks += 1
	else:
		_held_ticks = 0

	if _buffer_until >= 0 and ctx.tick > _buffer_until:
		_buffer_until = -1

	match slot.fire_mode():
		DotWeaponDef.Fire.CHARGE:
			return _advance_charge(slot, ctx, down, was_down)
		DotWeaponDef.Fire.BURST:
			return _advance_burst(slot, ctx, down, was_down)
		DotWeaponDef.Fire.AUTO, DotWeaponDef.Fire.HOLD:
			if down:
				return _try_use(slot, ctx)
			if was_down:
				return slot.behaviour.release(ctx)
			return DotWeaponOutcome.nothing("")
		_:
			if down and not was_down:
				if ctx.tick < _next_use_tick and _arm_buffer(def, ctx.tick):
					return DotWeaponOutcome.nothing("")
				_buffer_until = -1
				return _try_use(slot, ctx)
			if _buffer_until >= ctx.tick and ctx.tick >= _next_use_tick:
				_buffer_until = -1
				return _try_use(slot, ctx)
			if was_down and not down:
				return slot.behaviour.release(ctx)
			return DotWeaponOutcome.nothing("")


## Remembers a press made inside the cooldown so it fires when the cooldown ends, if that is inside the window.
func _arm_buffer(def: DotWeaponDef, tick: int) -> bool:
	var seconds := def.fire_buffer_seconds if def.fire_buffer_seconds > -2.0 else fire_buffer_seconds
	if seconds == 0.0:
		return false
	_buffer_until = 0x7fffffff if seconds < 0.0 else tick + ceili(seconds * tick_rate)
	return true


func _advance_charge(
	slot: DotWeaponSlot, ctx: DotWeaponContext, down: bool, was_down: bool
) -> DotWeaponOutcome:
	var def := slot.def

	if down and not was_down:
		# Refused up front, not at release: a draw that then does nothing reads as a broken bow.
		if not _can_pay(slot):
			dry_used.emit(_current)
			return DotWeaponOutcome.nothing("Nothing to spend.")
		_charge_started = ctx.tick
		_charge_announced = false
		return DotWeaponOutcome.nothing("")

	if down:
		if (
			not _charge_announced
			and _charge_started >= 0
			and ctx.tick - _charge_started >= ticks_for(def, def.charge_ticks)
		):
			_charge_announced = true
			charge_full.emit(_current)
		return DotWeaponOutcome.nothing("")

	if not was_down or _charge_started < 0:
		return DotWeaponOutcome.nothing("")

	# Released.
	var charge := charge_for(def, ctx.tick - _charge_started)
	_charge_started = -1
	_charge_announced = false

	if def.charge_requires_min and charge < def.min_charge:
		return DotWeaponOutcome.nothing("Not drawn far enough.")

	ctx.charge = charge
	return _try_use(slot, ctx)


func _advance_burst(
	slot: DotWeaponSlot, ctx: DotWeaponContext, down: bool, was_down: bool
) -> DotWeaponOutcome:
	if down and not was_down and _burst_left <= 0:
		_burst_left = slot.def.burst_count

	if _burst_left <= 0:
		return DotWeaponOutcome.nothing("")

	var out := _try_use(slot, ctx)
	if out.used:
		_burst_left -= 1
		# The gap within a burst is its own; one interval for both makes a burst look automatic.
		if _burst_left > 0:
			_next_use_tick = ctx.tick + maxi(1, ticks_for(slot.def, slot.def.burst_interval_ticks))
	elif out.refusal != "":
		_burst_left = 0

	return out


## Whether the weapon can pay for one use right now.
func _can_pay(slot: DotWeaponSlot) -> bool:
	var def := slot.def

	if not def.uses_ammo():
		return true

	if def.uses_magazine():
		return slot.magazine >= def.cost_per_use

	return def.infinite_reserve or _ammo.has(def.ammo_type, def.cost_per_use)


func _try_use(slot: DotWeaponSlot, ctx: DotWeaponContext) -> DotWeaponOutcome:
	var def := slot.def

	if ctx.tick < _next_use_tick:
		return DotWeaponOutcome.nothing("")

	if not _can_pay(slot):
		dry_used.emit(_current)
		if def.auto_reload and def.uses_magazine():
			if not (ctx.sprinting and ctx.sprint_blocks_aim):
				begin_reload(ctx.tick)
		elif auto_switch_on_empty:
			_switch_off_empty(ctx.tick)
		return DotWeaponOutcome.nothing("Nothing to spend.")

	# Whether the weapon can pay is asked BEFORE the reload is cancelled: the other way round,
	# a held trigger on an empty weapon cancels its own reload every cadence and it never refills.
	if _reloading:
		cancel_reload()

	var allowed := slot.behaviour.can_use(ctx)
	if not allowed.ok:
		return DotWeaponOutcome.nothing(allowed.error.message)

	ctx.index = _use_index
	_use_index += 1

	var out := slot.behaviour.use(ctx)

	if not out.used:
		return out

	_spend(slot, out)

	# An outcome's own cooldown is counted in the definition's ticks, like the interval it
	# stands in for, so the behaviour that set it never needs to know the running rate.
	var cadence := out.cooldown_ticks if out.cooldown_ticks >= 0 else def.use_interval_ticks
	_next_use_tick = ctx.tick + maxi(1, ticks_for(def, cadence))

	used.emit(out)
	return out


func _spend(slot: DotWeaponSlot, out: DotWeaponOutcome) -> void:
	var def := slot.def

	if not def.uses_ammo():
		return

	var cost := out.ammo_used if out.ammo_used >= 0 else def.cost_per_use
	if cost <= 0:
		return

	if def.uses_magazine():
		slot.magazine = maxi(0, slot.magazine - cost)
	elif not def.infinite_reserve:
		_ammo.take(def.ammo_type, cost)
		ammo_changed.emit(def.ammo_type, _ammo.count(def.ammo_type))


func _switch_off_empty(tick: int) -> void:
	for s in slots():
		if s == _current:
			continue
		var other: DotWeaponSlot = _slots[s]
		if _can_pay(other):
			select(s, tick)
			return


## Fits [param fitting] to the weapon in [param slot], replacing what was there. The slot's
## definition becomes a copy with the attachments applied (the catalogue's is untouched), a
## magazine above the new capacity is clamped, and an empty fitting restores the base.
func fit(slot: int, fitting: DotWeaponFitting) -> DotResult:
	if attachments == null:
		return DotResult.fail(DotError.CODE_STATE, "This arsenal has no attachment catalogue.")
	var s: DotWeaponSlot = _slots.get(slot, null)
	if s == null:
		return DotResult.fail(DotError.CODE_INVALID, "Nothing in slot %d." % slot)
	return _apply_fitting(s, fitting)


func _apply_fitting(s: DotWeaponSlot, fitting: DotWeaponFitting) -> DotResult:
	var base := catalogue.get_def(s.id())
	if base == null:
		return DotResult.fail(DotError.CODE_INVALID, "%s is not in the catalogue." % String(s.id()))
	var res := attachments.apply(base, fitting)
	if not res.ok:
		return res
	s.def = res.value
	s.fitting = null if fitting.is_empty() else fitting.duplicate_fitting()
	if s.def.uses_magazine():
		s.magazine = mini(s.magazine, s.def.magazine)
	carried_changed.emit()
	return DotResult.success(s)


## What is fitted to [param slot]. Never null; empty when nothing is.
func fitting_at(slot: int) -> DotWeaponFitting:
	var s: DotWeaponSlot = _slots.get(slot, null)
	if s == null:
		return DotWeaponFitting.make(&"")
	if s.fitting == null:
		return DotWeaponFitting.make(s.id())
	return s.fitting.duplicate_fitting()


## Everything that has to travel and everything a rollback has to restore, behaviours' own state included.
func snapshot() -> Dictionary:
	return _Io.snapshot(self)


## Restores a snapshot, rebuilding any weapon this carrier is not currently holding.
func restore(d: Dictionary) -> DotResult:
	return _Io.restore(self, d)


func describe() -> Dictionary:
	return _Io.describe(self)


func describe_lines() -> PackedStringArray:
	return _Io.describe_lines(self)
