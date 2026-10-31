class_name DotWeaponDrops
extends Node3D

## Weapons lying in the world after a player dropped or died with them. The authority simulates
## each as a rigid body, ages it, caps the count and hands it to whoever has the empty slot; a
## client draws the same body and snaps to the authority's resting place. The game carries the
## three signals over its net link and answers them with [code]mirror_*[/code].
##
## [codeblock]
## drops.rules = DotWeaponDropRules.new()
## drops.is_authority = true
## drops.look_of = func(weapon_id): return world_model_for(weapon_id)   # a Node3D, optional
## drops.dropped.connect(send_drop)
## drops.throw(arsenal, eye_origin, aim_dir, owner_id, class_def)      # the drop key
## [/codeblock]

const CHANNEL := "weapon.drop"
const SETTLE_SPEED := 0.08
const SETTLE_SEC := 0.6
## Cap on how far a thrown weapon may start from the player, so a wall in front cannot swallow it.
const REACH := 0.5

## A weapon left a hand (or a corpse): [param state] is [code]{id, magazine, reserve}[/code].
signal dropped(drop_id: int, state: Dictionary, at: Transform3D, velocity: Vector3, owner_id: int)
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
var _next_id: int = 1
var _order: int = 0


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
		var _took := take_for(arsenal, origin, owner_id, source)
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
	# A drop thrown straight up is colinear with the default up vector and warns.
	var up := Vector3.FORWARD if absf(facing.dot(Vector3.UP)) > 0.999 else Vector3.UP
	var at := Transform3D(Basis.looking_at(facing, up), origin)
	_make(id, state, at, velocity, owner_id, r.lifetime, r.pickup_delay, _team(owner_id))
	dropped.emit(id, state, at, velocity, owner_id)
	_enforce_cap(r.max_count)
	return id


## The weapon within reach whose slot [param arsenal] has empty goes into it. Returns the drop id, or 0.
## Automatic pickup: the arena leaves it to [member DotWeaponDropRules.auto_pickup].
func take_for(arsenal: Object, position: Vector3, taker_id: int, source: Object = null) -> int:
	if not is_authority or arsenal == null:
		return 0
	var r := rules.resolve(source)
	return _take(arsenal, _nearest(arsenal, position, Vector3.ZERO, r.pickup_radius, _team(taker_id), true), taker_id, r)


## The use key: takes the dropped weapon [param position] is looking at (or the nearest in
## [member DotWeaponDropRules.use_radius]) into its empty slot, ammo as it lay. Returns the drop id, or 0.
func use(arsenal: Object, position: Vector3, direction: Vector3, taker_id: int, source: Object = null) -> int:
	if not is_authority or arsenal == null:
		return 0
	var r := rules.resolve(source)
	return _take(arsenal, _nearest(arsenal, position, direction, r.use_radius, _team(taker_id)), taker_id, r)


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
	return {"id": id, "weapon": StringName(state["id"]), "magazine": state.get("magazine", 0),
		"reserve": state.get("reserve", 0), "can_take": can}


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


## Takes drop [param best] into [param arsenal]. A slot already holding a different weapon is no
## reason to refuse: with no room beside it the held one swaps out onto the floor; the same weapon
## twice gives its ammunition.
func _take(arsenal: Object, best: int, taker_id: int, r: DotWeaponDropRules = null) -> int:
	if best == 0:
		return 0
	var e: Dictionary = _entries[best]
	var state: Dictionary = e["state"]
	var id := StringName(state["id"])
	var def: Object = arsenal.get(&"catalogue").call(&"get_def", id)
	var swapped: Dictionary = {}
	if def != null and arsenal.call(&"has_slot", def.get(&"slot")):
		var slot_no: int = def.get(&"slot")
		if bool(arsenal.call(&"carries", id)):
			var pool: StringName = def.get(&"ammo_type")
			if pool == &"" or int(arsenal.call(&"add_ammo", pool, int(state.get("reserve", 0)) + int(state.get("magazine", 0)))) <= 0:
				return 0
			_remove(best, taker_id)
			return best
		var in_slot: Array = arsenal.call(&"weapons_in", slot_no)
		if in_slot.size() >= int(arsenal.call(&"slot_capacity")):
			var old: Object = arsenal.call(&"slot_at", slot_no)
			swapped = {"id": old.call(&"id"), "magazine": old.get(&"magazine"), "reserve": 0}
	var given: Object = arsenal.call(&"give", id, false)
	if given == null or not given.get(&"ok"):
		return 0
	arsenal.call(&"apply_dropped", state)
	var where: Vector3 = (e["body"] as Node3D).global_position
	_remove(best, taker_id)
	if not swapped.is_empty():
		var _back := spawn(swapped, where, Vector3.UP * 1.5, taker_id, r)
	return best


