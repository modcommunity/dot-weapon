extends "sections_content.gd"

## Melee, beam, carry, spread, recoil, ballistics and bridge sections of the suite.

func _test_melee() -> void:
	_section("melee is a very short shot")

	var a := _arsenal()
	a.give(&"knife")
	a.select(4, 0)
	_drive(a, 0, 1, false)

	var swings := _drive(a, 10, 2, true)
	_check(swings.size() == 1, "a swing happens")

	var swing := swings[0]
	_check(swing.kind == DotWeaponOutcome.KIND_SWING, "and says it is a swing")
	_check(swing.shots.size() == 1, "producing one shot")
	_check(swing.shots[0].pellet_count == 5, "sampled across the arc")
	_close(swing.shots[0].max_range, 2.0, "reaching only as far as the blade")
	_check(
		swing.shots[0].fixed_pattern,
		"on a fixed pattern: a swing that scattered differently every time would "
		+ "sometimes miss a target standing still in front of it"
	)
	_check(
		swing.shots[0].pellets.size() == 5,
		"and the arc directions are built",
		str(swing.shots[0].pellets.size())
	)

	# A knife costs no ammunition and needs none declared.
	_check(a.current().def.ammo_type == &"", "a knife declares no ammunition")
	var many := 0
	var prev: DotWeaponCommand = null
	for i in range(200):
		# Tapped, not held: a knife is semi-automatic, so holding it is one swing.
		var cmd := _cmd(i % 25 == 0)
		if a.simulate_tick(cmd, _ctx(1000 + i), prev).used:
			many += 1
		prev = cmd
	_check(many >= 6, "and swings for as long as you like", str(many))

	_drop(a)
	_done()


func _test_beam() -> void:
	_section("a beam ramps while it is held")

	var a := _arsenal()
	a.give(&"flamer")
	a.select(5, 0)
	_drive(a, 0, 1, false)

	var ticks := _drive(a, 10, 40, true)
	_check(ticks.size() == 10, "a held beam works every interval", str(ticks.size()))

	var first := ticks[0].shots[0].damage
	var last := ticks[ticks.size() - 1].shots[0].damage
	_check(first < last, "ramping up as it is held", "%.2f then %.2f" % [first, last])
	_close(last, 6.0, "to its full output", 0.1)

	# Releasing announces the stop even though it produced nothing, because a looping
	# sound and a particle stream both need an off switch.
	var previous := _cmd(true)
	a.simulate_tick(previous, _ctx(200), null)
	var stop := a.simulate_tick(_cmd(false), _ctx(201), previous)
	_check(not stop.used, "releasing produces no damage")
	_check(stop.events.size() == 1, "but does announce the beam stopping")

	_drop(a)
	_done()


func _test_thrown() -> void:
	_section("a grenade's fuse starts when the pin comes out")

	var a := _arsenal()
	a.give(&"grenade")
	a.select(6, 0)
	_drive(a, 0, 1, false)

	# A quick throw keeps almost the whole fuse.
	var p := _cmd(true)
	a.simulate_tick(p, _ctx(100), null)
	for i in range(9):
		var c := _cmd(true)
		a.simulate_tick(c, _ctx(101 + i), p)
		p = c

	var quick := a.simulate_tick(_cmd(false), _ctx(110), p)
	_check(quick.used, "a grenade is thrown")
	_check(quick.kind == DotWeaponOutcome.KIND_THROW, "as a throw")
	_check(
		quick.spawns[0].fuse_ticks > 170,
		"with most of its fuse left",
		str(quick.spawns[0].fuse_ticks)
	)

	# A cooked one keeps much less.
	var b := _arsenal()
	b.give(&"grenade")
	b.select(6, 0)
	_drive(b, 0, 1, false)

	var p2 := _cmd(true)
	b.simulate_tick(p2, _ctx(200), null)
	for i in range(120):
		var c2 := _cmd(true)
		b.simulate_tick(c2, _ctx(201 + i), p2)
		p2 = c2

	var cooked := b.simulate_tick(_cmd(false), _ctx(321), p2)
	_check(
		cooked.spawns[0].fuse_ticks < quick.spawns[0].fuse_ticks,
		"cooking spends the fuse",
		"%d vs %d" % [cooked.spawns[0].fuse_ticks, quick.spawns[0].fuse_ticks]
	)

	# Cooking all the way goes off in the hand, which is the cost of cooking at all.
	var c3 := _arsenal()
	c3.give(&"grenade")
	c3.select(6, 0)
	_drive(c3, 0, 1, false)

	var p3 := _cmd(true)
	c3.simulate_tick(p3, _ctx(400), null)
	for i in range(200):
		var cc := _cmd(true)
		c3.simulate_tick(cc, _ctx(401 + i), p3)
		p3 = cc

	var boom := c3.simulate_tick(_cmd(false), _ctx(601), p3)
	_check(boom.used, "a fully cooked grenade still leaves the definition")
	_check(boom.spawns[0].fuse_ticks == 0, "with no fuse left")
	_check(
		boom.spawns[0].velocity == Vector3.ZERO,
		"and no velocity: it went off in the hand, which is what cooking risks"
	)
	_check(boom.events.size() == 1, "and that is announced")

	_drop(a)
	_drop(b)
	_drop(c3)
	_done()


