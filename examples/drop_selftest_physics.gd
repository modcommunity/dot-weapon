extends "selftest/harness.gd"

## The physics half of drop_selftest: tunnelling, rescue, support gone, blasts. Extended by drop_selftest.gd.


func _drops(authority: bool = true) -> DotWeaponDrops:
	var d := DotWeaponDrops.new()
	d.is_authority = authority
	d.draws = false
	d.collision_mask = 0
	add_child(d)
	return d


func _test_physics() -> void:
	_section("shootable drops")
	var drops := _drops()
	drops.collision_mask = 0
	var d := drops.spawn({"id": &"rifle", "magazine": 5, "reserve": 0}, Vector3(0, 5, 0), Vector3.ZERO, 1)
	drops.rules.lifetime = 0.0
	var seen: Array = []
	drops.pushed.connect(func(id: int, _at: Transform3D, v: Vector3, _s: Vector3) -> void: seen.append([id, v]))
	await get_tree().physics_frame
	var hit := drops.raycast(Vector3(0, 5, 3), Vector3(0, 5, -3))
	_check(hit.get("id", 0) == d, "a ray across a drop finds it")
	_check(drops.raycast(Vector3(4, 5, 3), Vector3(4, 5, -3)).is_empty(), "and a ray beside it does not")
	drops._rest(d, drops._entries[d], drops._entries[d]["body"])
	_check(drops.active_count() == 0, "a settled drop is not active")
	_check(drops.hit(d, hit["point"], Vector3.FORWARD, 8.0) and seen.size() == 1 and drops.active_count() == 1, "a shot wakes it and tells clients")
	_check((seen[0][1] as Vector3).length() > 0.5, "and gives it speed")
	drops.rules.shootable = false
	_check(not drops.hit(d, hit["point"], Vector3.FORWARD, 8.0), "sv_weapon_drop_shootable 0 leaves it alone")
	drops.rules.shootable = true
	_check(drops.blast(Vector3(0, 4, 0), 6.0, 10.0) == 1 and seen.size() == 2, "an explosion in range pushes it")
	_check(drops.blast(Vector3(0, 40, 0), 3.0, 10.0) == 0, "and one out of range does not")
	drops.rules.max_active = 1
	var e := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(3, 5, 0), Vector3.ZERO, 1)
	var _h := drops.hit(e, Vector3(3, 5, 0), Vector3.FORWARD, 5.0)
	_check(drops.active_count() <= 1, "max_active puts the oldest to rest")
	var client := _drops(false)
	client.mirror_drop(d, {"id": &"rifle", "magazine": 5, "reserve": 0}, Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), Vector3.ZERO, 0.0, true)
	client.mirror_pushed(d, Transform3D(Basis.IDENTITY, Vector3(1, 5, 0)), Vector3(0, 0, -3), Vector3.ZERO)
	_check(client.active_count() == 1 and absf(client.snapshot()[0]["at"].origin.x - 1.0) < 0.01, "a client wakes the drop at the authority's pose")
	_done()


func _test_capped_in_air() -> void:
	_section("a drop the active cap rests in mid-air goes down onto the floor first")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(100, -0.5, 0)
	add_child(floor_body)
	var drops := _drops()
	drops.collision_mask = 1
	drops.rules.lifetime = 0.0
	drops.rules.max_active = 1
	var settled: Dictionary = {}
	drops.settled.connect(func(id: int, at: Transform3D) -> void: settled[id] = at)
	var a := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(100, 6, 0), Vector3.ZERO, 1)
	await get_tree().physics_frame
	var body: RigidBody3D = drops._entries[a]["body"]
	body.global_basis = Basis(Vector3.RIGHT, PI * 0.5)
	var _b := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(104, 6, 0), Vector3.ZERO, 1)
	_check(bool(drops._entries[a]["rest"]) and settled.has(a), "the oldest flying drop is rested by the cap")
	for _i in DotWeaponDrops.GROUND_TICKS + 1:
		await get_tree().physics_frame
	var at: Transform3D = settled.get(a, Transform3D())
	_check(at.origin.y > -0.05 and at.origin.y < 0.3 and absf(at.origin.x - 100.0) < 0.01, "on the floor under it, not 6 m up where it flew", str(at.origin))
	_check(absf(at.basis.z.normalized().y) < 0.05, "laid flat, not standing on its muzzle", str(at.basis.z))
	var c := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(108, 0.2, 0), Vector3.ZERO, 1)
	await get_tree().physics_frame
	var low: Vector3 = (drops._entries[c]["body"] as RigidBody3D).global_position
	var _d := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(112, 6, 0), Vector3.ZERO, 1)
	for _i in DotWeaponDrops.GROUND_TICKS + 1:
		await get_tree().physics_frame
	_check(settled.has(c) and absf((settled[c] as Transform3D).origin.y - low.y) < 0.1, "one already down by the floor rests where it is", "%s vs %s" % [settled.get(c), low])
	drops.queue_free()
	floor_body.queue_free()
	_done()


