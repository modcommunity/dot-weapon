class_name DotWeaponDrops
extends Node3D

## Weapons lying in the world after a player dropped or died with them: the authority simulates
## each as a rigid body, a client snaps to its resting place. The game carries the signals and
## answers with [code]mirror_*[/code]; setup is in docs/design.md.

const CHANNEL := "weapon.drop"
const SETTLE_SPEED := 0.08
const SETTLE_SEC := 0.6
## A drop still wobbling after this long (a thin gun on a slope) is put to rest where it lies.
const SETTLE_MAX_SEC := 4.0
## Cap on how far a thrown weapon may start from the player, so a wall in front cannot swallow it.
const REACH := 0.5
## The box of a weapon with no model.
const DEFAULT_SIZE := Vector3(0.12, 0.14, 0.7)
## Spare bodies kept per weapon for reuse.
const MAX_PARKED := 8
## A moving drop this far below where it was dropped or last pushed is put back there once, then removed: it fell through
## the world, and [constant SETTLE_MAX_SEC] would otherwise freeze it in mid-air.
const RESCUE_DEPTH := 40.0
## Times one drop is put back on a floor it fell through before it is frozen where it was put.
const RESCUE_MAX := 3

## A weapon left a hand (or a corpse): [param state] is [code]{id, magazine, reserve}[/code].
signal dropped(drop_id: int, state: Dictionary, at: Transform3D, velocity: Vector3, owner_id: int)
## Ammunition moved between a dropped weapon and a carrier; [param state] is what still lies there.
signal ammo_changed(drop_id: int, state: Dictionary)
## A shot, blast or melee hit set a resting weapon moving again; clients simulate on from here.
signal pushed(drop_id: int, at: Transform3D, velocity: Vector3, spin: Vector3)
## A weapon came to rest at [param at]; clients snap to it.
signal settled(drop_id: int, at: Transform3D)
## A weapon left the world: [param taker_id] is who took it, or 0 for expiry and the cap.
signal removed(drop_id: int, taker_id: int)

var rules: DotWeaponDropRules = DotWeaponDropRules.new()
var is_authority: bool = false
## False on a headless server: no visuals are built.
var draws: bool = true
## [code]look_of.call(weapon_id) -> Node3D[/code] or null for a plain box.
var look_of: Callable = Callable()
## What a dropped weapon collides with.
var collision_mask: int = 1
## Slots whose weapons never drop (a permanent melee weapon).
var keep_slots: Array[int] = []

## [code]team_of.call(player_id) -> int[/code]: 0 for no team (free-for-all, teams off). Stamps each drop
## with its dropper's team and reads the taker's; unset means no teams.
var team_of: Callable = Callable()

var _entries: Dictionary = {}   ## int -> Dictionary {body, state, age, rest, owner, order, team}
var _fits: Dictionary = {}   ## StringName -> [size, centre] of a weapon's model box
## StringName -> Array of [body, size]: bodies out of the tree, reused by the next drop of that weapon (no model rebuilt).
var _parked: Dictionary = {}
var _material: PhysicsMaterial = null
var _next_id: int = 1
var _order: int = 0
## Seconds this layer has been ticked; stamps `touched`.
var _clock: float = 0.0
var _scan_left: float = 0.0


func count() -> int:
	return _entries.size()


func has_drop(drop_id: int) -> bool:
	return _entries.has(drop_id)


## Drops the weapon [param arsenal] holds, thrown along [param aim] at the class's force, then lets
## the carrier take a weapon within reach into the slot just emptied. Returns the new drop id, or 0.
## [param source] is a player class def or null.
func throw(arsenal: Object, origin: Vector3, aim: Vector3, owner_id: int, source: Object = null,
		inherit: Vector3 = Vector3.ZERO) -> int:
	var r := rules.resolve(source)
	if not is_authority or not r.enabled or not r.key_enabled:
		return 0
	var state: Dictionary = arsenal.call(&"drop_current", keep_slots)
	if state.is_empty():
		return 0
	var dir := aim.normalized() if aim.length() > 0.001 else Vector3.FORWARD
	var velocity := inherit + dir * r.throw_force + Vector3.UP * r.throw_up
	var id := spawn(state, origin + dir * REACH, velocity, owner_id, r)
	if r.swap:
		var _took := _take_near(arsenal, origin, owner_id, rules.resolve(source))
	return id


## Drops [param state] where a player died (no throw, a small tumble).
func drop_dead(arsenal: Object, origin: Vector3, velocity: Vector3, owner_id: int, source: Object = null) -> int:
	var r := rules.resolve(source)
	if not is_authority or not r.enabled or not r.on_death:
		return 0
	var state: Dictionary = arsenal.call(&"drop_current", keep_slots)
	if state.is_empty():
		return 0
	return spawn(state, origin, velocity, owner_id, r)