## Ticks for one weapon to finish a reload started on [param from], driving no buttons.


func _test_carry() -> void:
	_section("carry weight")
	var cat := _catalogue()
	var twin := _pistol()
	twin.id = &"pistol2"
	cat.add(twin)
	cat.get_def(&"rifle").weight = 12.0
	cat.get_def(&"pistol").weight = 4.0
	twin.weight = 5.0
	cat.get_def(&"knife").weight = 1.0
	var a := _arsenal(cat)
	_check(a.give(&"rifle").ok and a.carried_weight() == 0.0 and a.capacity() == INF, "with no carry rules nothing weighs and nothing is refused")
	_check(a.give(&"pistol2").ok and a.weapons_in(2).size() == 1, "and a slot holds one weapon")
	a.clear()
	var carry := DotWeaponCarry.new()
	a.carry = carry
	_check(a.give(&"rifle").ok and a.carried_weight() == 0.0, "a disabled carry weighs nothing")
	carry.enabled = true
	carry.base_limit = 20.0
	carry.slot_capacity = 2
	_check(is_equal_approx(a.carried_weight(), 12.0) and is_equal_approx(a.capacity(), 20.0), "enabled, weights count and the limit is the base")
	_check(a.give(&"pistol").ok and is_equal_approx(a.carried_weight(), 16.0), "a weapon under the limit is taken")
	var refused := a.give(&"pistol2")
	_check(not refused.ok and refused.error.code == DotError.CODE_QUOTA and refused.error.message.contains("Too heavy"), "an over-weight pickup is refused with a message")
	_check(a.weapons_in(2).size() == 1 and not a.carries(&"pistol2"), "and nothing changed")
	_check(not a.equip_backpack(4) and a.equip_backpack(1) and is_equal_approx(a.capacity(), 30.0), "a backpack raises the limit, a tier that does not exist is refused")
	_check(not a.equip_backpack(1), "and the same tier again is not an upgrade")
	_check(a.give(&"pistol2").ok and a.weapons_in(2).size() == 2, "the same pickup now fits and stows beside the first")
	_check(a.slot_at(2).id() == &"pistol2" and a.weapons_in(2)[1].id() == &"pistol", "the new weapon is in hand, the old behind it")
	_check(a.carries(&"pistol") and a.carries(&"pistol2"), "carries sees stowed weapons")
	_check(a.select(2, 0) and a.is_switching(), "slot 2 selected")
	_drive(a, 1, 60, false)
	_check(a.current_slot() == 2, "slot 2 is in hand")
	_check(a.cycle_slot(100) and a.slot_at(2).id() == &"pistol" and a.weapons_in(2)[1].id() == &"pistol2", "the slot key again brings the next weapon")
	_check(a.is_switching(), "and it deploys")
	_check(not a.cycle_slot(101) or a.slot_at(2).id() == &"pistol2", "cycling twice returns")
	var snap := a.snapshot()
	var b := _arsenal(cat)
	b.carry = carry
	_check(b.restore(snap).ok and b.weapons_in(2).size() == 2 and b.backpack_tier == 1, "a snapshot carries the shelf and the backpack")
	_check(is_equal_approx(b.carried_weight(), a.carried_weight()), "and the same weight")
	carry.set_modifier(&"heavy_box", 2.0)
	_check(is_equal_approx(carry.weight_factor(), 2.0) and a.over_by() > 0.0, "a modifier doubling weights puts the carrier over")
	_check(a.speed_scale() < 1.0 and a.speed_scale() >= carry.slow_floor, "SLOW mode slows within the floor")
	carry.over_limit = DotWeaponCarry.OverLimit.DROP
	_check(is_equal_approx(a.speed_scale(), 1.0), "DROP mode does not slow")
	var dropped := a.enforce_limit()
	_check(a.over_by() <= 0.0001 and not dropped.is_empty() and a.current() != null, "DROP sheds weapons until under, keeping the one in hand")
	carry.clear_modifier(&"heavy_box")
	carry.set_modifier(&"depression", 1.0, 0.5)
	_check(is_equal_approx(a.capacity(), 15.0), "a limit modifier halves the capacity")
	carry.set_modifier(&"depression", 1.0, 1.0, 5.0)
	_check(is_equal_approx(a.capacity(), 35.0), "a flat addition raises it")
	carry.clear_modifiers()
	carry.multiplier = 0.5
	_check(is_equal_approx(carry.weight_of(cat.get_def(&"rifle")), 6.0), "the global multiplier scales a weight")
	carry.over_limit = DotWeaponCarry.OverLimit.SLOW
	_check(carry.speed_scale(10.0, 20.0) == 1.0 and carry.speed_scale(40.0, 20.0) == 0.5, "speed scale is 1 under, floored over")
	var from_file := DotWeaponDef.new()
	DotWeaponProfiles.apply_common(from_file, {"weight": 7.5})
	_check(is_equal_approx(from_file.weight, 7.5), "weight is a profile key")
	_check(str(DotWeaponProfiles.schema()).contains("weight"), "and in the schema")
	var t := a.take(2)
	_check(t.ok and a.carried_weight() < 16.0, "take removes a weapon")
	_done()