func _static_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	b.add_child(shape)
	b.position = at
	add_child(b)
	return b


## The gap under a drop as the physics sees it (its whole box swept down, other drops ignored).
func _gap_under(drops: DotWeaponDrops, id: int) -> float:
	var body: RigidBody3D = drops._entries[id]["body"]
	return drops._sweep_down(body, body.global_transform, 3.0).length()


func _test_support_gone() -> void:
	_section("a resting drop whose support goes falls again, on the server and its mirror")
	var floor_body := _static_box(Vector3(20, 1, 20), Vector3(200, -0.5, 0))
	var crate := _static_box(Vector3(2, 1, 2), Vector3(200, 0.5, 0))
	var server := _drops()
	server.collision_mask = 1
	server.rules.lifetime = 0.0
	var client := _drops(false)
	client.collision_mask = 1
	var pushes: Array = []
	server.dropped.connect(func(id: int, state: Dictionary, at: Transform3D, v: Vector3, _o: int) -> void: client.mirror_drop(id, state, at, v))
	server.settled.connect(func(id: int, at: Transform3D) -> void: client.mirror_settled(id, at))
	server.pushed.connect(func(id: int, at: Transform3D, v: Vector3, spin: Vector3) -> void:
		pushes.append(id)
		client.mirror_pushed(id, at, v, spin))
	var a := server.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(200, 1.6, 0), Vector3.ZERO, 1)
	for _i in 180:
		await get_tree().physics_frame
		if bool(server._entries[a]["rest"]) and not server._entries[a].has("ground_in"):
			break
	var on_crate: float = (server._entries[a]["body"] as Node3D).global_position.y
	_check(bool(server._entries[a]["rest"]) and on_crate > 0.95, "rests on the crate", str(on_crate))
	_check(_gap_under(server, a) < 0.05, "server pose: ground right under it", str(_gap_under(server, a)))
	_check(client._entries.has(a) and bool(client._entries[a]["rest"]), "the mirror rests too")
	_check(_gap_under(client, a) < 0.05, "client pose: ground right under it", str(_gap_under(client, a)))
	_check(server.check_support() == 0, "a supported drop is left alone")
	crate.free()
	_check(server.check_support() == 1 and pushes.has(a), "the crate gone, the drop is woken and announced")
	_check(not bool(server._entries[a]["rest"]) and not bool(client._entries[a]["rest"]), "both sides fall again")
	for _i in 300:
		await get_tree().physics_frame
		if bool(server._entries[a]["rest"]) and not server._entries[a].has("ground_in"):
			break
	var y: float = (server._entries[a]["body"] as Node3D).global_position.y
	_check(bool(server._entries[a]["rest"]) and y < 0.3, "it lands on the floor, not where the crate was", str(y))
	_check(_gap_under(server, a) < 0.05 and _gap_under(client, a) < 0.05, "ground under both poses again", "%s %s" % [_gap_under(server, a), _gap_under(client, a)])
	server.queue_free()
	client.queue_free()
	floor_body.queue_free()
	_done()


