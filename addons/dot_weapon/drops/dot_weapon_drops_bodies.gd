extends Node3D

## The bodies half of [DotWeaponDrops]: building, fitting, parking and sweeping the rigid bodies a dropped weapon is.
## The drops layer extends this; use [DotWeaponDrops].

## The box of a weapon with no model.
const DEFAULT_SIZE := Vector3(0.12, 0.14, 0.7)
## Spare bodies kept per weapon for reuse.
const MAX_PARKED := 8
## A grounded drop inside the floor is lifted in steps of this, up to [constant LIFT_MAX], to a clear pose.
const LIFT_STEP := 0.02
const LIFT_MAX := 0.3
## The grounding sweep goes down in legs of this (under the thinnest drop), so it cannot step through a thin edge.
const SWEEP_LEG := 0.05
var rules: DotWeaponDropRules = DotWeaponDropRules.new()
## False on a headless server: no visuals are built.
var draws: bool = true
## [code]look_of.call(weapon_id) -> Node3D[/code] or null for a plain box.
var look_of: Callable = Callable()
## What a dropped weapon collides with.
var collision_mask: int = 1
var _entries: Dictionary = {}   ## int -> Dictionary {body, state, age, rest, owner, order, team}
var _fits: Dictionary = {}   ## StringName -> [size, centre] of a weapon's model box
## StringName -> Array of [body, size]: bodies out of the tree, reused by the next drop of that weapon (no model rebuilt).
var _parked: Dictionary = {}
var _material: PhysicsMaterial = null
var _rids: Array[RID] = []


## The first floor (an upward face of a static body) the ray [param from]->[param to] passes down through, as [code]{position,
## normal}[/code] with the normal towards [param from]; empty for none. Back faces count (a trimesh wound the other way is still a
## floor; front-faces-only rays missed every tunnel). Walls, ceilings and moving bodies are passed through.
func _floor_hit(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	q.hit_back_faces = true
	var dir := (to - from).normalized()
	var space := get_world_3d().direct_space_state
	for _i in 6:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var n: Vector3 = hit["normal"]
		if n.dot(dir) > 0.0:
			n = -n
		var other: Object = hit["collider"]
		if other is CharacterBody3D or other is RigidBody3D or other is AnimatableBody3D:
			var skip: Array[RID] = q.exclude
			skip.append(hit["rid"])
			q.exclude = skip
			continue
		if n.y < 0.3:
			q.from = (hit["position"] as Vector3) + dir * 0.002
			if (to - q.from).dot(dir) <= 0.0:
				return {}
			continue
		return {"position": hit["position"], "normal": n}
	return {}


## Where [param body], in its current pose, lies [param gap] above [param floor_at] along [param n].
func _on_floor(body: RigidBody3D, floor_at: Vector3, n: Vector3, gap: float) -> Transform3D:
	return Transform3D(body.global_basis, floor_at + n * (_support(body, n) + gap) - body.global_basis * _centre(body))


## Half the drop's box measured along [param n], in its current pose.
func _support(body: RigidBody3D, n: Vector3) -> float:
	var half := _half_extents(body)
	var b := body.global_basis
	return absf(b.x.normalized().dot(n)) * half.x + absf(b.y.normalized().dot(n)) * half.y + absf(b.z.normalized().dot(n)) * half.z


## [param from] itself when clear of the world, else lifted straight up in [constant LIFT_STEP] steps (at most
## [constant LIFT_MAX]) to the first clear pose; the sweep after it brings the drop back down onto the surface.
func _lift_clear(body: RigidBody3D, from: Transform3D) -> Transform3D:
	if not _overlaps(body, from):
		return from
	var h := LIFT_STEP
	while h <= LIFT_MAX:
		var t := from.translated(Vector3.UP * h)
		if not _overlaps(body, t):
			return t
		h += LIFT_STEP
	return from


## [method _sweep] down in short legs, so a thin tread or crate edge cannot be stepped through in one long cast; a leg
## that ends inside the world is dropped and the sweep stops above it.
func _sweep_down(body: RigidBody3D, from: Transform3D, depth: float) -> Vector3:
	var done := 0.0
	var pos := from
	while done < depth:
		var leg := minf(SWEEP_LEG, depth - done)
		var step := _sweep(body, pos, Vector3.DOWN * leg)
		if step.length() < leg - 0.0001:
			return Vector3.DOWN * (done + step.length())
		var nxt := pos.translated(step)
		if _overlaps(body, nxt):
			return Vector3.DOWN * done
		pos = nxt
		done += leg
	return Vector3.DOWN * done


## How far [param body] at [param from] moves along [param motion] before it touches the world (other drops ignored).
func _sweep(body: RigidBody3D, from: Transform3D, motion: Vector3) -> Vector3:
	var q := PhysicsTestMotionParameters3D.new()
	q.from = from
	q.motion = motion
	q.margin = 0.001
	q.exclude_bodies = _drop_rids(body)
	var r := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), q, r):
		return motion
	return r.get_travel()


## True when [param body] at [param at] is inside the world (other drops ignored).
func _overlaps(body: RigidBody3D, at: Transform3D) -> bool:
	var q := PhysicsTestMotionParameters3D.new()
	q.from = at
	q.motion = Vector3.ZERO
	q.margin = 0.001
	q.recovery_as_collision = true
	q.exclude_bodies = _drop_rids(body)
	return PhysicsServer3D.body_test_motion(body.get_rid(), q, PhysicsTestMotionResult3D.new())


## The other drops' bodies, for a motion test to ignore; one array reused (the test copies it).
func _drop_rids(body: RigidBody3D) -> Array[RID]:
	_rids.clear()
	for other: int in _entries:
		var b: RigidBody3D = _entries[other]["body"]
		if b != body and is_instance_valid(b):
			_rids.append(b.get_rid())
	return _rids


## [param b] turned the least way that brings the drop's long axis level.
func _laid_flat(e: Dictionary, b: Basis) -> Basis:
	var size: Vector3 = e["size"]
	var axis := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	var long_world := b[axis].normalized()
	var level := Vector3(long_world.x, 0.0, long_world.z)
	if level.length() < 0.01:
		level = Vector3.RIGHT
	level = level.normalized()
	var turn := long_world.cross(level)
	if turn.length() < 0.0001:
		return b.orthonormalized()
	return (Basis(turn.normalized(), long_world.signed_angle_to(level, turn.normalized())) * b.orthonormalized())


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
