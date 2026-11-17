extends "sections_attach.gd"

## Thrown knives: the charged throw, the Boomerang's closed loop and homing, sticking in a survivor, the wire.


## dot-net is not a dependency: a tape that hands back what was written, in order, stands in for its writer and reader.
class Tape extends RefCounted:
	var values: Array = []
	var read_at: int = 0

	func _put(v) -> void:
		values.append(v)

	func _take():
		read_at += 1
		return values[read_at - 1] if read_at <= values.size() else null

	func write_varint(v: int) -> void: _put(v)
	func write_uint(v: int, _bits: int) -> void: _put(v)
	func write_bool(v: bool) -> void: _put(v)
	func write_float32(v: float) -> void: _put(v)
	func write_direction(v: Vector3, _bits: int) -> void: _put(v.normalized())
	func write_vector3_range(v: Vector3, _lo: float, _hi: float, _bits: int) -> void: _put(v)
	func read_varint() -> int: return int(_take())
	func read_uint(_bits: int) -> int: return int(_take())
	func read_bool() -> bool: return bool(_take())
	func read_float32() -> float: return float(_take())
	func read_direction(_bits: int) -> Vector3: return _take()
	func read_vector3_range(_lo: float, _hi: float, _bits: int) -> Vector3: return _take()
	func ok() -> bool: return read_at <= values.size()


class KnifeState extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO


class KnifeController extends RefCounted:
	var state: KnifeState = KnifeState.new()


## The duck-typed player DotWeaponKnives reads.
class KnifePlayer extends RefCounted:
	var arsenal: DotWeaponArsenal = null
	var controller: KnifeController = KnifeController.new()
	var health: DotHealth = null

	func is_alive() -> bool:
		return health == null or health.alive

	func muzzle_position() -> Vector3:
		return controller.state.position + Vector3(0.0, 1.5, 0.0)


func _test_knives() -> void:
	_test_knife_charge()
	_test_knife_boomerang_loop()
	_test_knife_boomerang_catch()
	_test_knife_boomerang_empty_hand()
	_test_knife_boomerang_home()
	_test_knife_boomerang_stick()
	_test_knife_wire()


func _knife_layer(players: Dictionary) -> DotWeaponKnives:
	var k := DotWeaponKnives.new()
	k.tick_rate = RATE
	k.player_for = func(id: int): return players.get(id, null)
	k.player_ids = func() -> Array: return players.keys()
	add_child(k)
	return k


## A player holding a knife whose grip mount takes the Boomerang attachment.
func _knife_player(boomerang: bool) -> KnifePlayer:
	var c := _catalogue()
	var knife := c.get_def(&"knife")
	knife.mounts = [&"grip"] as Array[StringName]
	var a := _arsenal(c)
	var cat := DotWeaponAttachments.new()
	var att := _att("boomerang", &"grip")
	att.params_set = {DotWeaponKnives.PARAM_BOOMERANG: true}
	var _added := cat.add(att)
	a.attachments = cat
	var _given := a.give(&"knife", true)
	if boomerang:
		var f := DotWeaponFitting.make(&"knife")
		f.fit(&"grip", &"boomerang")
		var _fitted := a.fit(knife.slot, f)
	a.bring_to_hand(knife.slot)
	var p := KnifePlayer.new()
	p.arsenal = a
	return p


func _aim(down: bool) -> DotWeaponCommand:
	var c := DotWeaponCommand.new()
	c.set_button(DotWeaponCommand.BUTTON_AIM, down)
	return c