func _test_rescue() -> void:
	_section("a drop that tunnels through the floor is put back")
	var floor_body := _static_box(Vector3(20, 1, 20), Vector3(0, -0.5, 0))
	var drops := _drops()
	drops.collision_mask = 1
	drops.rules.lifetime = 0.0
	var seen: Array = []
	drops.pushed.connect(func(id: int, at: Transform3D, _v: Vector3, _s: Vector3) -> void: seen.append([id, at.origin]))
	var d := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(0, 0.6, 0), Vector3.ZERO, 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body: RigidBody3D = drops._entries[d]["body"]
	body.global_position = Vector3(0, -1.5, 0)
	drops.tick(0.0)
	_check(body.global_position.y > 0.0 and absf(body.global_position.x) < 0.5, "a drop whose centre went through the floor is back on top", str(body.global_position))
	_check(seen.size() == 1 and int(seen[0][0]) == d and (seen[0][1] as Vector3).y > 0.0, "and clients are told where")
	body.global_position = Vector3(0, -0.02, 0)
	drops.tick(0.0)
	_check(seen.size() == 1, "a drop only slightly into the floor (contact slop) is left to the solver")
	drops.rules.rescue = false
	body.global_position = Vector3(0, -1.5, 0)
	drops.tick(0.0)
	_check(body.global_position.y < -1.0, "sv_weapon_drop_rescue 0 leaves it")
	drops.rules.rescue = true
	var air := _drops()
	air.rules.lifetime = 0.0
	var a := air.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(0, 5, 0), Vector3.ZERO, 1)
	var fell: RigidBody3D = air._entries[a]["body"]
	fell.global_position = Vector3(0, 5.0 - DotWeaponDrops.RESCUE_DEPTH - 1.0, 0)
	air.tick(0.0)
	_check(air.has_drop(a) and absf(fell.global_position.y - 5.0) < 0.01, "a drop that fell out of the world goes back to its drop point once")
	fell.global_position = Vector3(0, 5.0 - DotWeaponDrops.RESCUE_DEPTH - 1.0, 0)
	air.tick(0.0)
	_check(not air.has_drop(a), "and the second time it is removed")
	var bumps := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(2, 0.6, 0), Vector3.ZERO, 1)
	var many: RigidBody3D = drops._entries[bumps]["body"]
	for _i in DotWeaponDrops.RESCUE_MAX + 1:
		many.global_position = Vector3(2, -1.5, 0)
		drops.tick(0.0)
	_check(bool(drops._entries[bumps]["rest"]) and many.global_position.y > 0.0 and many.global_position.y < 0.2, "a drop that keeps tunnelling is frozen lying on top after a few tries", str(many.global_position))
	var deep := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(4, 0.6, 0), Vector3.ZERO, 1)
	var sunk: RigidBody3D = drops._entries[deep]["body"]
	sunk.global_position = Vector3(4, 0.6 - DotWeaponDrops.RESCUE_DEPTH - 1.0, 0)
	drops.tick(0.0)
	_check(drops.has_drop(deep) and not bool(drops._entries[deep]["rest"]) and sunk.global_position.y > 0.0 and sunk.global_position.y < 0.6 and absf(sunk.global_position.x - 4.0) < 0.01,
		"a drop whose tunnel was missed goes back on the floor under its drop point", str(sunk.global_position))
	sunk.global_position = Vector3(4, 0.6 - DotWeaponDrops.RESCUE_DEPTH - 1.0, 0)
	drops.tick(0.0)
	_check(drops.has_drop(deep) and bool(drops._entries[deep]["rest"]) and sunk.global_position.y > 0.0 and sunk.global_position.y < 0.2,
		"and the second time it is frozen lying on that floor, not removed", str(sunk.global_position))
	# A trimesh floor whose faces point down (front faces seen from below): a sweep that skipped back faces missed every tunnel.
	var mesh_body := StaticBody3D.new()
	var mesh_shape := CollisionShape3D.new()
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(PackedVector3Array([Vector3(25, 0, -5), Vector3(35, 0, -5), Vector3(25, 0, 5), Vector3(35, 0, -5), Vector3(35, 0, 5), Vector3(25, 0, 5)]))
	tri.backface_collision = true
	mesh_shape.shape = tri
	mesh_body.add_child(mesh_shape)
	add_child(mesh_body)
	var flip := PhysicsRayQueryParameters3D.create(Vector3(30, 1, 0), Vector3(30, -1, 0), 1)
	flip.hit_back_faces = false
	var front := PhysicsRayQueryParameters3D.create(Vector3(30, -1, 0), Vector3(30, 1, 0), 1)
	front.hit_back_faces = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := mesh_body.get_world_3d().direct_space_state
	_check(space.intersect_ray(flip).is_empty() or space.intersect_ray(front).is_empty(), "the test trimesh is one-sided to a front-faces-only ray")
	var tm := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(30, 0.6, 0), Vector3.ZERO, 1)
	await get_tree().physics_frame
	var through: RigidBody3D = drops._entries[tm]["body"]
	through.global_position = Vector3(30, -1.5, 0)
	drops.tick(0.0)
	_check(through.global_position.y > 0.0 and absf(through.global_position.x - 30.0) < 0.5, "a drop through a trimesh floor of either winding is back on top", str(through.global_position))
	_drop(mesh_body)
	_drop(drops)
	_drop(air)
	_drop(floor_body)
	_done()


