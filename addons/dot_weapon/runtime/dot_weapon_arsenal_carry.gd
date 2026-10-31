@tool
extends "dot_weapon_arsenal_state.gd"
## Carrying, dropping and fire modes for [DotWeaponArsenal]; a layer between the state and the state machine so neither file grows past the size gate.

const CHANNEL := "weapon.arsenal"

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


## Drops the weapon in hand for a world pickup: removes it, cancels any reload, switches to the next
## weapon and returns `{id, magazine, reserve}` plus `fit` (mount to attachment id) and `fm` (fire mode
## index) when set (empty when nothing may be dropped). Slots in [param keep_slots] (a permanent melee
## weapon) are never dropped. The reserve goes with it only when no other carried weapon draws on the same pool.
func drop_current(keep_slots: Array[int] = []) -> Dictionary:
	return drop_from_slot(_current, keep_slots)


## [method drop_current] for the weapon at the front of [param slot_number], held or not.
func drop_from_slot(slot_number: int, keep_slots: Array[int] = []) -> Dictionary:
	var held: DotWeaponSlot = _slots.get(slot_number, null)
	if held == null or keep_slots.has(slot_number) or disabled:
		return {}
	var state := {"id": held.id(), "magazine": held.magazine, "reserve": 0}
	if held.fitting != null and not held.fitting.is_empty():
		state["fit"] = held.fitting.to_dictionary()
	if held.fire_mode_index != 0:
		state["fm"] = held.fire_mode_index
	if slot_number == _current:
		_cancel_transient()
	if _shelf_of(slot_number).is_empty():
		var _taken := take(slot_number)
	else:
		_slots[slot_number] = _shelf_of(slot_number).pop_front()
		if _shelf_of(slot_number).is_empty():
			_shelf.erase(slot_number)
		if slot_number == _current:
			var to := current()
			_switch_to = slot_number
			_holstering = false
			_switch_done_tick = -1
			if to != null:
				switched.emit(slot_number, slot_number)
		carried_changed.emit()
	var pool := held.def.ammo_type
	if pool != &"" and not held.def.infinite_reserve:
		var shared := false
		for s: int in _slots:
			for w in weapons_in(s):
				if w.def.ammo_type == pool:
					shared = true
		if not shared:
			state["reserve"] = _ammo.take(pool, _ammo.count(pool))
			ammo_changed.emit(pool, _ammo.count(pool))
	return state


## Puts the ammunition, attachments and fire mode of a [method drop_current] state back on the weapon
## [param state] names, which must already be carried (given with `full = false`).
func apply_dropped(state: Dictionary) -> void:
	var def := catalogue.get_def(StringName(state.get("id", &"")))
	if def == null:
		return
	var fit_state: Variant = state.get("fit", null)
	if fit_state is Dictionary and attachments != null:
		var parsed := DotWeaponFitting.from_dictionary(fit_state as Dictionary)
		if parsed.ok:
			var _fitted: Variant = call("fit", def.slot, parsed.value)
	for w in weapons_in(def.slot):
		if w.id() == def.id:
			w.magazine = clampi(int(state.get("magazine", 0)), 0, maxi(w.def.magazine, 0))
			if state.has("fm"):
				w.fire_mode_index = clampi(int(state["fm"]), 0, maxi(w.def.allowed_fire_modes().size() - 1, 0))
	if def.ammo_type != &"" and int(state.get("reserve", 0)) > 0:
		var _added := add_ammo(def.ammo_type, int(state["reserve"]))
	carried_changed.emit()


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
		DotLog.debug(CHANNEL, "fire mode changed", {"weapon": String(s.id()), "mode": DotWeaponDef.Fire.keys()[mode], "index": i})
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
