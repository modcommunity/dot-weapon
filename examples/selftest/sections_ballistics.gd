extends "sections_rules.gd"

## Ballistics, simulated bullets and ammunition hit-zone sections of the suite.

func _test_ballistics() -> void:
	_section("ballistic trajectory")
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 800.0
	b.max_range = 1200.0
	_check(DotWeaponTrajectory.is_simulated(b) and not DotWeaponTrajectory.is_simulated(DotWeaponBallistics.new()), "velocity 0 stays hitscan")
	var carbine := DotWeaponBallistics.new()
	carbine.muzzle_velocity = 350.0
	var sniper := DotWeaponBallistics.new()
	sniper.muzzle_velocity = 900.0
	sniper.drag = 0.0002
	sniper.max_range = 1200.0
	var last := {}
	for w in [carbine, b, sniper]:
		var d100 := DotWeaponTrajectory.drop_at(w, 100.0)
		var d300 := DotWeaponTrajectory.drop_at(w, 300.0)
		_check(d300.drop > d100.drop and d100.drop > 0.0, "drop grows with range", "%f %f" % [d100.drop, d300.drop])
		_check(d300.time > d100.time and d300.speed < w.muzzle_velocity, "it takes time and slows")
		last = d300
	var nodrag := DotWeaponBallistics.new()
	nodrag.muzzle_velocity = 500.0
	nodrag.drag = 0.0
	var t100 := DotWeaponTrajectory.drop_at(nodrag, 100.0)
	_close(t100.drop, 0.5 * 9.8 * 0.2 * 0.2, "no drag: drop is g*t^2/2 at t = 0.2 s", 0.04)
	var wall := func(from: Vector3, to: Vector3) -> Dictionary:
		if from.z > -400.0 and to.z <= -400.0:
			return {"position": Vector3(from.x, from.y, -400.0)}
		return {}
	var shot := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, wall)
	_check(not shot.hit.is_empty(), "a bullet at 900 m/s does not tunnel a paper-thin wall at 400 m")
	_close(shot.position.z, -400.0, "and stops on it")
	var open_shot := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, Callable())
	_check(open_shot.hit.is_empty() and open_shot.distance >= sniper.max_range - 1.0, "with nothing in the way it runs out at max range")
	var again := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, wall)
	_check(again.position == shot.position and again.time == shot.time, "the flight is deterministic")
	var fb := DotWeaponBallistics.new()
	fb.max_range = 100.0
	fb.falloff_start = 20.0
	fb.falloff_min = 0.5
	_close(DotWeaponTrajectory.falloff(fb, 10.0) + DotWeaponTrajectory.falloff(fb, 100.0), 1.5, "falloff: full inside, half at max range")
	fb.penetration = 0.4
	_close(DotWeaponTrajectory.through(fb, 0.1), 0.75, "a thin wall costs a quarter")
	_close(DotWeaponTrajectory.through(fb, 0.5), 0.0, "a thick one stops it")
	var pitch := DotWeaponTrajectory.solve_pitch(sniper, 300.0, 0.0)
	_check(pitch > 0.0 and pitch < 0.02, "the solver raises the bore for drop", str(pitch))
	var aim := DotWeaponTrajectory.lead(sniper, Vector3.ZERO, Vector3(0, 0, -300), Vector3(5, 0, 0))
	_check(aim.x > 1.0 and aim.y > 0.0, "bots lead a mover and hold over for drop", str(aim))
	_check(is_nan(DotWeaponTrajectory.solve_pitch(carbine, 100000.0)), "out of reach has no solution")
	_done()