func _spread_sprint_blocks(a: DotWeaponArsenal, aim_cmd: DotWeaponCommand) -> void:
	var sprint_ctx := _ctx(200)
	sprint_ctx.sprinting = true
	sprint_ctx.sprint_blocks_aim = true
	var _w := a.simulate_tick(aim_cmd, sprint_ctx, null)
	_check(not sprint_ctx.aiming, "sprinting with sprint_blocks_aim drops the aim")
	var reload_cmd := _cmd(false)
	reload_cmd.set_button(DotWeaponCommand.BUTTON_RELOAD, true)
	var _x := a.simulate_tick(reload_cmd, sprint_ctx, null)
	_check(not a.is_reloading(), "and refuses a reload")
	sprint_ctx.sprint_blocks_aim = false
	sprint_ctx.tick = 201
	var _y := a.simulate_tick(reload_cmd, sprint_ctx, null)
	_check(a.is_reloading() and sprint_ctx.sprinting, "sprinting alone leaves the reload and the aim alone")
	var fired := _arsenal()
	fired.give(&"rifle")
	var fire_ctx := _ctx(300)
	fire_ctx.sprinting = true
	fire_ctx.sprint_blocks_fire = true
	var blocked := fired.simulate_tick(_cmd(true), fire_ctx, null)
	_check(not blocked.used, "sv_sprint_shoot 0 refuses the trigger while sprinting")
	fire_ctx.sprint_blocks_fire = false
	fire_ctx.tick = 301
	_check(fired.simulate_tick(_cmd(true), fire_ctx, null).used, "and sprinting may shoot when it is allowed")
	_drop(fired)