## Puts a weapon in the world. [param r] is the rules in force (class overrides applied).
func spawn(state: Dictionary, origin: Vector3, velocity: Vector3, owner_id: int, r: DotWeaponDropRules = null) -> int:
	r = r if r != null else rules
	var id := _next_id
	_next_id += 1
	var facing := velocity.normalized() if velocity.length() > 0.1 else Vector3.FORWARD
	if r.lie_flat:
		# Its long axis starts horizontal, rolled onto its side, so a throw straight up lands flat, not on end.
		facing = Vector3(facing.x, 0.0, facing.z)
		facing = facing.normalized() if facing.length() > 0.05 else Vector3.FORWARD
	# A drop thrown straight up is colinear with the default up vector and warns.
	var up := Vector3.FORWARD if absf(facing.dot(Vector3.UP)) > 0.999 else Vector3.UP
	var basis := Basis.looking_at(facing, up)
	if r.lie_flat:
		basis = basis.rotated(facing, deg_to_rad(90.0 + randf_range(-25.0, 25.0)))
	var at := Transform3D(basis, origin)
	_make(id, state, at, velocity, owner_id, r.lifetime, r.pickup_delay, _team(owner_id))
	dropped.emit(id, state, at, velocity, owner_id)
	# A burst of deaths is held to the cap at once; lifetime waits for the scan.
	_enforce_cap(r.max_count, id)
	_enforce_active(id)
	return id


## The weapon within reach whose slot [param arsenal] has empty goes into it. Returns the drop id, or 0.
## Automatic pickup: does nothing unless [member DotWeaponDropRules.auto_pickup] is on, so a game cannot forget the gate.
func take_for(arsenal: Object, position: Vector3, taker_id: int, source: Object = null) -> int:
	if not is_authority or arsenal == null:
		return 0
	var r := rules.resolve(source)
	if not r.auto_pickup:
		return 0
	return _take_near(arsenal, position, taker_id, r)


func _take_near(arsenal: Object, position: Vector3, taker_id: int, r: DotWeaponDropRules) -> int:
	if not is_authority or arsenal == null:
		return 0
	return _take(arsenal, _nearest(arsenal, position, Vector3.ZERO, r.pickup_radius, _team(taker_id), true), taker_id, r, false, false, position)


## The use key. A tap ([param held] false) takes the drop looked at into a free slot, or unloads its ammunition
## into the same weapon carried (overflow stays); a different weapon is replaced at once. A hold ([DotWeaponUseHold])
## over the same weapon replaces it fully, attachments trading. Returns the drop id, or 0.
func use(arsenal: Object, position: Vector3, direction: Vector3, taker_id: int, source: Object = null, held: bool = false) -> int:
	if not is_authority or arsenal == null:
		return 0
	var r := rules.resolve(source)
	return _take(arsenal, _nearest(arsenal, position, direction, r.use_radius, _team(taker_id)), taker_id, r, held, true, position)


## What a "press use" prompt shows for the drop [param position] looks at: {id, weapon, magazine,
## reserve, can_take}, or empty when none is in reach. Works on a client, from what it was told.
func prompt_for(arsenal: Object, position: Vector3, direction: Vector3, source: Object = null, taker_team: int = 0) -> Dictionary:
	var id := _nearest(null, position, direction, rules.resolve(source).use_radius, taker_team)
	if id == 0:
		return {}
	var state: Dictionary = _entries[id]["state"]
	var can := true
	if arsenal != null and arsenal.get(&"catalogue") != null:
		can = arsenal.get(&"catalogue").call(&"get_def", StringName(state["id"])) != null
	var mode := "take"
	var hold := false
	var ammo_ok := false
	if can and arsenal != null and arsenal.get(&"catalogue") != null:
		var def: Object = arsenal.get(&"catalogue").call(&"get_def", StringName(state["id"]))
		var slot_no: int = def.get(&"slot")
		if bool(arsenal.call(&"carries", StringName(state["id"]))):
			mode = "ammo"
			hold = true
		elif arsenal.call(&"has_slot", slot_no) and arsenal.call(&"weapons_in", slot_no).size() >= int(arsenal.call(&"slot_capacity")):
			mode = "swap"
			hold = rules.resolve(source).swap_hold
		if mode != "take":
			ammo_ok = _ammo_fits(arsenal, state, def)
	return {"id": id, "weapon": StringName(state["id"]), "magazine": state.get("magazine", 0),
		"reserve": state.get("reserve", 0), "can_take": can, "mode": mode, "hold": hold, "ammo_ok": ammo_ok,
		"at": (_entries[id]["body"] as Node3D).global_position, "fitted": state.has("fit")}