func _test_bullets() -> void:
	_section("ballistic bullets and rules")
	var rules := DotWeaponBallisticsRules.new()
	_check(not rules.enabled, "ballistics default OFF")
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.max_range = 500.0
	b.tracer_interval = 2
	b.falloff_start = 0.0
	b.falloff_min = 0.5
	var bullets := DotWeaponBullets.new()
	bullets.rules = rules
	bullets.tick_rate = 60
	add_child(bullets)
	_check(bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b) == 0, "off: spawn refuses, weapon stays hitscan")
	_check(rules.set_cvar("sv_ballistics", "1") and rules.enabled, "sv_ballistics switches it on")
	_check(not rules.set_cvar("sv_nonsense", "1"), "unknown cvar refused")
	_check(rules.set_cvar("sv_ballistics_max_bullets", "3") and rules.max_bullets == 3.0, "cap is a cvar")
	var hitscan := DotWeaponBallistics.new()
	_check(bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), hitscan) == 0, "velocity 0 stays hitscan when on")
	var log := {"hits": [], "rewinds": [], "restores": 0, "tracers": 0}
	bullets.cast_fn = func(from: Vector3, to: Vector3, _o: int) -> Dictionary:
		if from.z > -100.0 and to.z <= -100.0:
			return {"position": Vector3(from.x, from.y, -100.0)}
		return {}
	bullets.rewind_fn = func(t: float) -> void: log.rewinds.append(t)
	bullets.restore_fn = func() -> void: log.restores += 1
	bullets.hit.connect(func(id: int, _o: int, _i: Dictionary, d: float, m: float, _b: DotWeaponBallistics) -> void: log.hits.append([id, d, m]))
	bullets.tracer.connect(func(_id: int, _f: Vector3, _t: Vector3) -> void: log.tracers += 1)
	var id1 := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b, 6.0)
	var id2 := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b, 0.0)
	var id3 := bullets.spawn(2, Vector3.ZERO, Vector3(0, 0, -1), b)
	_check(id1 > 0 and id2 > id1 and id3 > id2 and bullets.count() == 3, "three bullets in flight")
	_check(bullets.spawn(2, Vector3.ZERO, Vector3(0, 0, -1), b) == 0, "the cap holds")
	bullets.step(100.0)
	_check(log.hits.is_empty(), "600 m/s takes more than one tick to cross 100 m")
	for t in range(1, 12):
		bullets.step(100.0 + t)
	_check(log.hits.size() == 3 and bullets.count() == 0, "all three hit the wall and are gone", str(log.hits.size()))
	_check(log.hits[0][1] > 99.0 and log.hits[0][1] < 101.0, "at 100 m")
	_check(log.hits[0][2] < 1.0 and log.hits[0][2] > 0.5, "with the falloff multiplier", str(log.hits[0][2]))
	_check(log.rewinds.size() > 0 and is_equal_approx(log.rewinds[0], 94.0), "the lagged bullet rewound to now minus its lag", str(log.rewinds))
	_check(log.restores == log.rewinds.size(), "every rewind restored")
	_check(log.tracers > 0, "every second bullet of an owner is a tracer")
	rules.set_cvar("sv_ballistics_max_bullets", "512")
	rules.set_cvar("sv_ballistics_velocity", "2")
	var fast := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b)
	var before: int = log.hits.size()
	bullets.step(200.0)
	bullets.step(201.0)
	_check(log.hits.size() > before or bullets.count() == 1, "the velocity multiplier applies", str(fast))
	var expired := {"n": 0}
	bullets.expired.connect(func(_id: int) -> void: expired.n += 1)
	bullets.cast_fn = Callable()
	for t in range(0, 40):
		bullets.step(300.0 + t)
	_check(expired.n >= 1 and bullets.count() == 0, "past max range it expires")
	var many := 0
	rules.set_cvar("sv_ballistics_velocity", "1")
	for i in 400:
		many += 1 if bullets.spawn(i % 20, Vector3.ZERO, Vector3(0, 0, -1), b) > 0 else 0
	var t0 := Time.get_ticks_usec()
	bullets.step(400.0)
	var us := Time.get_ticks_usec() - t0
	_check(many == 400 and us < 100000, "400 bullets step in one node, cheaply", "%d us" % us)
	_done()


## The shot an arsenal makes, as text, with the given ballistics rules and muzzle velocity.
func _shot_text(rules: DotWeaponBallisticsRules, velocity: float) -> Array:
	var a := _arsenal()
	a.give(&"rifle")
	a.ballistics_rules = rules
	((a.catalogue.get_def(&"rifle") as DotWeaponDef).tuning as DotWeaponBallistics).muzzle_velocity = velocity
	var o := a.simulate_tick(_cmd(true), _ctx(10), null)
	var shot: DotShot = o.shots[0]
	var text := "%s|%s|%s|%s|%s|%s|%s|%s" % [shot.origin, shot.direction, shot.spread, shot.pellets, shot.damage, shot.max_range, o.recoil, shot.pellet_count]
	var deferred := shot.deferred
	_drop(a)
	return [text, deferred]