func _test_spread_rules() -> void:
	_section("movement-dependent spread")

	var rules := DotWeaponSpreadRules.new()
	var ctx := _ctx(1)
	_check(is_equal_approx(rules.target_factor(ctx), 1.0), "off: every posture is factor 1")
	rules.enabled = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_stand * rules.mult_hip), "still at the hip")
	ctx.speed = 2.0
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_walk), "walking")
	ctx.speed = 6.0
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_run), "running")
	ctx.airborne = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_air), "in the air, speed ignored")
	ctx.sliding = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_slide), "sliding")
	ctx.airborne = false
	ctx.sliding = false
	ctx.sprinting = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_sprint), "sprinting")
	ctx.sprinting = false
	ctx.speed = 0.0
	ctx.crouched = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_crouch), "crouched tightens")
	ctx.aiming = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_crouch * rules.mult_aim), "aimed and crouched tightest")
	_check(is_equal_approx(rules.apply(5.0, 10.0), rules.max_spread), "the cap holds")
	_check(rules.set_cvar("sv_spread_mult_run", "2.5") and is_equal_approx(rules.mult_run, 2.5), "a cvar sets a multiplier")
	_check(rules.set_cvar("sv_spread_mult_run", "99") and is_equal_approx(rules.mult_run, 10.0), "and is clamped to its range")
	_check(not rules.set_cvar("sv_nonsense", "1") and not rules.set_cvar("sv_spread_mult_run", "x"), "unknown names and values are refused")

	var a := _arsenal()
	a.give(&"rifle")
	var tuning := a.current().def.tuning as DotWeaponBallistics
	tuning.spread = 1.0
	tuning.spread_moving = 1.0
	tuning.spread_airborne = 1.0
	a.spread_rules = rules
	rules.mult_run = 3.0
	rules.mult_hip = 1.0
	rules.mult_crouch = 1.0
	rules.recovery = 64.0
	var moving := _ctx(2)
	moving.speed = 6.0
	var out := a.simulate_tick(_cmd(true), moving, null)
	_check(out.used and is_equal_approx(out.shots[0].spread, 3.0), "a run triples the gun's own spread", str(out.shots[0].spread))
	_check(is_equal_approx(a.spread_now(), 3.0), "and the crosshair reads the same cone")
	var still := _ctx(3)
	var _t := a.simulate_tick(_cmd(false), still, null)
	_check(a.spread_now() > 1.0 and a.spread_now() < 3.0, "settles over ticks, not at once", str(a.spread_now()))
	for i in range(80):
		var _s := a.simulate_tick(_cmd(false), _ctx(4 + i), null)
	_check(is_equal_approx(a.spread_now(), 1.0), "and recovers to the base", str(a.spread_now()))
	var aimed := _ctx(100)
	var aim_cmd := _cmd(false)
	aim_cmd.set_button(DotWeaponCommand.BUTTON_AIM, true)
	var _u := a.simulate_tick(aim_cmd, aimed, null)
	_check(is_equal_approx(a.spread_now(), 0.5), "aiming halves it", str(a.spread_now()))
	rules.enabled = false
	var _v := a.simulate_tick(_cmd(false), _ctx(101), null)
	_check(is_equal_approx(a.spread_now(), 1.0), "disabled, the gun keeps its own spread")
	_spread_sprint_blocks(a, aim_cmd)
	_drop(a)
	_done()