## Whether a tap could move any of the drop's rounds into [param arsenal]: the weapon in that slot draws on the same pool and the pool has room.
func _ammo_fits(arsenal: Object, state: Dictionary, def: Object) -> bool:
	var pool: StringName = def.get(&"ammo_type")
	if pool == &"" or int(state.get("reserve", 0)) + int(state.get("magazine", 0)) <= 0:
		return false
	var in_slot: Array = arsenal.call(&"weapons_in", def.get(&"slot"))
	if in_slot.is_empty() or in_slot[0].def.ammo_type != pool:
		return false
	var ammo: Object = arsenal.call(&"ammo")
	return ammo == null or int(ammo.call(&"cap", pool)) <= 0 or int(ammo.call(&"count", pool)) < int(ammo.call(&"cap", pool))


## The best drop within [param radius] of [param position]; with [param arsenal], only one whose slot is empty.
## A drop in front of [param direction] beats one behind at the same distance.
func _nearest(arsenal: Object, position: Vector3, direction: Vector3, radius: float, taker_team: int = 0, empty_only: bool = false) -> int:
	if not rules.allow_pickup:
		return 0
	var best := 0
	var best_score := INF
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if float(e["delay"]) > 0.0:
			continue
		if rules.team_only and taker_team != 0 and int(e["team"]) != 0 and int(e["team"]) != taker_team:
			continue
		if arsenal != null:
			var def: Object = arsenal.get(&"catalogue").call(&"get_def", StringName(e["state"]["id"]))
			if def == null or (empty_only and arsenal.call(&"has_slot", def.get(&"slot"))):
				continue
		var offset := (e["body"] as Node3D).global_position - position
		var d := offset.length()
		if d > radius:
			continue
		var facing := offset.normalized().dot(direction.normalized()) if direction != Vector3.ZERO and d > 0.01 else 0.0
		var score := d - facing * 0.5
		if score < best_score:
			best = id
			best_score = score
	return best


func _team(player_id: int) -> int:
	return int(team_of.call(player_id)) if team_of.is_valid() else 0


## The team stamped on drop [param drop_id] when it was dropped (0 none).
func drop_team(drop_id: int) -> int:
	return int(_entries[drop_id]["team"]) if _entries.has(drop_id) else 0


## Takes drop [param best] into [param arsenal]. A free slot takes it with its ammunition and attachments as
## it lay. The same weapon twice unloads its ammunition into the reserve (the overflow stays), or with
## [param held] trades fittings. A different weapon already in the slot is swapped out onto the floor at [param taker_at], where the taker stands, not where the taken weapon lay.
func _take(arsenal: Object, best: int, taker_id: int, r: DotWeaponDropRules = null, held: bool = false, keyed: bool = false, taker_at: Vector3 = Vector3.INF) -> int:
	if best == 0:
		return 0
	var e: Dictionary = _entries[best]
	var state: Dictionary = e["state"]
	var id := StringName(state["id"])
	var def: Object = arsenal.get(&"catalogue").call(&"get_def", id)
	var swapped: Dictionary = {}
	var was_current := false
	if def != null and arsenal.call(&"has_slot", def.get(&"slot")):
		var slot_no: int = def.get(&"slot")
		if bool(arsenal.call(&"carries", id)):
			return _replace_same(arsenal, best, def, taker_id) if held and keyed else _unload(arsenal, best, def, taker_id)
		var in_slot: Array = arsenal.call(&"weapons_in", slot_no)
		if in_slot.size() >= int(arsenal.call(&"slot_capacity")):
			if keyed and not held and r != null and r.swap_hold:
				return _unload(arsenal, best, def, taker_id) if in_slot[0].def.ammo_type == def.get(&"ammo_type") else 0
			was_current = int(arsenal.call(&"current_slot")) == slot_no
			swapped = arsenal.call(&"drop_from_slot", slot_no, keep_slots)
			if swapped.is_empty():
				return 0
	var given: Object = arsenal.call(&"give", id, false)
	if given == null or not given.get(&"ok"):
		if not swapped.is_empty():
			var _undo: Object = arsenal.call(&"give", StringName(swapped["id"]), false)
			arsenal.call(&"apply_dropped", swapped)
		return 0
	arsenal.call(&"apply_dropped", state)
	if was_current:
		arsenal.call(&"bring_to_hand", def.get(&"slot"))
	var where: Vector3 = (e["body"] as Node3D).global_position if not taker_at.is_finite() else taker_at
	_remove(best, taker_id)
	if not swapped.is_empty():
		var _back := spawn(swapped, where, Vector3.UP * 1.5, taker_id, r)
	return best


