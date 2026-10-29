extends "selftest/harness.gd"

## Dropped weapons: rules, throw, empty-slot pickup, expiry, cap. Headless.

const CHECKS := 34


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-weapon drop self-test")
	_test_rules()
	_test_throw_and_swap()
	await _test_lifetime_and_cap()
	await _test_settle_and_mirror()
	print("")
	print("%d sections entered, %d finished, %d passed, %d failed" % [_sections_entered, _sections_finished, _passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 or _sections_entered != _sections_finished else 0)


class _ClassStub extends RefCounted:
	var drop_throw_force: float = 12.0
	var drop_lifetime: float = -1.0
	var drop_on_death: int = 0
	var drop_allowed: int = -1
	var drop_pickup_radius: float = -1.0
	var drop_throw_up: float = -1.0


func _drops(authority: bool = true) -> DotWeaponDrops:
	var d := DotWeaponDrops.new()
	d.is_authority = authority
	d.draws = false
	d.collision_mask = 0
	add_child(d)
	return d


func _test_rules() -> void:
	_section("rules and class overrides")
	var r := DotWeaponDropRules.new()
	_check(r.lifetime == 60.0 and r.max_count == 32, "defaults: 60 s, 32 on the map")
	var c := r.resolve(_ClassStub.new())
	_check(c.throw_force == 12.0, "a class sets the throw force")
	_check(c.lifetime == 60.0 and c.pickup_radius == r.pickup_radius, "and a negative field inherits the rule")
	_check(not c.on_death and r.on_death, "a class turns the death drop off without touching the rules")
	_check(r.set_cvar("sv_weapon_drop_time", "0") and r.lifetime == 0.0, "sv_weapon_drop_time 0 means never")
	_check(r.set_cvar("sv_weapon_drop_max", "9999") and r.max_count == 512, "sv_weapon_drop_max clamps")
	_check(not r.set_cvar("sv_weapon_drop_time", "soon"), "a non-number is refused")
	_check(not r.set_cvar("sv_other", "1"), "another cvar is not ours")
	_check(r.cvar_specs().size() == 10, "ten cvars are described")
	_done()


func _test_throw_and_swap() -> void:
	_section("throwing and taking")
	var drops := _drops()
	var a := _arsenal()
	var _g := a.give(&"rifle")
	var seen: Array = []
	drops.dropped.connect(func(id: int, state: Dictionary, _at: Transform3D, v: Vector3, _o: int) -> void: seen.append([id, state, v]))
	var id := drops.throw(a, Vector3(0, 1.6, 0), Vector3.FORWARD, 7, null)
	_check(id == 1 and drops.count() == 1, "the drop key puts the weapon in the world")
	_check(not a.carries(&"rifle"), "and takes it out of the hand")
	_check(seen.size() == 1 and (seen[0][1] as Dictionary)["magazine"] == 30, "the signal carries the magazine")
	_check((seen[0][2] as Vector3).z < -5.0 and (seen[0][2] as Vector3).y > 1.0, "thrown along the aim with some lift")
	var back := drops.take_for(a, Vector3(0, 1.6, 0), 7)
	_check(back == 0, "the thrower cannot catch it again during the delay")
	drops.tick(1.0)
	_check(drops.take_for(a, Vector3(0, 1.6, 0), 7) == id and a.carries(&"rifle"), "after the delay an empty slot takes it")
	_check(drops.count() == 0, "and it leaves the world")
	_check(a.current().magazine == 30, "with its magazine")

	# Q on a weapon: drop mine, then take the one at my feet (same slot).
	var b := _arsenal()
	var _g2 := b.give(&"rifle", false)
	var _s := drops.spawn({"id": &"rifle", "magazine": 12, "reserve": 0}, Vector3(0, 1, 0), Vector3.ZERO, 3)
	drops.tick(1.0)
	var mine := drops.throw(b, Vector3(0, 1, 0.2), Vector3.FORWARD, 9, null)
	_check(mine > 0, "swap: the held weapon is dropped")
	_check(b.carries(&"rifle") and b.current().magazine == 12, "and the one underfoot is in the slot (12 rounds)")
	_check(drops.count() == 1 and drops.has_drop(mine), "leaving only the thrown one")

	var off := DotWeaponDropRules.new()
	off.enabled = false
	drops.rules = off
	var c2 := _arsenal()
	var _g3 := c2.give(&"pistol")
	_check(drops.throw(c2, Vector3.ZERO, Vector3.FORWARD, 1) == 0 and c2.carries(&"pistol"), "disabled rules drop nothing")
	drops.rules = DotWeaponDropRules.new()
	var held := _arsenal()
	_check(drops.throw(held, Vector3.ZERO, Vector3.FORWARD, 1) == 0, "an empty-handed player drops nothing")
	var dead := _arsenal()
	var _g4 := dead.give(&"pistol")
	_check(drops.drop_dead(dead, Vector3(2, 1, 2), Vector3.ZERO, 4) > 0 and not dead.carries(&"pistol"), "a death drops the weapon")
	var stubbed := _arsenal()
	var _g5 := stubbed.give(&"pistol")
	_check(drops.drop_dead(stubbed, Vector3.ZERO, Vector3.ZERO, 4, _ClassStub.new()) == 0 and stubbed.carries(&"pistol"), "a class with drop_on_death 0 keeps it")
	_drop(drops)
	_done()


func _test_lifetime_and_cap() -> void:
	_section("lifetime and the cap")
	var drops := _drops()
	var gone: Array = []
	drops.removed.connect(func(id: int, taker: int) -> void: gone.append([id, taker]))
	var r := DotWeaponDropRules.new()
	r.lifetime = 2.0
	r.max_count = 3
	drops.rules = r
	var ids: Array[int] = []
	for i in range(4):
		ids.append(drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(i, 5, 0), Vector3.ZERO, 1))
	_check(drops.count() == 3 and not drops.has_drop(ids[0]), "past the cap the oldest goes first")
	_check(gone.size() == 1 and gone[0] == [ids[0], 0], "and says so with taker 0")
	drops.tick(2.5)
	_check(drops.count() == 0, "the rest expire after the lifetime")
	r.lifetime = 0.0
	var keep := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(0, 5, 0), Vector3.ZERO, 1)
	drops.tick(10000.0)
	_check(drops.has_drop(keep), "lifetime 0 never expires")
	r.max_count = 0
	for i in range(40):
		var _n := drops.spawn({"id": &"rifle", "magazine": 1, "reserve": 0}, Vector3(0, 5, 0), Vector3.ZERO, 1)
	_check(drops.count() == 41, "max 0 is unlimited")
	_drop(drops)
	_done()
	await get_tree().process_frame