func _test_knife_charge() -> void:
	_section("thrown knife: charged throw")
	var rules := DotWeaponKnives.DEFAULT_RULES.duplicate()
	_check(not bool(rules["charge"]) and DotWeaponKnives.power_fraction(rules, 0.0) == 1.0, "charge is off by default and throws at full power")
	var p := _knife_player(false)
	var players := {1: p}
	var layer := _knife_layer(players)
	var press := _aim(true)
	layer.input(1, p, press)
	_check(layer.count() == 1 and not press.is_pressed(DotWeaponCommand.BUTTON_AIM), "without charge the press throws at once and takes the aim key")
	_close(layer.entries()[0].velocity.length(), 40.0, "at the full speed")
	layer.clear()

	layer.rules["charge"] = true
	_check(p.arsenal.carries(&"knife"), "clear gives the knife back")
	p.arsenal.bring_to_hand(4)
	var first := _aim(true)
	layer.input(1, p, first)
	_check(layer.count() == 0 and layer.charge_of(1) == 0.0 and not first.is_pressed(DotWeaponCommand.BUTTON_AIM), "with charge the press winds up, empty meter, aim key taken")
	for i in RATE / 2:
		layer.input(1, p, _aim(true))
	_close(layer.charge_of(1), 0.5, "half a second of holding half fills a one-second meter")
	layer.input(1, p, _aim(false))
	_check(layer.count() == 1 and layer.charge_of(1) == -1.0 and not p.arsenal.carries(&"knife"), "the release throws it")
	_close(layer.entries()[0].velocity.length(), 40.0 * lerpf(0.35, 1.0, 0.5), "at the power the meter showed")
	_close(DotWeaponKnives.power_fraction(layer.rules, 5.0), 1.0, "a long hold is full power")
	layer.rules["charge_sec"] = 0.0
	_close(DotWeaponKnives.power_fraction(layer.rules, 0.0), 1.0, "charge_sec 0 is full power at once")
	layer.clear()
	p.arsenal.bring_to_hand(4)
	layer.rules["charge_sec"] = 1.0
	layer.input(1, p, _aim(true))
	p.health = DotHealth.new()
	p.health.alive = false
	layer.input(1, p, _aim(true))
	_check(layer.charge_of(1) == -1.0 and layer.count() == 0, "dying cancels the wind-up")
	p.health.free()
	layer.queue_free()
	_done()


func _test_knife_boomerang_loop() -> void:
	_section("thrown knife: boomerang out, circle, back")
	var p := _knife_player(true)
	_check(DotWeaponKnives.is_boomerang(p.arsenal.current_def()), "the Boomerang attachment marks the fitted knife")
	var layer := _knife_layer({1: p})
	layer.rules["boomerang_distance"] = 18.0
	layer.rules["boomerang_radius"] = 5.0
	layer.rules["boomerang_catch"] = 0.0
	layer.input(1, p, _aim(true))
	var k: DotWeaponKnives.Knife = layer.entries()[0] if layer.count() == 1 else null
	_check(k != null and k.boomerang and layer.glides(k.id) and k.state.has("fit"), "the throw glides as a boomerang and keeps the fitting")
	var origin := p.muzzle_position()
	var aim := k.velocity.normalized()
	_check(absf(k.path_len - (26.0 + 5.0 * k.path_angle)) < 0.001, "the path is out, a turn, and the same way back", str(k.path_len))
	var apex := 0.0
	var along_max := 0.0
	var turned_at := -1
	var straight_max := 0.0
	var straight_ok := true
	var back_dir := Vector3.ZERO
	var back_from := Vector3.ZERO
	var ticks := ceili(k.path_len / (k.speed / RATE)) + 2
	for t in ticks:
		layer.tick(t + 1, 1.0 / RATE)
		if k.phase != DotWeaponKnives.Phase.FLY or not k.glide:
			break
		apex = maxf(apex, k.at.distance_to(origin))
		along_max = maxf(along_max, (k.at - origin).dot(aim))
		if k.leg == 0:
			straight_max = maxf(straight_max, (k.at - origin).dot(aim))
		if turned_at < 0 and k.leg == 1:
			turned_at = t
		if k.leg == 2 and back_dir == Vector3.ZERO:
			back_dir = k.velocity.normalized()
			back_from = k.at
		if k.leg == 0 and (k.at - origin).cross(aim).length() > 0.001:
			straight_ok = false
	_check(absf(along_max - 18.0) < k.speed / RATE + 0.01, "it flies out the configured distance before turning", "%.2f m" % along_max)
	_check(straight_max > 12.0 and straight_max < 13.5, "the straight leg is the distance less the turn radius", "%.2f m" % straight_max)
	_check(apex >= 18.0 and apex < 21.0, "the farthest point stays near the configured distance", "%.2f m" % apex)
	_check(straight_ok, "the outward leg is straight along the throw")
	_check(turned_at > 0, "the turn comes after the outward leg")
	_check(back_dir.dot((origin - back_from).normalized()) > 0.999, "the return leg points straight at the throw point", str(back_dir.dot((origin - back_from).normalized())))
	_check(k.at == origin and not k.glide and k.velocity == Vector3.ZERO, "it comes back to exactly the throw point", str(k.at.distance_to(origin)))
	layer.tick(ticks + 2, 1.0 / RATE)
	_check(k.velocity.y < 0.0 and k.bounces >= 1, "then falls there and can no longer hurt anyone")
	var curve := _boomerang_curve_checks()
	var twins := _boomerang_twin_checks()
	for l: DotWeaponKnives in [layer, curve] + twins:
		l.clear()
		l.queue_free()
	_done()