## Holding the use key over the weapon already in hand replaces it with the drop's: magazine, fitting and fire
## mode trade places (the one in hand lands on the floor as it was), while the reserve stays with its owner so
## ammunition is conserved. Returns the drop id, or 0 when the two are identical.
func _replace_same(arsenal: Object, best: int, def: Object, taker_id: int) -> int:
	var state: Dictionary = _entries[best]["state"]
	var slot_no: int = def.get(&"slot")
	var front: Array = arsenal.call(&"weapons_in", slot_no)
	if front.is_empty() or front[0].call(&"id") != def.get(&"id"):
		return 0
	var mine: Object = front[0]
	var held_mag: int = mine.magazine
	var held_fm: int = mine.fire_mode_index
	var held_fit: Dictionary = {}
	var traded_fit := arsenal.get(&"attachments") != null
	if traded_fit:
		var fitting: Object = arsenal.call(&"fitting_at", slot_no)
		if fitting != null and not bool(fitting.call(&"is_empty")):
			held_fit = fitting.call(&"to_dictionary")
	var new_fit: Dictionary = state.get("fit", {}) if state.get("fit", null) is Dictionary else {}
	var new_mag := clampi(int(state.get("magazine", 0)), 0, maxi(int(def.get(&"magazine")), 0))
	var new_fm := int(state.get("fm", 0))
	if held_mag == new_mag and held_fm == new_fm and (not traded_fit or held_fit == new_fit):
		return 0
	if traded_fit and held_fit != new_fit:
		var incoming := DotWeaponFitting.make(def.get(&"id"))
		if not new_fit.is_empty():
			var parsed := DotWeaponFitting.from_dictionary(new_fit)
			if not parsed.ok:
				return 0
			incoming = parsed.value
		var applied: Object = arsenal.call(&"fit", slot_no, incoming)
		if applied == null or not bool(applied.get(&"ok")):
			return 0
		if held_fit.is_empty():
			state.erase("fit")
		else:
			state["fit"] = held_fit
	mine.magazine = new_mag
	mine.fire_mode_index = clampi(new_fm, 0, maxi(mine.def.allowed_fire_modes().size() - 1, 0))
	state["magazine"] = held_mag
	if held_fm != 0:
		state["fm"] = held_fm
	else:
		state.erase("fm")
	_entries[best]["touched"] = _clock
	ammo_changed.emit(best, state)
	return best


## Moves a dropped weapon's ammunition (reserve first, then the magazine) into [param arsenal]'s pool of
## the same weapon, as far as the pool has room; what does not fit stays in the drop.
func _unload(arsenal: Object, best: int, def: Object, taker_id: int) -> int:
	var state: Dictionary = _entries[best]["state"]
	var pool: StringName = def.get(&"ammo_type")
	var reserve := int(state.get("reserve", 0))
	var mag := int(state.get("magazine", 0))
	if pool == &"" or reserve + mag <= 0:
		return 0
	var added := int(arsenal.call(&"add_ammo", pool, reserve + mag))
	if added <= 0:
		return 0
	if added >= reserve + mag:
		_remove(best, taker_id)
		return best
	var from_reserve := mini(added, reserve)
	state["reserve"] = reserve - from_reserve
	state["magazine"] = mag - (added - from_reserve)
	_entries[best]["touched"] = _clock
	ammo_changed.emit(best, state)
	return best


## Removes every drop (a new round); each says it is gone.
func clear() -> void:
	for id: int in _entries.keys():
		_remove(id, 0)


## Ages, settles and expires the drops. Call every physics frame (the node does when added to a tree).
func tick(delta: float) -> void:
	_clock += delta
	for id: int in _entries.keys():
		var e: Dictionary = _entries[id]
		e["delay"] = maxf(float(e["delay"]) - delta, 0.0)
		e["age"] = float(e["age"]) + delta
		var body: RigidBody3D = e["body"]
		# A slow launch still gathers speed falling; switch CCD on once one tick's travel passes half the box's thinnest side.
		# Mirrors fall on their own too, so this runs on the client as well.
		if not bool(e["rest"]) and not body.continuous_cd:
			var thin: float = minf(minf((e["size"] as Vector3).x, (e["size"] as Vector3).y), (e["size"] as Vector3).z)
			body.continuous_cd = body.linear_velocity.length() * delta > thin * 0.5
		if not bool(e["rest"]) and rules.rescue and _rescue(id, e, body):
			continue
		if not is_authority:
			continue
		if not bool(e["rest"]):
			if body.linear_velocity.length() < SETTLE_SPEED and body.angular_velocity.length() < SETTLE_SPEED * 2.0:
				e["still"] = float(e["still"]) + delta
			else:
				e["still"] = 0.0
				e["touched"] = _clock
			e["moving"] = float(e.get("moving", 0.0)) + delta
			if float(e["still"]) >= rules.sleep_time and rules.lie_flat and _topple(e, body):
				e["still"] = 0.0
			elif float(e["still"]) >= rules.sleep_time or float(e["moving"]) >= SETTLE_MAX_SEC:
				_rest(id, e, body)
		elif body.global_position.y < -200.0:
			_remove(id, 0)
	if is_authority:
		_scan_left = minf(_scan_left, rules.scan_interval) - delta
		if _scan_left <= 0.0:
			_scan_left = rules.scan_interval
			scan()