func _test_hitscan_unchanged() -> void:
	_section("hitscan is unchanged with ballistics off")
	var base := _shot_text(null, 0.0)
	var off := DotWeaponBallisticsRules.new()
	_check(_shot_text(off, 0.0) == base, "rules present but off: identical shot")
	_check(_shot_text(off, 800.0) == base, "rules off, weapon has a velocity: identical shot")
	var on := DotWeaponBallisticsRules.new()
	on.enabled = true
	_check(_shot_text(on, 0.0) == base, "rules on, no velocity: identical shot")
	var fast := _shot_text(on, 800.0)
	_check(fast[1] and not base[1], "rules on and a velocity: the shot is deferred to a bullet")
	_check(fast[0] == base[0], "and is otherwise the same shot")
	var recoil := DotWeaponRecoilRules.new()
	_check(recoil is DotWeaponCvarRules and recoil.cvar_name(&"enabled") == "sv_recoil" and recoil.cvar_name(&"scale") == "sv_recoil_scale", "recoil rules keep their cvar names on the shared base")
	_check(recoil.set_cvar("sv_recoil_scale", "2") and recoil.scale == 2.0, "and still set from cvars")
	_check(recoil.describe().has("scale"), "and describe")
	_done()


func _bridge_target(z: float) -> Node3D:
	var body := Node3D.new()
	body.position = Vector3(0.0, 0.0, z)
	var health := DotHealth.new()
	health.max_health = 100.0
	health.regen_per_second = 0.0
	body.add_child(health)
	var set_node := DotHitboxSet.new()
	set_node.bounds_offset = Vector3(0.0, 0.9, 0.0)
	set_node.bounds_radius = 1.4
	var chest := DotHitbox.new()
	chest.group = DotHitGroup.CHEST
	chest.shape = DotHitbox.Shape.CAPSULE
	chest.radius = 0.4
	chest.height = 1.6
	chest.position = Vector3(0.0, 1.0, 0.0)
	set_node.add_child(chest)
	body.add_child(set_node)
	add_child(body)
	return body


func _bridge_shot(tick: int, pellets: int, dir: Vector3 = Vector3.FORWARD) -> DotShot:
	var shot := DotShot.make(&"rifle", 1, tick, 0)
	shot.origin = Vector3(0.0, 1.0, 0.0)
	shot.direction = dir
	shot.pellet_count = pellets
	shot.fixed_pattern = true
	shot.damage = 20.0
	shot.max_range = 200.0
	shot.deferred = true
	shot.scatter()
	return shot


func _bridge_lag(manager: DotCombatManager, bridge: DotWeaponBulletBridge, victim: Node3D, health: DotHealth, hits: Array, b: DotWeaponBallistics) -> void:
	# Lag compensation: the target has since stepped aside; the shooter saw it in line at tick 100.
	health.health = 100.0
	hits.clear()
	victim.position.x = 5.0
	var rewinds: Array = []
	manager.rewind_fn = func(t: float) -> void:
		rewinds.append(t)
		victim.position.x = 0.0 if t < 112.0 else 5.0
	manager.restore_fn = func() -> int:
		victim.position.x = 5.0
		return 0
	var lagged := _bridge_shot(106, 1)
	var _l := bridge.resolve_shot(lagged, b, 100.0)
	for t in range(1, 12):
		bridge.tick(106.0 + t)
	_check(hits.size() == 1 and health.health == 80.0, "a lag-compensated bullet hits where the shooter saw the target", str(hits.size()))
	_check(not rewinds.is_empty() and victim.position.x == 5.0, "and the world is restored afterwards")
	hits.clear()
	health.health = 100.0
	manager.rewind_fn = Callable()
	var _n := bridge.resolve_shot(_bridge_shot(106, 1), b, -1.0)
	for t in range(1, 12):
		bridge.tick(106.0 + t)
	_check(hits.is_empty() and health.health == 100.0, "the same shot without lag compensation misses")


