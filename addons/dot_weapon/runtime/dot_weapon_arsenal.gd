@tool
class_name DotWeaponArsenal
extends Node

## What one carrier holds, and the state machine that drives it.
##
## [b]It decides that a use happened. It never decides what the use hit.[/b] That is
## dot-combat's job, and the split is the same one dot-combat draws internally: this
## runs on the owning client [i]and[/i] on the server, and both reach the same
## [DotWeaponOutcome] from the same command. Collapsing the two gives you a client that
## decides who dies.
##
## [b]It is a pure function of the commands it is given.[/b] No device, no wall clock,
## no node lookups, no randomness. That is what lets a client predict a use, a server
## re-run it authoritatively, and a reconciliation replay re-run it again, all reaching
## the same answer. See [DotWeaponSpread] for the one place that is easy to get wrong.
##
## [b]Every weapon-specific decision belongs to a [DotWeaponBehaviour].[/b] This file
## knows about slots, cadence, ammunition, reloading and switching, and deliberately
## knows nothing about pellets, arrows, arcs or beams. A game adding a weapon writes a
## behaviour; it does not touch this.

## A use produced an outcome. Carries the whole outcome so a listener can tell a swing
## from a shot without inspecting it.
signal used(outcome: DotWeaponOutcome)

## A use was attempted with nothing to spend.
signal dry_used(slot: int)

signal reload_started(slot: int)
signal reload_finished(slot: int, rounds: int)

## A charged weapon reached full draw. For a sound and a HUD tick, nothing else.
signal charge_full(slot: int)

signal switched(from: int, to: int)
signal ammo_changed(pool: StringName, amount: int)
signal carried_changed()

@export_group("Simulation")

## Ticks per second the simulation runs at.
##
## Only used to convert for a caller that thinks in seconds; nothing here measures time
## any other way. Every duration on a [DotWeaponDef] is already in ticks.
@export_range(1, 240, 1) var tick_rate: int = 64

@export_range(1, 16, 1) var max_slots: int = 8

@export_group("Content")

## Every weapon this carrier could hold. Required before [method setup].
@export var catalogue: DotWeaponCatalogue = null

@export_group("Rules")

## Switches away from a weapon that has run out entirely.
@export var auto_switch_on_empty: bool = true

## Refuses everything. For a dead player, a cutscene, a freeze time.
@export var disabled: bool = false

## True on the machine that decides. Handed to every [DotWeaponContext].
##
## A behaviour must not apply anything when this is false, and dot-combat must not
## resolve damage. A client still runs everything, for prediction.
@export var authority: bool = false

# --- State ------------------------------------------------------------------

var _slots: Dictionary = {}          ## int -> DotWeaponSlot
var _ammo := DotWeaponAmmo.new()
var _current: int = 0
var _previous: int = 0

## Tick the current weapon may next be used on.
var _next_use_tick: int = 0

## Switching: the slot being switched to, and the tick the switch completes on.
var _switch_to: int = 0
var _switch_done_tick: int = -1
var _holstering: bool = false

## Reloading: the tick the reload (or the next round of it) completes on.
var _reload_done_tick: int = -1
var _reloading: bool = false

## Burst: uses left in the burst, and the tick the next one is due.
var _burst_left: int = 0

## Charge: the tick the use button went down on. -1 when it is not down.
var _charge_started: int = -1
var _charge_announced: bool = false

## Ticks the use button has been held, for a HOLD weapon.
var _held_ticks: int = 0

## Uses so far, so two uses on one tick scatter differently.
var _use_index: int = 0

## Set while re-running inputs after a correction.
var _replaying: bool = false

var _ready_for_use: bool = false


# --- Lifecycle --------------------------------------------------------------

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


# --- Carrying ---------------------------------------------------------------

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

	if _current == slot:
		var next := _first_other_slot(slot)
		_force_select(next)

	_slots.erase(slot)
	carried_changed.emit()
	return DotResult.success(null)


func clear() -> void:
	_slots.clear()
	_current = 0
	_previous = 0
	_switch_done_tick = -1
	_reloading = false
	_burst_left = 0
	_charge_started = -1
	carried_changed.emit()


func carries(id: StringName) -> bool:
	for slot: DotWeaponSlot in _slots.values():
		if slot.id() == id:
			return true
	return false


func has_slot(slot: int) -> bool:
	return _slots.has(slot)


func slot_at(slot: int) -> DotWeaponSlot:
	return _slots.get(slot, null)


func current_slot() -> int:
	return _current