## Standing < walking < running < sprinting and airborne; crouched and aimed tighter. Through the
## arsenal's spread_now, with the data a shotgun ships (spread_moving below spread, crouched 1+).
func _test_spread_ladder() -> void:
	_section("spread ladder: still < walk < run < air")
	for shotgun in [false, true]:
		var rules := DotWeaponSpreadRules.new()
		rules.enabled = true
		rules.recovery = 0.0
		var a := _arsenal()
		a.give(&"rifle")
		var t := a.current().def.tuning as DotWeaponBallistics
		t.spread = 4.0 if shotgun else 0.5
		t.spread_moving = 0.5 if shotgun else 2.0
		t.spread_airborne = 1.0 if shotgun else 4.0
		t.spread_crouched = 4.0 if shotgun else 0.5
		a.spread_rules = rules
		var tick := 10
		var got := {}
		for key: String in ["still", "walk", "run", "sprint", "air", "crouch", "aim"]:
			var c := _ctx(tick)
			tick += 1
			c.speed = {"walk": 2.0, "run": 6.0, "sprint": 7.0}.get(key, 0.0)
			c.sprinting = key == "sprint"
			c.airborne = key == "air"
			c.crouched = key == "crouch"
			var cmd := _cmd(false)
			if key == "aim":
				cmd.set_button(DotWeaponCommand.BUTTON_AIM, true)
			var _o := a.simulate_tick(cmd, c, null)
			got[key] = a.spread_now()
		var tag := " (shotgun data)" if shotgun else ""
		_check(got["still"] < got["walk"] and got["walk"] < got["run"], "still < walk < run" + tag, str(got))
		_check(got["run"] < got["sprint"] and got["run"] < got["air"], "run < sprint and air" + tag, str(got))
		_check(got["crouch"] < got["still"] and got["aim"] < got["still"], "crouched and aimed are tighter" + tag, str(got))
		_drop(a)
	var bal := DotWeaponBallistics.new()
	var sniper := bal.crosshair_scale_for([&"primary", &"scoped"])
	var smg := bal.crosshair_scale_for([&"primary", &"automatic"])
	var plain := bal.crosshair_scale_for([&"primary"])
	_check(sniper > plain and plain > smg, "gap scale: sniper > usual gun > automatic", "%s %s %s" % [sniper, plain, smg])
	bal.crosshair_scale = 2.0
	_check(is_equal_approx(bal.crosshair_scale_for([&"automatic"]), 2.0), "an explicit crosshair_scale beats the class default")
	var xs := DotWeaponDef.new()
	DotWeaponProfiles.apply_common(xs, {"crosshair_scale": 3.0})
	_check(is_equal_approx(xs.crosshair_scale, 3.0) and str(DotWeaponProfiles.schema()).contains("crosshair_scale"), "crosshair_scale is a schema field the def takes")
	var xa := _arsenal()
	xa.give(&"rifle")
	var xdef := xa.current().def
	xdef.crosshair_scale = 0.0
	(xdef.tuning as DotWeaponBallistics).crosshair_scale = 1.5
	_check(is_equal_approx(xa.crosshair_scale(), 1.5), "def field 0 falls back to extra.tuning crosshair_scale")
	xdef.crosshair_scale = 0.5
	_check(is_equal_approx(xa.crosshair_scale(), 0.5), "the def field beats the tuning path")
	_drop(xa)
	_done()


func _burst(rules: DotWeaponRecoilRules, shots: int, start_tick: int) -> Array:
	var a := _arsenal()
	a.give(&"rifle")
	a.recoil_rules = rules
	var out: Array = []
	for i in range(shots):
		var o := a.simulate_tick(_cmd(true), _ctx(start_tick + i * 6), null)
		out.append(o)
		var _r := a.simulate_tick(_cmd(false), _ctx(start_tick + i * 6 + 1), null)
	_drop(a)
	return out