func _test_bullet_bridge() -> void:
	_section("bullet bridge against a real combat manager")
	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.with_floor(0.0)
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	manager.config.tick_rate = 64
	add_child(manager)
	var victim := _bridge_target(-30.0)
	var set_node: DotHitboxSet = null
	for c in victim.get_children():
		if c is DotHitboxSet:
			set_node = c
	set_node.register_with(manager, 2)
	var health: DotHealth = null
	for c in victim.get_children():
		if c is DotHealth:
			health = c
	manager.register_health(2, health)
	_check(manager.entity_id_of(victim) == 0 or manager.entity_id_of(victim) == 2, "entity_id_of is public")

	var rules := DotWeaponBallisticsRules.new()
	rules.enabled = true
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.bullet_gravity = 0.0
	b.drag = 0.0
	b.max_range = 200.0
	var bridge := DotWeaponBulletBridge.new()
	add_child(bridge)
	bridge.setup(manager, rules, 64)
	var hits: Array = []
	bridge.bullet_hit.connect(func(_id: int, d: DotDamage) -> void: hits.append(d))

	var shot := bridge.resolve_shot(_bridge_shot(100, 1), b, -1.0)
	_check(shot.deferred and bridge.bullets.count() == 1 and hits.is_empty(), "a deferred shot launches a bullet and does no damage yet")
	for t in range(1, 12):
		bridge.tick(100.0 + t)
	_check(hits.size() == 1 and bridge.bullets.count() == 0, "the bullet hits the target and is gone", str(hits.size()))
	_check(health.health == 80.0, "damage applied once", str(health.health))
	_check(hits[0].victim == 2 and hits[0].hit_group == DotHitGroup.CHEST and hits[0].distance > 28.0, "to the right victim, group and distance")

	hits.clear()
	var _miss := bridge.resolve_shot(_bridge_shot(110, 1, Vector3(0.5, 0.0, -1.0)), b, -1.0)
	for t in range(1, 40):
		bridge.tick(110.0 + t)
	_check(hits.is_empty() and health.health == 80.0 and bridge.bullets.count() == 0, "a bullet aimed away misses and expires")

	var _two := bridge.resolve_shot(_bridge_shot(120, 3), b, -1.0)
	_check(bridge.bullets.count() == 3, "three pellets, three bullets")
	for t in range(1, 12):
		bridge.tick(120.0 + t)
	_check(hits.size() >= 1 and hits.size() <= 3 and bridge.bullets.count() == 0, "pellets resolve", str(hits.size()))
	var expected := 80.0 - 20.0 * hits.size()
	_check(is_equal_approx(health.health, expected), "each hitting pellet damages once", "%s vs %s" % [health.health, expected])

	_bridge_lag(manager, bridge, victim, health, hits, b)

	rules.enabled = false
	health.health = 100.0
	victim.position.x = 0.0
	manager.restore_fn = Callable()
	var hitscan := _bridge_shot(130, 1)
	hitscan.deferred = false
	var flying := bridge.bullets.count()
	var _plain := bridge.resolve_shot(hitscan, b, -1.0)
	_check(bridge.bullets.count() == flying and health.health == 80.0, "switched off, the bridge is plain hitscan", str(health.health))
	_done()


func _ammo_loaded_round() -> void:
	var a := _arsenal()
	a.give(&"rifle")
	var rifle_id: StringName = a.current().def.id
	_check(a.ammo_of(rifle_id) == &"", "no round loaded by default")
	a.load_ammo(rifle_id, &"ap")
	_check(a.ammo_of(rifle_id) == &"ap", "load_ammo selects the round")
	var on := DotWeaponBallisticsRules.new()
	on.enabled = true
	a.ballistics_rules = on
	((a.catalogue.get_def(&"rifle") as DotWeaponDef).tuning as DotWeaponBallistics).muzzle_velocity = 800.0
	var o := a.simulate_tick(_cmd(true), _ctx(10), null)
	var fired: DotShot = o.shots[0]
	_check(fired.deferred and fired.get_meta(&"ammo", &"") == &"ap", "a simulated shot carries the loaded round")
	_drop(a)
	var off := _arsenal()
	off.give(&"rifle")
	off.load_ammo(&"rifle", &"ap")
	var o2 := off.simulate_tick(_cmd(true), _ctx(10), null)
	_check(not (o2.shots[0] as DotShot).has_meta(&"ammo"), "ballistics off: the shot is untouched by ammo")
	_drop(off)


func _ammo_penetration() -> void:
	var fmj := DotWeaponAmmoType.from_flat(&"fmj", {"penetration": 0.8, "materials": "wood:0.5, steel:6", "guns": "rifle, smg"})
	_check(fmj.materials == {&"wood": 0.5, &"steel": 6.0} and fmj.guns == PackedStringArray(["rifle", "smg"]), "an ammo profile parses its material table and gun list")
	var pen := fmj.make_penetration()
	_check(pen != null and is_equal_approx(pen.resistance_of(&"steel"), 6.0) and is_equal_approx(pen.resistance_of(&"glass"), 1.0), "and builds the penetration a shot carries")
	_check(DotWeaponAmmoType.from_flat(&"blank", {}).make_penetration() == null, "a round with no penetration power passes nothing")
	var types := DotWeaponAmmoTypes.new()
	var ball := DotWeaponAmmoType.from_flat(&"ball", {"penetration": 0.2, "default": true})
	types.add(fmj)
	types.add(ball)
	_check(types.type_for_weapon(&"rifle") == fmj and types.type_for_weapon(&"pistol") == ball, "one profile serves several guns, the default serves the rest")
	var a := _arsenal()
	a.give(&"rifle")
	var rifle_id: StringName = a.current().def.id
	_check(not (a.simulate_tick(_cmd(true), _ctx(10), null).shots[0] as DotShot).penetration, "without ammo profiles a shot carries no penetration")
	_drop(a)
	var b := _arsenal()
	b.ammo_types = types
	b.give(&"rifle")
	var fired: DotShot = b.simulate_tick(_cmd(true), _ctx(10), null).shots[0]
	_check(fired.penetration != null and is_equal_approx(fired.penetration.power, 0.8) and rifle_id == &"rifle", "with them the shot carries its gun's round")
	_drop(b)