## Puts a moving drop back on the floor its centre passed down through since the last tick (the solver tunnelled it, about
## once in 3000 drops on a bumpy trimesh floor), or at its drop point once it fell [constant RESCUE_DEPTH]
## below it. [code]last[/code] stays above a floor the centre is only slightly into (contact slop). Returns true when it moved or removed it.
func _rescue(id: int, e: Dictionary, body: RigidBody3D) -> bool:
	var pos := body.global_position
	var last: Vector3 = e["last"]
	if pos.y < (e["origin"] as Vector3).y - RESCUE_DEPTH:
		if is_authority and int(e.get("lost", 0)) >= 1:
			_remove(id, 0)
			return true
		e["lost"] = int(e.get("lost", 0)) + 1
		_place(id, e, body, Transform3D(body.global_basis, e["origin"]))
		return true
	if pos.distance_squared_to(last) < 0.000001 or not is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(last, pos, collision_mask)
	q.hit_back_faces = false
	var space := get_world_3d().direct_space_state
	for _i in 3:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var n: Vector3 = hit["normal"]
		var other: Object = hit["collider"]
		if other is CharacterBody3D or other is RigidBody3D or other is AnimatableBody3D or n.y < 0.3:
			var skip: Array[RID] = q.exclude
			skip.append(hit["rid"])
			q.exclude = skip
			continue
		var floor_at: Vector3 = hit["position"]
		var reach := _support(body, n)
		if (floor_at - pos).dot(n) <= reach + 0.02:
			return false
		var count := int(e.get("rescued", 0)) + 1
		e["rescued"] = count
		var at := Transform3D(body.global_basis, floor_at + n * (reach + 0.15) - body.global_basis * _centre(body))
		DotLog.debug(CHANNEL, "drop fell through a floor; put back", {"id": id, "times": count})
		_place(id, e, body, at)
		if count > RESCUE_MAX and is_authority:
			_rest(id, e, body)
		return true
	e["last"] = pos
	return false


## Moves a moving drop to [param at], still, and tells clients.
func _place(id: int, e: Dictionary, body: RigidBody3D, at: Transform3D) -> void:
	body.global_transform = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	e["last"] = at.origin
	e["still"] = 0.0
	e["moving"] = 0.0
	if is_authority:
		_announce_push(id)


## Half the drop's box measured along [param n], in its current pose.
func _support(body: RigidBody3D, n: Vector3) -> float:
	var half := _half_extents(body)
	var b := body.global_basis
	return absf(b.x.normalized().dot(n)) * half.x + absf(b.y.normalized().dot(n)) * half.y + absf(b.z.normalized().dot(n)) * half.z