func _test_recoil_rules() -> void:
	_section("per-weapon recoil patterns")

	var rules := DotWeaponRecoilRules.new()
	_check(DotWeaponRecoilRules.of(null) == null, "no arsenal, no rules")
	var off := _burst(rules, 3, 10)
	_check(off[0].recoil == Vector2(0.5, 0.2) and not off[0].recoil_signed, "off: the flat kick")
	rules.enabled = true
	rules.horizontal = 1.0
	var tuning := _rifle().tuning as DotWeaponBallistics
	_check(tuning.recoil_build > 0.0, "ballistics carry a build")

	var run1 := _burst(rules, 6, 10)
	var run2 := _burst(rules, 6, 10)
	var same := true
	for i in range(6):
		same = same and run1[i].recoil == run2[i].recoil
	_check(same, "the pattern repeats exactly from the same seed")
	_check(run1[0].recoil_signed and run1[0].recoil_recovery > 0.0, "the outcome carries a signed kick and its recovery")
	_check(run1[0].recoil.x > 0.0 and is_equal_approx(run1[0].recoil.x, 0.5), "first shot is the base kick", str(run1[0].recoil))
	_check(run1[5].recoil.x > run1[0].recoil.x, "sustained fire builds", str(run1[5].recoil.x))
	_check(run1[5].recoil.x <= 0.5 * (1.0 + tuning.recoil_build_max) + 0.001, "and is capped")
	var yaws := {}
	for i in range(6):
		yaws[snappedf(run1[i].recoil.y, 0.0001)] = true
	_check(yaws.size() > 2, "sideways drift varies shot to shot")
	_check(is_equal_approx(DotWeaponRecoilRules.drift(7, 3), DotWeaponRecoilRules.drift(7, 3)) and DotWeaponRecoilRules.drift(7, 3) != DotWeaponRecoilRules.drift(8, 3), "drift is a pure function of seed and index")
	_check(DotWeaponRecoilRules.seed_for(null, &"ak") == DotWeaponRecoilRules.seed_for(null, &"ak") and DotWeaponRecoilRules.seed_for(null, &"ak") != DotWeaponRecoilRules.seed_for(null, &"m4"), "an id seeds stably")

	var gap := _burst(rules, 2, 10)
	_check(is_equal_approx(gap[1].recoil.x, 0.5 * (1.0 + tuning.recoil_build)), "the second shot of a burst is built up")

	var a := _arsenal()
	a.give(&"rifle")
	a.recoil_rules = rules
	var first := a.simulate_tick(_cmd(true), _ctx(10), null)
	var _r := a.simulate_tick(_cmd(false), _ctx(11), null)
	var later := a.simulate_tick(_cmd(true), _ctx(10 + 64 * 3), null)
	_check(is_equal_approx(later.recoil.x, first.recoil.x) and is_equal_approx(later.recoil.y, first.recoil.y), "released long enough, the pattern starts over")
	_drop(a)

	var ctx := _ctx(1)
	var base := rules.posture(ctx)
	ctx.aiming = true
	var aimed := rules.posture(ctx)
	ctx.crouched = true
	_check(aimed < base and rules.posture(ctx) < aimed, "aim and crouch tighten it")
	ctx = _ctx(1)
	ctx.speed = 6.0
	var moving := rules.posture(ctx)
	ctx.airborne = true
	_check(moving > base and rules.posture(ctx) > moving, "moving and air widen it")

	rules.scale = 2.0
	var doubled := _burst(rules, 1, 10)
	_check(is_equal_approx(doubled[0].recoil.x, 1.0), "the master scale multiplies")
	rules.scale = 1.0
	rules.punch = 0.0
	var split := _burst(rules, 1, 10)
	_check(split[0].recoil == Vector2.ZERO and split[0].shots[0].direction != Vector3.FORWARD, "punch 0 leaves the view alone and offsets the bullet")
	var again := _burst(rules, 1, 10)
	_check(split[0].shots[0].direction.is_equal_approx(again[0].shots[0].direction), "the bullet offset repeats too")
	rules.punch = 1.0
	_check(_burst(rules, 1, 10)[0].shots[0].direction.is_equal_approx(Vector3.FORWARD), "punch 1 keeps the bullet on the view")

	var view := DotWeaponRecoil.new()
	for o: DotWeaponOutcome in run1:
		view.kick_outcome(o)
	var peak := view.offset().x
	_check(peak > 2.0, "the view climbs over a burst", str(peak))
	view.advance(1.0)
	_check(view.offset().x < peak * 0.1, "and settles on release", str(view.offset().x))

	_check(rules.set_cvar("sv_recoil_scale", "0.5") and is_equal_approx(rules.scale, 0.5), "a cvar sets a multiplier")
	_check(rules.set_cvar("sv_recoil_punch", "9") and is_equal_approx(rules.punch, 1.0), "and is clamped")
	_check(rules.set_cvar("sv_recoil", "0") and not rules.enabled and DotWeaponRecoilRules.of(null) == null, "sv_recoil switches it off")
	_done()