func _test_knife_boomerang_catch() -> void:
	_section("thrown knife: boomerang caught in the air")
	_check(float(DotWeaponKnives.DEFAULT_RULES["boomerang_catch"]) > 0.0, "a returning Boomerang is caught by default")
	var p := _knife_player(true)
	var layer := _knife_layer({1: p})
	layer.rules["boomerang_distance"] = 12.0
	layer.rules["boomerang_radius"] = 3.0
	layer.rules["boomerang_catch"] = 1.5
	layer.input(1, p, _aim(true))
	var k: DotWeaponKnives.Knife = layer.entries()[0] if layer.count() == 1 else null
	_check(k != null and not p.arsenal.carries(&"knife"), "the hand is empty while the knife flies")
	var ticks := ceili(k.path_len / (k.speed / RATE)) + 2
	var caught_at := -1.0
	var out_leg_caught := false
	for t in ticks:
		var before := k.at
		var leg := k.leg
		layer.tick(t + 1, 1.0 / RATE)
		if layer.count() == 0:
			caught_at = before.distance_to(p.muzzle_position())
			out_leg_caught = leg == 0
			break
	_check(layer.count() == 0 and p.arsenal.carries(&"knife"), "it comes back into the thrower's hand without touching the floor")
	_check(caught_at >= 0.0 and caught_at < 1.5 + k.speed / RATE + 0.01, "caught within reach of the hand", "%.2f m" % caught_at)
	_check(not out_leg_caught, "never caught on the way out")
	_check(DotWeaponKnives.is_boomerang(p.arsenal.current_def()), "the caught knife keeps its Boomerang fitting")
	layer.clear()
	layer.queue_free()
	# Walked away from the throw point: it flies past the empty spot and falls there.
	var q := _knife_player(true)
	var away := _knife_layer({1: q})
	away.rules["boomerang_distance"] = 12.0
	away.rules["boomerang_radius"] = 3.0
	away.input(1, q, _aim(true))
	var qk: DotWeaponKnives.Knife = away.entries()[0] if away.count() == 1 else null
	q.controller.state.position = Vector3(0.0, 0.0, 30.0)
	for t in ceili(qk.path_len / (qk.speed / RATE)) + 2:
		away.tick(t + 1, 1.0 / RATE)
	_check(away.count() == 1 and not qk.glide and not q.arsenal.carries(&"knife"), "out of reach it is not caught and falls at the throw point")
	away.clear()
	away.queue_free()
	_done()


func _test_knife_boomerang_empty_hand() -> void:
	_section("thrown knife: boomerang thrower waits bare-handed")
	_check(bool(DotWeaponKnives.DEFAULT_RULES["boomerang_empty_hand"]), "the thrower waits bare-handed by default")
	var p := _knife_with_sidearm()
	var knife_slot: int = p.arsenal.current_slot()
	var layer := _knife_layer({1: p})
	layer.rules["boomerang_distance"] = 12.0
	layer.rules["boomerang_radius"] = 3.0
	layer.input(1, p, _aim(true))
	var k: DotWeaponKnives.Knife = layer.entries()[0] if layer.count() == 1 else null
	_check(k != null and p.arsenal.current_slot() == 0, "the throw leaves the hand empty, not on the next weapon", str(p.arsenal.current_slot()))
	for t in ceili(k.path_len / (k.speed / RATE)) + 2:
		layer.tick(t + 1, 1.0 / RATE)
		if layer.count() == 0:
			break
	_check(layer.count() == 0 and p.arsenal.current_slot() == knife_slot, "the catch puts the knife straight back in the empty hand")
	layer.clear()
	layer.queue_free()
	# Out of reach: the knife falls at the throw point and the next weapon comes up.
	var q := _knife_with_sidearm()
	var away := _knife_layer({1: q})
	away.rules["boomerang_distance"] = 12.0
	away.rules["boomerang_radius"] = 3.0
	away.input(1, q, _aim(true))
	var qk: DotWeaponKnives.Knife = away.entries()[0] if away.count() == 1 else null
	q.controller.state.position = Vector3(0.0, 0.0, 30.0)
	var waited := true
	for t in ceili(qk.path_len / (qk.speed / RATE)) + 2:
		away.tick(t + 1, 1.0 / RATE)
		if qk.glide and q.arsenal.current_slot() != 0:
			waited = false
	_check(waited, "the hand stays empty while the knife glides")
	_check(not qk.glide and q.arsenal.current_slot() != 0 and not q.arsenal.carries(&"knife"), "a knife that falls brings the next weapon up", str(q.arsenal.current_slot()))
	away.clear()
	away.queue_free()
	# Rule off: the throw draws the next weapon at once, as before.
	var r := _knife_with_sidearm()
	var off := _knife_layer({1: r})
	off.rules["boomerang_empty_hand"] = false
	off.input(1, r, _aim(true))
	_check(off.count() == 1 and r.arsenal.current_slot() != 0, "with the rule off the next weapon is drawn at once")
	off.clear()
	off.queue_free()
	_check(r.arsenal.empty_hand() and r.arsenal.current_slot() == 0 and not r.arsenal.empty_hand(), "empty_hand lowers the weapon once")
	_done()