func current() -> DotWeaponSlot:
	return _slots.get(_current, null)


func current_def() -> DotWeaponDef:
	var slot := current()
	return slot.def if slot != null else null


func slots() -> Array[int]:
	var out: Array[int] = []
	for key: int in _slots.keys():
		out.append(key)
	out.sort()
	return out


func ammo() -> DotWeaponAmmo:
	return _ammo


## Adds reserve ammunition. Returns how many rounds actually fitted.
func add_ammo(pool: StringName, amount: int) -> int:
	var added := _ammo.add(pool, amount)
	if added > 0:
		ammo_changed.emit(pool, _ammo.count(pool))
	return added


# --- Switching --------------------------------------------------------------

func is_switching() -> bool:
	return _switch_done_tick >= 0


## Begins a switch to [param slot]. Returns false if it cannot start.
##
## A switch is a holster followed by a deploy, and the weapon in hand stays usable
## until the holster finishes, which is what makes quick-switching a real technique
## rather than an instant teleport between weapons.
func select(slot: int, tick: int) -> bool:
	if disabled or slot == _current or not _slots.has(slot):
		return false

	var from := current()

	_switch_to = slot
	_holstering = true
	_switch_done_tick = tick + (from.def.holster_ticks if from != null else 0)

	# A switch cancels everything the old weapon was in the middle of. A reload that
	# survived a switch would finish into a magazine nobody is holding.
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


# --- Reloading --------------------------------------------------------------

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
	_reload_done_tick = tick + (
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
	# Stopping after one round is the bug where a shotgun loads a single shell and then
	# stands there, which looks like the reload being interrupted by nothing.
	if (
		def.reload_per_round
		and slot.magazine_space() > 0
		and (def.infinite_reserve or _ammo.has(def.ammo_type, 1) or def.ammo_type == &"")
	):
		_reload_done_tick = tick + def.reload_ticks
	else:
		_reloading = false
		_reload_done_tick = -1
		reload_finished.emit(_current, slot.magazine)


# --- Replay -----------------------------------------------------------------

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


# --- The tick ---------------------------------------------------------------

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

	if disabled:
		return DotWeaponOutcome.nothing("The arsenal is disabled.")

	_advance_switch(ctx)
	_advance_reload(ctx.tick)

	var slot := current()
	if slot == null:
		return DotWeaponOutcome.nothing("Nothing in hand.")

	_apply_slot_request(command, ctx.tick)
	_run_behaviour_tick(slot, ctx)

	if is_switching():
		return DotWeaponOutcome.nothing("Switching.")

	if command.is_pressed(DotWeaponCommand.BUTTON_RELOAD):
		begin_reload(ctx.tick)

	return _advance_use(slot, command, ctx, previous)


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
		_switch_done_tick = ctx.tick + (to.def.deploy_ticks if to != null else 0)
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
	return slot.def.charge_at(tick - _charge_started)


# --- Using ------------------------------------------------------------------

func _advance_use(
	slot: DotWeaponSlot,
	command: DotWeaponCommand,
	ctx: DotWeaponContext,
	previous: DotWeaponCommand
) -> DotWeaponOutcome:
	var def := slot.def
	var down := command.is_pressed(DotWeaponCommand.BUTTON_ATTACK)
	var was_down := previous != null and previous.is_pressed(
		DotWeaponCommand.BUTTON_ATTACK
	)

	if down:
		_held_ticks += 1
	else:
		_held_ticks = 0

	match def.fire_mode:
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
				return _try_use(slot, ctx)
			if was_down and not down:
				return slot.behaviour.release(ctx)
			return DotWeaponOutcome.nothing("")


func _advance_charge(
	slot: DotWeaponSlot, ctx: DotWeaponContext, down: bool, was_down: bool
) -> DotWeaponOutcome:
	var def := slot.def

	if down and not was_down:
		# Starting a draw is refused up front when there is nothing to spend, rather
		# than at release. A bow that lets you draw and then does nothing is a bow the
		# player believes is broken.
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
			and ctx.tick - _charge_started >= def.charge_ticks
		):
			_charge_announced = true
			charge_full.emit(_current)
		return DotWeaponOutcome.nothing("")

	if not was_down or _charge_started < 0:
		return DotWeaponOutcome.nothing("")

	# Released.
	var charge := def.charge_at(ctx.tick - _charge_started)
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
		# The gap within a burst is its own, and it is usually shorter than the gap
		# between bursts. Using one interval for both is the bug that makes a
		# three-round burst indistinguishable from automatic fire.
		if _burst_left > 0:
			_next_use_tick = ctx.tick + maxi(1, slot.def.burst_interval_ticks)
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
			begin_reload(ctx.tick)
		elif auto_switch_on_empty:
			_switch_off_empty(ctx.tick)
		return DotWeaponOutcome.nothing("Nothing to spend.")

	# [b]Whether the weapon can pay is asked BEFORE the reload is cancelled, and the
	# order is the whole of it.[/b] Cancelling first means a held trigger on an empty
	# weapon cancels the reload it just started, every time the cadence comes round,
	# so the reload restarts for ever and the magazine never refills. Nothing errors;
	# the gun simply stops working, and the only symptom is that a bot holding its
	# trigger does about a fifth of the damage it should.
	#
	# With the order this way round, using cancels a reload only when there is
	# something to fire, which is what every shooter does and what a player expects
	# from a reload they started by accident.
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

	var cadence := out.cooldown_ticks if out.cooldown_ticks >= 0 else def.use_interval_ticks
	_next_use_tick = ctx.tick + maxi(1, cadence)

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