func _test_fire_modes() -> void:
	_section("fire modes")

	var cat := _catalogue()
	var rifle := cat.get_def(&"rifle")
	rifle.fire_modes = PackedStringArray(["auto", "semi", "burst"])
	rifle.burst_count = 3
	rifle.burst_interval_ticks = 2
	var a := _arsenal(cat)
	a.give(&"rifle")
	a.give(&"pistol")
	var seen: Array[int] = []
	a.fire_mode_changed.connect(func(_s: int, m: int) -> void: seen.append(m))

	_check(a.fire_mode() == DotWeaponDef.Fire.AUTO, "the first listed mode is the default")
	var auto_shots := _drive(a, 0, 60, true).size()
	_check(auto_shots == 10, "auto fires on every interval while held", str(auto_shots))

	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.SEMI, "cycling goes auto to semi")
	var semi_shots := _drive(a, 100, 60, true).size()
	_check(semi_shots == 1, "semi fires once per press however long it is held", str(semi_shots))

	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.BURST, "then semi to burst")
	var burst_shots := _drive(a, 200, 40, true)
	_check(burst_shots.size() == 3, "burst fires exactly three shots per press", str(burst_shots.size()))
	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.AUTO, "burst wraps back to auto")
	_check(seen == [DotWeaponDef.Fire.SEMI, DotWeaponDef.Fire.BURST, DotWeaponDef.Fire.AUTO], "fire_mode_changed announces each change", str(seen))

	_check(not a.set_fire_mode(DotWeaponDef.Fire.CHARGE), "a mode the gun does not list is refused")
	_check(a.fire_mode() == DotWeaponDef.Fire.AUTO, "and the mode is unchanged")

	# The button is a rising edge: held over many ticks it cycles once.
	var before := a.fire_mode()
	var prev: DotWeaponCommand = null
	for i in range(5):
		var c := DotWeaponCommand.new()
		c.set_button(DotWeaponCommand.BUTTON_FIRE_MODE, true)
		var _o := a.simulate_tick(c, _ctx(300 + i), prev)
		prev = c
	_check(a.fire_mode() != before and a.fire_mode() == DotWeaponDef.Fire.SEMI, "the fire-mode button cycles once per press")

	# A pistol without a list has no choice and refuses.
	_check(a.select(2, 400), "switch to the pistol")
	var _d := _drive(a, 401, 2, false)
	_check(a.fire_modes_available().size() == 1 and not a.cycle_fire_mode(), "a gun with one mode refuses to cycle")

	# Selection belongs to the weapon instance and survives a switch and a snapshot.
	var _s := a.select(1, 500)
	var snap := a.snapshot()
	var b := _arsenal(cat)
	var res := b.restore(snap)
	_check(res.ok and b.fire_mode() == DotWeaponDef.Fire.SEMI, "the selection survives a weapon switch and a snapshot")
	_drop(a)
	_drop(b)
	_done()


func _test_muzzle() -> void:
	_section("the muzzle flash bridge falls back without dot-fx or a display")

	var d := _rifle()
	_check(DotWeaponMuzzle.flash_name(d) == "" and DotWeaponMuzzle.flash_name(null) == "", "no profile size is an empty name")
	d.params[DotWeaponMuzzle.KEY] = "big"
	_check(DotWeaponMuzzle.flash_name(d) == "big", "the profile's size name is read")
	var host := Node3D.new()
	add_child(host)
	_check(not DotWeaponMuzzle.warm(host, "rifle", d), "warm builds nothing here (no dot-fx or headless)")
	_check(not DotWeaponMuzzle.warm(null, "rifle"), "warm with no host is false")
	_check(DotWeaponMuzzle.attach(host, "rifle", d) == null and host.get_child_count() == 0, "attach returns null and adds nothing here")
	_check(DotWeaponMuzzle.warm_done() and DotWeaponMuzzle.spare_count() == 0, "nothing warming, nothing waiting")
	host.queue_free()
	_done()