## A Boomerang knife player who also carries the catalogue's first other weapon.
func _knife_with_sidearm() -> KnifePlayer:
	var p := _knife_player(true)
	var knife_slot: int = p.arsenal.current_slot()
	var c: DotWeaponCatalogue = p.arsenal.catalogue
	for id: StringName in c.ids():
		if c.get_def(id).slot != knife_slot and p.arsenal.give(id, true).ok:
			break
	p.arsenal.bring_to_hand(knife_slot)
	return p


## A default boomerang curves right and lands on the origin; returns the layer to free.
func _boomerang_curve_checks() -> DotWeaponKnives:
	var curve := _knife_layer({})
	curve.rules["boomerang_distance"] = 10.0
	curve.rules["boomerang_radius"] = 3.0
	var cid := curve.throw(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, 1.0, true)
	var ck: DotWeaponKnives.Knife = curve.entries()[0]
	var far_x := 0.0
	for t in ceili(ck.path_len / (ck.speed / RATE)) + 2:
		curve.tick(t + 1, 1.0 / RATE)
		if not ck.glide:
			break
		far_x = maxf(far_x, ck.at.x)
	_check(far_x > 5.0, "it curves right by default", "%.2f" % far_x)
	_check(ck.at == Vector3.ZERO, "and lands on the origin to within nothing", str(ck.at))
	_check(cid > 0, "throw returns an id")
	return curve


## Two servers fly one throw alike, radius 0 turns on the spot, distance 0 glides on; returns the layers to free.
func _boomerang_twin_checks() -> Array:
	var a := _knife_layer({})
	var b := _knife_layer({})
	for layer2: DotWeaponKnives in [a, b]:
		layer2.rules["boomerang_left"] = true
		var _id := layer2.throw(1, Vector3(1.0, 1.5, 2.0), Vector3(0.3, 0.2, -1.0), Vector3(0.5, 0.0, 0.0), 0.8, true)
		for t in 40:
			layer2.tick(t + 1, 1.0 / RATE)
	var ka: DotWeaponKnives.Knife = a.entries()[0]
	var kb: DotWeaponKnives.Knife = b.entries()[0]
	_check(ka.at == kb.at and ka.velocity == kb.velocity, "two servers fly it bit-identically")
	_check(ka.turn.length() > 0.0 and ka.turn.dot(ka.path_dir.cross(ka.path_side)) > 0.0, "the circling leg carries a turn for clients to fly")
	var sharp := _knife_layer({})
	sharp.rules["boomerang_radius"] = 0.0
	var sk_id := sharp.throw(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, 1.0, true)
	var sk: DotWeaponKnives.Knife = sharp.entries()[0]
	for t in ceili(sk.path_len / (sk.speed / RATE)) + 2:
		sharp.tick(t + 1, 1.0 / RATE)
		if not sk.glide:
			break
	_check(sk_id > 0 and sk.at == Vector3.ZERO, "radius 0 turns on the spot and still lands on the origin")
	a.rules["boomerang_distance"] = 0.0
	var straight := a.throw(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, 1.0, true)
	_check(a.glides(straight) and a.turn_of(straight) == Vector3.ZERO, "boomerang_distance 0 glides straight on, no return")
	return [a, b, sharp]