# --- Netcode ----------------------------------------------------------------

## Everything that has to travel and everything a rollback has to restore.
##
## [b]The behaviours' own state is in here[/b], because a snapshot that carried the
## magazine and not the bow's draw reconciles a correction by silently un-drawing it.
func snapshot() -> Dictionary:
	var carried: Dictionary = {}
	for key: int in _slots.keys():
		carried[key] = (_slots[key] as DotWeaponSlot).snapshot()

	return {
		"slots": carried,
		"ammo": _ammo.snapshot(),
		"current": _current,
		"previous": _previous,
		"next_use": _next_use_tick,
		"switch_to": _switch_to,
		"switch_done": _switch_done_tick,
		"holstering": _holstering,
		"reloading": _reloading,
		"reload_done": _reload_done_tick,
		"burst_left": _burst_left,
		"charge_started": _charge_started,
		"held": _held_ticks,
		"use_index": _use_index,
	}


## Restores a snapshot, rebuilding any weapon this carrier is not currently holding.
func restore(d: Dictionary) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	var carried: Dictionary = d.get("slots", {})
	var wanted: Dictionary = {}

	for key: Variant in carried.keys():
		var index := int(key)
		var row: Dictionary = carried[key]
		var id := StringName(str(row.get("id", "")))
		wanted[index] = true

		var existing: DotWeaponSlot = _slots.get(index, null)

		if existing == null or existing.id() != id:
			var made := catalogue.instantiate(id, self)
			if not made.ok:
				return made
			var def := catalogue.get_def(id)
			existing = DotWeaponSlot.make(def, made.value)
			_slots[index] = existing

		existing.restore(row)

	for key: int in _slots.keys().duplicate():
		if not wanted.has(key):
			_slots.erase(key)

	_ammo.restore(d.get("ammo", {}))
	_current = int(d.get("current", 0))
	_previous = int(d.get("previous", 0))
	_next_use_tick = int(d.get("next_use", 0))
	_switch_to = int(d.get("switch_to", 0))
	_switch_done_tick = int(d.get("switch_done", -1))
	_holstering = bool(d.get("holstering", false))
	_reloading = bool(d.get("reloading", false))
	_reload_done_tick = int(d.get("reload_done", -1))
	_burst_left = int(d.get("burst_left", 0))
	_charge_started = int(d.get("charge_started", -1))
	_held_ticks = int(d.get("held", 0))
	_use_index = int(d.get("use_index", 0))

	return DotResult.success(null)


# --- Reporting --------------------------------------------------------------

func describe() -> Dictionary:
	var slot := current()
	return {
		"ready": _ready_for_use,
		"current": _current,
		"weapon": String(slot.id()) if slot != null else "",
		"magazine": slot.magazine if slot != null else 0,
		"switching": is_switching(),
		"reloading": _reloading,
		"carried": _slots.keys().size(),
		"ammo": _ammo.describe(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("arsenal: %d carried, slot %d%s" % [
		_slots.keys().size(), _current, " (switching)" if is_switching() else ""
	])

	for s in slots():
		var slot: DotWeaponSlot = _slots[s]
		var mark := ">" if s == _current else " "
		out.append("%s %d %-18s mag %d/%d" % [
			mark, s, String(slot.id()), slot.magazine, slot.def.magazine
		])

	for pool in _ammo.pools():
		out.append("  reserve %-12s %d" % [String(pool), _ammo.count(pool)])

	return out