## Removes every drop (a new round); each says it is gone.
func clear() -> void:
	for id: int in _entries.keys():
		_remove(id, 0)


## Ages, settles and expires the drops. Call every physics frame (the node does when added to a tree).
func tick(delta: float) -> void:
	for id: int in _entries.keys():
		var e: Dictionary = _entries[id]
		e["delay"] = maxf(float(e["delay"]) - delta, 0.0)
		e["age"] = float(e["age"]) + delta
		var body: RigidBody3D = e["body"]
		if not is_authority:
			continue
		if float(e["life"]) > 0.0 and float(e["age"]) >= float(e["life"]):
			_remove(id, 0)
			continue
		if not bool(e["rest"]):
			if body.linear_velocity.length() < SETTLE_SPEED and body.angular_velocity.length() < SETTLE_SPEED * 2.0:
				e["still"] = float(e["still"]) + delta
			else:
				e["still"] = 0.0
			if float(e["still"]) >= SETTLE_SEC:
				e["rest"] = true
				body.freeze = true
				settled.emit(id, body.global_transform)
		elif body.global_position.y < -200.0:
			_remove(id, 0)


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


func mirror_removed(drop_id: int) -> void:
	_remove(drop_id, -1, false)


func describe() -> Dictionary:
	return {"count": _entries.size(), "authority": is_authority, "rules": rules.describe()}


func _make(id: int, state: Dictionary, at: Transform3D, velocity: Vector3, owner_id: int, life: float, delay: float, team: int = 0) -> void:
	var body := RigidBody3D.new()
	body.name = "Drop%d" % id
	body.collision_layer = 0
	body.collision_mask = collision_mask
	body.mass = 4.0
	body.continuous_cd = true
	body.linear_damp = 0.15
	body.angular_damp = 1.2
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.2
	body.physics_material_override = material
	add_child(body)
	body.global_transform = at
	var look: Node3D = look_of.call(StringName(state["id"])) if (draws and look_of.is_valid()) else null
	var size := Vector3(0.12, 0.14, 0.7)
	if look != null:
		body.add_child(look)
		var box := _bounds(look)
		if box.size.length() > 0.05:
			size = box.size.max(Vector3.ONE * 0.06)
			body.add_child(_shape(size, box.get_center()))
		else:
			body.add_child(_shape(size, Vector3.ZERO))
	else:
		body.add_child(_shape(size, Vector3.ZERO))
		if draws:
			var mesh := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mesh.mesh = bm
			body.add_child(mesh)
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0)) if is_authority else Vector3.ZERO
	_order += 1
	_entries[id] = {"body": body, "state": state, "age": 0.0, "life": life, "delay": delay,
		"still": 0.0, "rest": false, "owner": owner_id, "order": _order, "team": team}
	DotLog.debug(CHANNEL, "weapon dropped", {"id": id, "weapon": String(state.get("id", &""))})


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


func _enforce_cap(cap: int) -> void:
	while cap > 0 and _entries.size() > cap:
		var oldest := 0
		var order := 1 << 60
		for id: int in _entries:
			if int(_entries[id]["order"]) < order:
				order = int(_entries[id]["order"])
				oldest = id
		_remove(oldest, 0)


func _remove(id: int, taker_id: int, tell: bool = true) -> void:
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty():
		return
	_entries.erase(id)
	if is_instance_valid(e["body"]):
		(e["body"] as Node).queue_free()
	if tell:
		removed.emit(id, taker_id)