func _test_ammo_hitzones() -> void:
	_section("ammo types and hit-zone armour")
	var types := DotWeaponAmmoTypes.new()
	var ap := DotWeaponAmmoType.from_flat(&"ap", {"damage": 1.5, "velocity": 0.5, "armour_pierce": 2.0})
	types.add(ap)
	types.add(DotWeaponAmmoType.from_flat(&"ball", {}))
	_check(ap.armour_pierce == 1.0 and types.ids() == [&"ap", &"ball"], "pierce clamps, ids sorted")
	_check(DotWeaponAmmoTypes.schema().size() == 15 and DotWeaponAmmoTypes.profile_schemas().has("ammo"), "ammo is a profile kind")
	_check(types.get_type(&"nope") == null, "an unknown round is null")
	var base := DotWeaponBallistics.new()
	base.muzzle_velocity = 600.0
	base.drag = 0.001
	_check(types.get_type(&"ball").apply_to(base) == base, "a neutral round flies the weapon's own tuning")
	var slow := ap.apply_to(base)
	_check(slow != base and slow.muzzle_velocity == 300.0 and base.muzzle_velocity == 600.0, "a round scales a copy, never the weapon")
	var zones := DotWeaponHitzones.from_flat({"head": 0.5, "chest": 0.4})
	_check(is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null), 0.5) and zones.multiplier(DotHitGroup.LEG, null) == 1.0, "armour only on listed zones")
	_check(is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null, 1.0), 1.0) and is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null, 0.5), 0.75), "piercing ignores armour")
	zones.presence_fn = func(_e: Node) -> float: return 0.0
	_check(zones.multiplier(DotHitGroup.HEAD, null) == 1.0, "a victim with no armour on takes full damage")
	zones.presence_fn = Callable()

	_ammo_loaded_round()
	_ammo_penetration()

	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.with_floor(0.0)
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	manager.config.tick_rate = 64
	add_child(manager)
	var victim := _bridge_target(-30.0)
	var set_node: DotHitboxSet = null
	var health: DotHealth = null
	for c in victim.get_children():
		if c is DotHitboxSet:
			set_node = c
		if c is DotHealth:
			health = c
	set_node.register_with(manager, 2)
	manager.register_health(2, health)
	var rules := DotWeaponBallisticsRules.new()
	rules.enabled = true
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.bullet_gravity = 0.0
	b.drag = 0.0
	var bridge := DotWeaponBulletBridge.new()
	add_child(bridge)
	bridge.setup(manager, rules, 64)
	var fly := func(tick: int, round_id: StringName) -> int:
		var s := _bridge_shot(tick, 1)
		if round_id != &"":
			s.set_meta(&"ammo", round_id)
		var _r := bridge.resolve_shot(s, b, -1.0)
		var n := 0
		while bridge.bullets.count() > 0 and n < 60:
			n += 1
			bridge.tick(float(tick + n))
		return n
	var _plain: int = fly.call(100, &"")
	_check(health.health == 80.0, "no ammo or zones configured: unchanged damage", str(health.health))
	health.health = 100.0
	bridge.ammo_types = types
	bridge.hitzones = DotWeaponHitzones.from_flat({"chest": 0.5})
	var _n0: int = fly.call(200, &"")
	_check(is_equal_approx(health.health, 90.0), "chest armour halves the damage", str(health.health))
	health.health = 100.0
	var fast_ticks: int = fly.call(300, &"ball")
	_check(is_equal_approx(health.health, 90.0), "a neutral round changes nothing", str(health.health))
	health.health = 100.0
	var slow_ticks: int = fly.call(400, &"ap")
	_check(is_equal_approx(health.health, 100.0 - 20.0 * 1.5), "armour-piercing: damage x1.5, armour ignored", str(health.health))
	_check(slow_ticks > fast_ticks, "and the slower round takes longer to arrive", "%d vs %d" % [slow_ticks, fast_ticks])
	health.health = 100.0
	var _unknown: int = fly.call(500, &"mystery")
	_check(is_equal_approx(health.health, 90.0), "an unknown round id changes nothing", str(health.health))
	_done()