## Nudges a drop propped on end or edge (its long axis steeper than about 20 degrees) so it falls over before it sleeps.
## Returns true when it nudged; gives up after a few tries so a drop wedged in a corner still sleeps.
func _topple(e: Dictionary, body: RigidBody3D) -> bool:
	if int(e.get("topples", 0)) >= 4:
		return false
	var size: Vector3 = e["size"]
	var axis := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	var long_world: Vector3 = body.global_transform.basis[axis].normalized()
	if absf(long_world.y) < 0.35:
		return false
	e["topples"] = int(e.get("topples", 0)) + 1
	var away := Vector3(long_world.x, 0.0, long_world.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	body.apply_torque_impulse(Vector3.UP.cross(away) * body.mass * 0.6)
	body.sleeping = false
	return true


## Freezes a drop in place. The solver leaves a thin box a few centimetres inside the floor
## (contact slop), so the penetration is resolved first and the drop freezes on the surface.
func _rest(id: int, e: Dictionary, body: RigidBody3D) -> void:
	var hit := KinematicCollision3D.new()
	for _i in 4:
		if not body.test_move(body.global_transform, Vector3.ZERO, hit, 0.001, true, 4):
			break
		var out := hit.get_travel()
		if out.length() < 0.0005:
			break
		body.global_position += out
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	e["rest"] = true
	body.freeze = true
	settled.emit(id, body.global_transform)


func _physics_process(delta: float) -> void:
	tick(delta)


## Everything lying, for a joiner: [code]{id, state, at, rest}[/code] each.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		out.append({"id": id, "state": e["state"], "at": (e["body"] as Node3D).global_transform, "rest": e["rest"], "team": e["team"], "life": maxf(float(e["life"]) - float(e["age"]), 0.0) if float(e["life"]) > 0.0 else 0.0})
	return out


## Client side: the authority dropped a weapon.
func mirror_drop(drop_id: int, state: Dictionary, at: Transform3D, velocity: Vector3, life: float = 0.0, rest: bool = false, team: int = 0) -> void:
	if _entries.has(drop_id):
		# Seen already: this is the authority re-announcing it after a push or an ammunition change.
		mirror_ammo(drop_id, state)
		if not rest:
			mirror_pushed(drop_id, at, velocity, Vector3.ZERO)
		return
	_make(drop_id, state, at, velocity, 0, life, 0.0, team)
	if rest:
		mirror_settled(drop_id, at)


func mirror_settled(drop_id: int, at: Transform3D) -> void:
	if not _entries.has(drop_id):
		return
	var e: Dictionary = _entries[drop_id]
	var body: RigidBody3D = e["body"]
	body.freeze = true
	body.global_transform = at
	e["rest"] = true


## Client side: the authority's drop [param drop_id] was pushed; wake it and simulate on from there.
func mirror_pushed(drop_id: int, at: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if not _entries.has(drop_id):
		return
	var e: Dictionary = _entries[drop_id]
	var body: RigidBody3D = e["body"]
	body.freeze = false
	body.global_transform = at
	body.linear_velocity = velocity
	body.angular_velocity = spin
	e["rest"] = false
	e["origin"] = at.origin
	e["last"] = at.origin


## The state, pose and rest flag of a drop, for re-announcing it: {state, at, velocity, rest}, or empty.
func pose_of(drop_id: int) -> Dictionary:
	if not _entries.has(drop_id):
		return {}
	var e: Dictionary = _entries[drop_id]
	var body: RigidBody3D = e["body"]
	return {"state": e["state"], "at": body.global_transform, "velocity": body.linear_velocity, "rest": bool(e.get("rest", false))}


## Client side: ammunition left on a dropped weapon changed.
func mirror_ammo(drop_id: int, state: Dictionary) -> void:
	if _entries.has(drop_id):
		_entries[drop_id]["state"] = state


## The drop a segment from [param from] to [param to] crosses first, as {id, point, distance}, or empty.
## Boxes are tested in their own frame, so no physics layer is needed and the shot trace stays untouched.
func raycast(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	var seg := to - from
	var length := seg.length()
	if length < 0.0001:
		return best
	for id: int in _entries:
		var body: RigidBody3D = _entries[id]["body"]
		var inv := body.global_transform.affine_inverse()
		var o := inv * from
		var d := inv.basis * (seg / length)
		var half := _half_extents(body)
		var centre := _centre(body)
		var tmin := 0.0
		var tmax := length
		var ok := true
		for axis in 3:
			var lo := centre[axis] - half[axis]
			var hi := centre[axis] + half[axis]
			if absf(d[axis]) < 0.00001:
				if o[axis] < lo or o[axis] > hi:
					ok = false
					break
			else:
				var t1 := (lo - o[axis]) / d[axis]
				var t2 := (hi - o[axis]) / d[axis]
				tmin = maxf(tmin, minf(t1, t2))
				tmax = minf(tmax, maxf(t1, t2))
				if tmin > tmax:
					ok = false
					break
		if ok and tmin < best_t:
			best_t = tmin
			best = {"id": id, "point": from + seg / length * tmin, "distance": tmin}
	return best


## A shot or melee hit along [param direction] at [param point] shoves drop [param drop_id] with
## [param momentum] (kilogram metres per second). Returns false when drops are not shootable here.
func hit(drop_id: int, point: Vector3, direction: Vector3, momentum: float) -> bool:
	if not is_authority or not rules.shootable or not _entries.has(drop_id):
		return false
	var body: RigidBody3D = _entries[drop_id]["body"]
	_wake(drop_id)
	var impulse := direction.normalized() * momentum * rules.impulse_scale
	# Set directly: the engine folds an impulse in at the next step, and clients are told the result now.
	body.linear_velocity += impulse / body.mass
	body.angular_velocity += (point - body.global_position).cross(impulse) / body.mass * 6.0
	_announce_push(drop_id)
	return true


## Optional [code]func(from: Vector3, to: Vector3) -> bool[/code] that says whether an explosion at [code]from[/code]
## reaches [code]to[/code]; a game assigns its combat trace's [code]line_of_sight[/code] so walls shield drops as they do players.
var can_see: Callable = Callable()


## An explosion at [param centre]: every drop within [param radius] is thrown outward, harder the closer.
## [param strength] is the impulse at the centre. Returns how many moved.
func blast(centre: Vector3, radius: float, strength: float) -> int:
	if not is_authority or not rules.shootable or radius <= 0.0 or rules.blast_scale <= 0.0:
		return 0
	var n := 0
	for id: int in _entries.keys():
		var body: RigidBody3D = _entries[id]["body"]
		var offset := body.global_position - centre
		var d := offset.length()
		if d > radius:
			continue
		if can_see.is_valid() and not can_see.call(centre, body.global_position):
			continue
		var fall := 1.0 - d / radius
		var dir := (offset / d if d > 0.01 else Vector3.UP) + Vector3.UP * 0.35
		_wake(id)
		body.linear_velocity += dir.normalized() * strength * fall * rules.blast_scale / body.mass
		body.angular_velocity += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * fall * 0.5 / body.mass
		_announce_push(id)
		n += 1
	return n


## Drops that are moving right now.
func active_count() -> int:
	var n := 0
	for id: int in _entries:
		if not bool(_entries[id]["rest"]):
			n += 1
	return n


func _wake(id: int) -> void:
	var e: Dictionary = _entries[id]
	e["touched"] = _clock
	var body: RigidBody3D = e["body"]
	if bool(e["rest"]):
		e["rest"] = false
		body.freeze = false
	e["still"] = 0.0
	e["moving"] = 0.0
	e["origin"] = body.global_position
	e["last"] = body.global_position
	_enforce_active(id)


## Rests the oldest moving drops until no more than [member DotWeaponDropRules.max_active] are awake, never [param keep]. A burst of deaths (a whole team at once) otherwise steps every body together, one physics step costing 200 ms.
func _enforce_active(keep: int) -> void:
	var cap := rules.max_active
	while cap > 0 and active_count() > cap:
		var oldest := 0
		var order := 1 << 60
		for other: int in _entries:
			if other != keep and not bool(_entries[other]["rest"]) and int(_entries[other]["order"]) < order:
				order = int(_entries[other]["order"])
				oldest = other
		if oldest == 0:
			break
		_rest(oldest, _entries[oldest], _entries[oldest]["body"])


func _announce_push(id: int) -> void:
	var body: RigidBody3D = _entries[id]["body"]
	pushed.emit(id, body.global_transform, body.linear_velocity, body.angular_velocity)


func _half_extents(body: RigidBody3D) -> Vector3:
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size * 0.5
	return Vector3(0.06, 0.07, 0.35)


func _centre(body: RigidBody3D) -> Vector3:
	for c in body.get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).position
	return Vector3.ZERO


func mirror_removed(drop_id: int) -> void:
	_remove(drop_id, -1, false)


func describe() -> Dictionary:
	return {"count": _entries.size(), "authority": is_authority, "rules": rules.describe()}


func _make(id: int, state: Dictionary, at: Transform3D, velocity: Vector3, owner_id: int, life: float, delay: float, team: int = 0) -> void:
	var weapon := StringName(state["id"])
	var body: RigidBody3D = null
	var size := DEFAULT_SIZE
	var parked: Array = _parked.get(weapon, [])
	while not parked.is_empty() and body == null:
		var spare: Array = parked.pop_back()
		if spare[0].get_meta(&"draws", false) != draws:
			(spare[0] as Node).free()
			continue
		body = spare[0]
		size = spare[1]
	if body != null:
		_configure(body)
		add_child(body)
		body.global_transform = at
		body.freeze = false
		body.sleeping = false
	else:
		var built := _build(weapon, at)
		body = built[0]
		size = built[1]
	body.name = "Drop%d" % id
	body.continuous_cd = rules.ccd_speed <= 0.0 or velocity.length() >= rules.ccd_speed
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0)) if is_authority else Vector3.ZERO
	_order += 1
	_entries[id] = {"body": body, "state": state, "age": 0.0, "life": life, "delay": delay,
		"still": 0.0, "rest": false, "size": size, "owner": owner_id, "order": _order, "team": team, "touched": _clock,
		"origin": at.origin, "last": at.origin}
	DotLog.debug(CHANNEL, "weapon dropped", {"id": id, "weapon": String(state.get("id", &""))})