func _test_blast() -> void:
	_section("explosions push drops by sv_weapon_drop_blast, not through walls")
	var drops := _drops()
	drops.rules.lifetime = 0.0
	var pushes: Array = []
	drops.pushed.connect(func(id: int, _at: Transform3D, _v: Vector3, _s: Vector3) -> void: pushes.append(id))
	var state := {"id": &"rifle", "magazine": 5, "reserve": 0}
	var open := drops.spawn(state, Vector3(3, 1, 0), Vector3.ZERO, 1)
	await get_tree().physics_frame
	var body: RigidBody3D = drops._entries[open]["body"]
	var centre := Vector3(0, 1, 0)

	_check(drops.blast(centre, 6.0, 10.0) == 1, "an explosion beside a drop moves it")
	var v1 := body.linear_velocity
	_check(v1.x > 0.5, "away from the centre", str(v1))
	body.linear_velocity = Vector3.ZERO
	drops.rules.blast_scale = 2.0
	var _n := drops.blast(centre, 6.0, 10.0)
	_close(body.linear_velocity.length(), v1.length() * 2.0, "sv_weapon_drop_blast 2 doubles the push", 0.15)
	body.linear_velocity = Vector3.ZERO
	drops.rules.blast_scale = 0.0
	pushes.clear()
	var moved := drops.blast(centre, 6.0, 10.0)
	_check(body.linear_velocity.length() < 0.001, "sv_weapon_drop_blast 0 gives no push")
	_check(moved == 0 and pushes.is_empty(), "and wakes nothing and tells no client", "moved %d, pushes %d" % [moved, pushes.size()])
	drops.rules.blast_scale = 1.0

	var wall := DotTraceFlat.new()
	var _w := wall.add_box(AABB(Vector3(1.0, 0.0, -3.0), Vector3(0.4, 4.0, 6.0)))
	drops.can_see = func(a: Vector3, b: Vector3) -> bool: return wall.line_of_sight(a, b)
	var behind := drops.spawn(state, Vector3(3, 1, 0), Vector3.ZERO, 1)
	var open2 := drops.spawn(state, Vector3(0, 1, 3), Vector3.ZERO, 1)
	drops._remove(open, 0, false)
	await get_tree().physics_frame
	var hidden: RigidBody3D = drops._entries[behind]["body"]
	var seen_body: RigidBody3D = drops._entries[open2]["body"]
	hidden.linear_velocity = Vector3.ZERO
	seen_body.linear_velocity = Vector3.ZERO
	pushes.clear()
	var count := drops.blast(centre, 6.0, 10.0)
	_check(hidden.linear_velocity.length() < 0.001 and not pushes.has(behind), "a drop behind a solid wall gets no push", str(hidden.linear_velocity))
	_check(seen_body.linear_velocity.length() > 0.5 and pushes.has(open2), "the same distance in the open does", str(seen_body.linear_velocity))
	_check(count == 1, "and only the visible one is counted", str(count))
	drops.can_see = Callable()
	hidden.linear_velocity = Vector3.ZERO
	var _m := drops.blast(centre, 6.0, 10.0)
	_check(hidden.linear_velocity.length() > 0.5, "with no sight check set, behaviour is as before")
	_done()