func _test_settle_and_mirror() -> void:
	_section("settling and the client copy")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var server := _drops()
	server.collision_mask = 1
	var client := _drops(false)
	client.collision_mask = 1
	server.dropped.connect(func(id: int, state: Dictionary, at: Transform3D, v: Vector3, _o: int) -> void: client.mirror_drop(id, state, at, v))
	var rested: Array = []
	server.settled.connect(func(id: int, at: Transform3D) -> void:
		rested.append(id)
		client.mirror_settled(id, at))
	server.removed.connect(func(id: int, _t: int) -> void: client.mirror_removed(id))
	var id := server.spawn({"id": &"rifle", "magazine": 5, "reserve": 0}, Vector3(0, 1.5, 0), Vector3(2, 0, 0), 1)
	_check(client.has_drop(id), "a client mirrors the drop")
	for i in range(240):
		await get_tree().physics_frame
	_check(rested.has(id), "the authority sees it come to rest")
	var s := server.snapshot()
	_check(s.size() == 1 and s[0]["rest"] and absf((s[0]["at"] as Transform3D).origin.y) < 0.5, "resting on the floor")
	_check(is_equal_approx(client.snapshot()[0]["at"].origin.x, s[0]["at"].origin.x), "and the client snapped to the same place")
	server.rules.lifetime = 0.5
	var _later := server.spawn({"id": &"pistol", "magazine": 1, "reserve": 0}, Vector3(3, 1, 0), Vector3.ZERO, 1, server.rules)
	for i in range(60):
		await get_tree().physics_frame
	_check(server.count() == 1 and client.count() == 1, "an expiry reaches the client too")
	_drop(server)
	_drop(client)
	_drop(floor_body)
	_done()