## Builds the body, model and box for [param weapon] at [param at] and adds it to the tree. Returns [body, size].
func _build(weapon: StringName, at: Transform3D) -> Array:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = collision_mask
	body.linear_damp = 0.15
	body.angular_damp = 1.2
	body.set_meta(&"weapon", weapon)
	body.set_meta(&"draws", draws)
	_configure(body)
	add_child(body)
	body.global_transform = at
	var look: Node3D = look_of.call(weapon) if look_of.is_valid() and (draws or not _fits.has(weapon)) else null
	var size := DEFAULT_SIZE
	var centre := Vector3.ZERO
	if look == null and _fits.has(weapon):
		size = _fits[weapon][0]
		centre = _fits[weapon][1]
	if look != null:
		# A server draws nothing but must rest the same box a client's model fills, or the client's
		# mesh sinks into (or floats off) the floor where the server's box came to rest.
		body.add_child(look)
		var fit := _fit_of(weapon, look)
		size = fit[0]
		centre = fit[1]
		if not draws:
			body.remove_child(look)
			look.free()
	body.add_child(_shape(size, centre))
	if draws and look == null:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		body.add_child(mesh)
	return [body, size]


## Applies the current rules to a new or reused body, so a cvar changed between drops still takes.
func _configure(body: RigidBody3D) -> void:
	body.mass = rules.mass
	# One material per setting, shared by every body, rather than a Resource per drop.
	if _material == null or _material.friction != rules.friction or _material.bounce != rules.bounce:
		_material = PhysicsMaterial.new()
		_material.friction = rules.friction
		_material.bounce = rules.bounce
	body.physics_material_override = _material