func _test_knife_boomerang_home() -> void:
	_section("thrown knife: boomerang homing to the thrower")
	var p := _knife_player(true)
	var layer := _knife_layer({1: p})
	layer.rules["boomerang_to_thrower"] = true
	layer.input(1, p, _aim(true))
	var k: DotWeaponKnives.Knife = layer.entries()[0]
	p.controller.state.position = Vector3(-4.0, 0.0, 3.0)
	var caught := -1
	for t in 400:
		layer.tick(t + 1, 1.0 / RATE)
		if layer.count() == 0:
			caught = t + 1
			break
	_check(caught > 20, "it comes back to the thrower who moved", str(caught))
	p.arsenal.bring_to_hand(4)
	_check(p.arsenal.carries(&"knife") and DotWeaponKnives.is_boomerang(p.arsenal.current_def()), "into the hand, Boomerang still fitted")
	layer.queue_free()
	_done()


func _test_knife_boomerang_stick() -> void:
	_section("thrown knife: boomerang sticks in a survivor")
	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.with_floor(0.0)
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	manager.config.tick_rate = RATE
	add_child(manager)
	var body := _bridge_target(-6.0)
	var health: DotHealth = null
	for c in body.get_children():
		if c is DotHitboxSet:
			(c as DotHitboxSet).register_with(manager, 2)
		elif c is DotHealth:
			health = c
	manager.register_health(2, health)
	var thrower := _knife_player(true)
	var victim := KnifePlayer.new()
	victim.health = health
	victim.arsenal = _arsenal()
	victim.controller.state.position = body.position
	var players := {1: thrower, 2: victim}
	var layer := _knife_layer(players)
	layer.combat = manager
	layer.rules["damage"] = 10.0
	layer.rules["boomerang_distance"] = 0.0
	layer.input(1, thrower, _aim(true))
	var k: DotWeaponKnives.Knife = layer.entries()[0]
	for t in 20:
		layer.tick(t + 1, 1.0 / RATE)
	_check(k.phase == DotWeaponKnives.Phase.STUCK and k.victim == 2 and health.alive and health.health < 100.0, "it hurts and stays in a victim who lives", "%d %s" % [k.phase, health.health])
	_check(k.riding, "riding the living body")
	var was := k.at
	victim.controller.state.position += Vector3(2.0, 0.0, 0.0)
	layer.tick(21, 1.0 / RATE)
	_check(k.at.is_equal_approx(was + Vector3(2.0, 0.0, 0.0)), "and moves with them")
	for t in 5:
		layer.tick(22 + t, 1.0 / RATE)
	_check(layer.count() == 1, "the victim cannot pull it out")
	thrower.controller.state.position = Vector3(k.at.x, 0.0, k.at.z)
	layer.tick(30, 1.0 / RATE)
	_check(layer.count() == 0 and thrower.arsenal.carries(&"knife"), "someone else walking up retrieves it")
	layer.queue_free()
	manager.queue_free()
	body.queue_free()
	_done()


func _test_knife_wire() -> void:
	_section("thrown knife: wire carries the glide")
	var w := Tape.new()
	var turn := Vector3(0.0, -3.9, 0.0)
	DotWeaponKnifeWire.write_knife(w, 7, 1, DotWeaponKnives.Phase.FLY, 0, Vector3(1.0, 2.0, 3.0), Vector3(0.0, 0.0, -30.0), true, turn)
	DotWeaponKnifeWire.write_knife(w, 8, 1, DotWeaponKnives.Phase.REST, 0, Vector3.ZERO, Vector3.FORWARD)
	var r := w
	var one := DotWeaponKnifeWire.read_knife(r)
	var two := DotWeaponKnifeWire.read_knife(r)
	_check(one["ok"] and one["glide"] and one["turn"] == turn, "glide and turn round-trip", str(one["turn"]))
	_check(two["ok"] and not two["glide"] and two["turn"] == Vector3.ZERO and two["id"] == 8, "a plain event after it still reads")
	var client := DotWeaponKnives.new()
	client.is_authority = false
	add_child(client)
	client.mirror(7, 1, DotWeaponKnives.Phase.FLY, 0, Vector3.ZERO, Vector3(0.0, 0.0, -30.0), true, turn)
	client._physics_process(1.0 / RATE)
	var ck: DotWeaponKnives.Knife = client.get_knife(7)
	_check(ck.velocity.y == 0.0 and ck.velocity.x != 0.0, "a client glides and turns it between events")
	client.queue_free()
	_done()
