extends "dot_weapon_drops_bodies.gd"

## The pushing half of [DotWeaponDrops]: shots, blasts and melee that set a lying weapon moving, and the cap on how many move.
## The drops layer extends this; use [DotWeaponDrops].

## A shot, blast or melee hit set a resting weapon moving again; clients simulate on from here.
signal pushed(drop_id: int, at: Transform3D, velocity: Vector3, spin: Vector3)
## Physics ticks between a cut-short rest and the sweep that puts the drop on the floor ([method _rest_grounded]).
const GROUND_TICKS := 2

## A weapon came to rest at [param at]; clients snap to it.
signal settled(drop_id: int, at: Transform3D)
var is_authority: bool = false
## Seconds this layer has been ticked; stamps `touched`.
var _clock: float = 0.0
## Optional [code]func(from: Vector3, to: Vector3) -> bool[/code] that says whether an explosion at [code]from[/code]
## reaches [code]to[/code]; a game assigns its combat trace's [code]line_of_sight[/code] so walls shield drops as they do players.
var can_see: Callable = Callable()


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
	e.erase("ground_in")
	e["still"] = 0.0
	e["moving"] = 0.0
	e["origin"] = body.global_position
	e["last"] = body.global_position
	_enforce_active(id)


func _announce_push(id: int) -> void:
	var body: RigidBody3D = _entries[id]["body"]
	pushed.emit(id, body.global_transform, body.linear_velocity, body.angular_velocity)


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


## Rests a drop that may still be in flight (the active cap or [constant SETTLE_MAX_SEC] cut it short):
## it freezes at once, and [constant GROUND_TICKS] ticks later one above the floor is swept down onto it,
## so no gun is frozen in the air. The wait lets geometry added the same frame reach the physics space.
func _rest_grounded(id: int, e: Dictionary, body: RigidBody3D) -> void:
	_rest(id, e, body)
	e["ground_in"] = GROUND_TICKS


## Rests the oldest moving drops until no more than [member DotWeaponDropRules.max_active] are awake,
## never [param keep]. A burst of deaths otherwise steps every body together (one physics step, 200 ms).
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
		_rest_grounded(oldest, _entries[oldest], _entries[oldest]["body"])