## Builds [param count] bodies of [param weapon] now and keeps them out of the tree for the next drops, so the first throw does not pay for the model. Call under the loading cover.
func prewarm(weapon: StringName, count: int = 1) -> void:
	for _i in mini(count, MAX_PARKED):
		var built := _build(weapon, Transform3D.IDENTITY)
		_park(built[0], weapon, built[1])


func _park(body: RigidBody3D, weapon: StringName, size: Vector3) -> void:
	var parked: Array = _parked.get(weapon, [])
	if parked.size() >= MAX_PARKED:
		body.queue_free() if body.is_inside_tree() else body.free()
		return
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	parked.append([body, size])
	_parked[weapon] = parked


func _exit_tree() -> void:
	for weapon: StringName in _parked:
		for spare: Array in _parked[weapon]:
			if is_instance_valid(spare[0]):
				(spare[0] as Node).free()
	_parked.clear()


## The collision box [size, centre] of [param look] (inside the tree), measured once per weapon.
func _fit_of(weapon: StringName, look: Node3D) -> Array:
	if _fits.has(weapon):
		return _fits[weapon]
	var box := _bounds(look)
	var fit: Array = [box.size.max(Vector3.ONE * 0.06), box.get_center()] if box.size.length() > 0.05 else [DEFAULT_SIZE, Vector3.ZERO]
	_fits[weapon] = fit
	return fit


func _shape(size: Vector3, centre: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = centre
	return shape


func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.has_method(&"get_aabb"):
			var m := n as MeshInstance3D
			var rel := root.global_transform.affine_inverse() * m.global_transform if root.is_inside_tree() else m.transform
			var box := rel * m.get_aabb()
			out = box if first else out.merge(box)
			first = false
		stack.append_array(n.get_children())
	return out


## One cleanup pass (server): removes every drop past its lifetime, then the [member DotWeaponDropRules.evict] picks until the cap holds.
## [method tick] runs it every [member DotWeaponDropRules.scan_interval]; a game may call it too. Returns how many it removed.
func scan() -> int:
	if not is_authority:
		return 0
	var gone := 0
	for id: int in _entries.keys():
		var e: Dictionary = _entries[id]
		if float(e["life"]) > 0.0 and float(e["age"]) >= float(e["life"]):
			_remove(id, 0)
			gone += 1
	return gone + _enforce_cap(rules.max_count)


func _enforce_cap(cap: int, keep: int = 0) -> int:
	var gone := 0
	while cap > 0 and _entries.size() > cap:
		var victim := _victim(keep)
		if victim == 0:
			break
		_remove(victim, 0)
		gone += 1
	return gone


## The drop the cap removes next under [member DotWeaponDropRules.evict], never [param keep]; 0 when there is none.
func _victim(keep: int) -> int:
	var ids: Array = _entries.keys()
	ids.erase(keep)
	if ids.is_empty():
		return 0
	if rules.evict == DotWeaponDropRules.EVICT_RANDOM:
		return int(ids[randi() % ids.size()])
	var best := 0
	var key := INF
	for id: int in ids:
		var e: Dictionary = _entries[id]
		var k := float(e["order"]) if rules.evict == DotWeaponDropRules.EVICT_OLDEST else float(e["touched"]) + float(e["order"]) * 1e-6
		if k < key:
			key = k
			best = id
	return best


func _remove(id: int, taker_id: int, tell: bool = true) -> void:
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty():
		return
	_entries.erase(id)
	var body: RigidBody3D = e["body"]
	if is_instance_valid(body):
		_park(body, body.get_meta(&"weapon", &""), e["size"])
	if tell:
		removed.emit(id, taker_id)
