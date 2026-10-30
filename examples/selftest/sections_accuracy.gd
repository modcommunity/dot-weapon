extends "sections_ballistics.gd"

## The per-weapon accuracy model: class presets, posture ladder, bloom that builds under sustained fire,
## settling, flinch, the global scales, profile overrides, recoil posture and client/server agreement.


func _heavy() -> DotWeaponDef:
	var d := _rifle()
	d.id = &"lmg_test"
	d.use_interval_ticks = 5
	d.magazine = 200
	var b := DotWeaponBallistics.new()
	b.damage = 20.0
	b.spread = 0.9
	b.spread_moving = 3.8
	b.spread_airborne = 6.5
	b.spread_crouched = 0.6
	b.bloom = 0.18
	b.bloom_max = 3.6
	b.bloom_recovery = 6.0 / 64.0
	b.recoil_pitch = 0.3
	b.recoil_yaw = 0.2
	d.tuning = b
	d.authored_tick_rate = 64
	return d


func _heavy_arsenal() -> DotWeaponArsenal:
	var c := DotWeaponCatalogue.new()
	c.add(_heavy())
	var a := _arsenal(c)
	a.give(&"lmg_test")
	return a


func _posture(key: String, tick: int) -> DotWeaponContext:
	var c := _ctx(tick)
	c.speed = {"walk": 2.0, "run": 6.0, "sprint": 7.5}.get(key, 0.0)
	c.sprinting = key == "sprint"
	c.airborne = key == "air"
	c.crouched = key.begins_with("crouch")
	c.wall_running = key == "wallrun"
	if c.wall_running:
		c.speed = 6.0
	return c


## The cone one tick in [param key] leaves, from a fresh gun.
func _cone(key: String, aim: bool = false) -> float:
	var a := _heavy_arsenal()
	var cmd := _cmd(false)
	cmd.set_button(DotWeaponCommand.BUTTON_AIM, aim)
	var _o := a.simulate_tick(cmd, _posture(key, 10), null)
	var got := a.spread_now()
	_drop(a)
	return got


func _test_accuracy_classes() -> void:
	_section("accuracy classes and the posture ladder")
	var R := DotWeaponAccuracyClass
	_check(R.resolve("", [], &"aw_lmg") == "lmg" and R.resolve("", [], &"machine_pistol") == "smg", "classes from id words, smg before pistol")
	_check(R.resolve("", [&"scoped"], &"rifle") == "sniper" and R.resolve("none", [], &"lmg") == "", "a tag beats the id; an unknown explicit class is neutral")
	_check(R.preset("lmg", "spread_aim") < 1.0 and R.preset("lmg", "recoil_crouch") < R.preset("rifle", "recoil_crouch"), "an lmg is tighter aimed and settles harder crouched than a rifle")
	var got := {}
	for key: String in ["still", "walk", "run", "sprint", "air", "crouch", "wallrun"]:
		got[key] = _cone(key)
	got["crouch_aim"] = _cone("crouch", true)
	got["aim"] = _cone("still", true)
	_check(got["crouch_aim"] < got["crouch"] and got["crouch"] < got["still"], "crouched and aimed < crouched < still", str(got))
	_check(got["aim"] < got["still"] and got["still"] < got["walk"] and got["walk"] < got["run"], "aimed < still < walk < run", str(got))
	_check(got["run"] < got["sprint"] and got["run"] < got["air"] and got["run"] < got["wallrun"], "run < sprint, air and wall-run", str(got))
	_check(got["still"] > 0.9 + 0.3, "an lmg at the hip is loose standing still (hip spread added)", str(got["still"]))
	_check(got["crouch_aim"] < 0.5, "and tight crouched and aimed", str(got["crouch_aim"]))
	_done()


## Fires [param shots] at full auto in [param key]; returns every shot's cone.
func _burst_cones(key: String, shots: int, aim: bool = false) -> Array:
	var a := _heavy_arsenal()
	var cones: Array = []
	var previous: DotWeaponCommand = null
	var tick := 10
	while cones.size() < shots and tick < 2000:
		var cmd := _cmd(true)
		cmd.set_button(DotWeaponCommand.BUTTON_AIM, aim)
		var out := a.simulate_tick(cmd, _posture(key, tick), previous)
		if out.used:
			cones.append(out.shots[0].spread)
		previous = cmd
		tick += 1
	_drop(a)
	return cones


func _test_accuracy_bloom() -> void:
	_section("bloom builds under sustained fire and recovers")
	var cones := _burst_cones("still", 25)
	_check(cones.size() == 25 and float(cones[24]) > float(cones[0]) + 2.5, "25 shots of an lmg open the cone by its bloom (recovery waits for the trigger)", "%s -> %s" % [cones[0], cones[24]])
	var crouched := _burst_cones("crouch", 25)
	_check(float(crouched[24]) < float(cones[24]) * 0.6, "the same burst crouched stays far tighter", "%s vs %s" % [crouched[24], cones[24]])
	var aimed := _burst_cones("crouch", 25, true)
	_check(float(aimed[24]) < float(crouched[24]), "and tighter again aimed")

	var a := _heavy_arsenal()
	var _shots := _drive(a, 10, 60, true)
	var opened := a.spread_now()
	var _rest := _drive(a, 70, 64 * 3, false)
	_check(opened > 3.0 and absf(a.spread_now() - _cone("still")) < 0.001, "three seconds off the trigger recover it to the still cone", "%s -> %s" % [opened, a.spread_now()])
	_drop(a)
	_done()


func _test_accuracy_settle_flinch() -> void:
	_section("settling after a run, flinch on a hit")
	var a := _heavy_arsenal()
	for i in range(20):
		var _r := a.simulate_tick(_cmd(false), _posture("run", 10 + i), null)
	var _s := a.simulate_tick(_cmd(false), _posture("still", 30), null)
	var just_stopped := a.spread_now()
	for i in range(64):
		var _t := a.simulate_tick(_cmd(false), _posture("still", 31 + i), null)
	var settled := a.spread_now()
	_check(just_stopped > settled + 1.0, "the moving cone lingers on the first still tick", "%s vs %s" % [just_stopped, settled])
	_check(absf(settled - _cone("still")) < 0.001, "and settles to the still cone within a second")
	var hit := _posture("still", 100)
	hit.hurt_tick = 100
	var _h := a.simulate_tick(_cmd(false), hit, null)
	var flinched := a.spread_now()
	var later := _posture("still", 140)
	later.hurt_tick = 100
	var _l := a.simulate_tick(_cmd(false), later, null)
	_check(flinched > settled + 0.5 and absf(a.spread_now() - settled) < 0.001, "a hit flinches the cone and it passes", "%s %s" % [flinched, a.spread_now()])
	_drop(a)
	_done()


func _test_accuracy_scale_profile() -> void:
	_section("sv_spread_scale, sv_recoil_scale and per-weapon profile values")
	var base := _cone("still")
	var a := _heavy_arsenal()
	var rules := DotWeaponSpreadRules.new()
	_check(rules.set_cvar("sv_spread_scale", "0") and rules.scale == 0.0, "sv_spread_scale is a cvar")
	a.spread_rules = rules
	var out := a.simulate_tick(_cmd(true), _posture("run", 10), null)
	_check(out.used and out.shots[0].spread == 0.0 and out.shots[0].pellets[0] == Vector3.FORWARD, "0 fires dead straight, even running")
	var _r := rules.set_cvar("sv_spread_scale", "2")
	for i in range(160):
		var _o := a.simulate_tick(_cmd(false), _posture("still", 400 + i), null)
	_check(absf(a.spread_now() - 2.0 * base) < 0.01, "2 doubles the cone", "%s vs %s" % [a.spread_now(), base])
	_drop(a)

	var b := _heavy().tuning as DotWeaponBallistics
	_check(b.accuracy("spread_aim", "lmg") == DotWeaponAccuracyClass.preset("lmg", "spread_aim"), "-1 takes the class preset")
	b.spread_aim = 0.2
	_check(is_equal_approx(b.accuracy("spread_aim", "lmg"), 0.2), "a weapon's own value beats the class")

	var root := OS.get_user_data_dir().path_join("accuracy_profiles")
	DirAccess.make_dir_recursive_absolute(root.path_join("base/addons/acc/weapon"))
	DirAccess.make_dir_recursive_absolute(root.path_join("server/addons/acc/weapon"))
	_profile_write(root.path_join("base/addons/acc/weapon/lmg_test.yml"), "extra:\n  tuning:\n    spread_aim: 0.5\n    bloom_crouch: 0.3\n    accuracy_class: \"sniper\"\n")
	_profile_write(root.path_join("server/addons/acc/weapon/lmg_test.yml"), "extra:\n  tuning:\n    spread_aim: 0.25\n")
	var def := _heavy()
	var defs: Array[DotWeaponDef] = [def]
	var set := DotWeaponProfiles.overlay_set("acc", "", "", PackedStringArray([root.path_join("base"), root.path_join("server")]))
	var errors := DotWeaponProfiles.tune(defs, set)
	var t := def.tuning as DotWeaponBallistics
	_check(errors.is_empty() and is_equal_approx(t.bloom_crouch, 0.3) and t.accuracy_class == "sniper", "the weapon profile sets accuracy fields and the class")
	_check(is_equal_approx(t.spread_aim, 0.25), "the server's profile overrides the shipped one", str(t.spread_aim))
	_check(DotWeaponProfiles.to_yaml(def, "Acc").contains("spread_aim: 0.25"), "and the exporter writes them")
	set.clear_cache()

	var rr := DotWeaponRecoilRules.new()
	rr.enabled = true
	_check(rr.set_cvar("sv_recoil_scale", "0"), "sv_recoil_scale is a cvar")
	var ra := _heavy_arsenal()
	ra.recoil_rules = rr
	var kicked := ra.simulate_tick(_cmd(true), _posture("still", 10), null)
	_check(kicked.used and kicked.recoil == Vector2.ZERO, "0 takes the kick away")
	_drop(ra)
	_done()


## The first kick of a burst in [param key].
func _kick(key: String, aim: bool, rr: DotWeaponRecoilRules) -> Vector2:
	var a := _heavy_arsenal()
	a.recoil_rules = rr
	var cmd := _cmd(true)
	cmd.set_button(DotWeaponCommand.BUTTON_AIM, aim)
	var out := a.simulate_tick(cmd, _posture(key, 10), null)
	_drop(a)
	return out.recoil


func _test_accuracy_recoil() -> void:
	_section("recoil per weapon posture and camera share")
	for on in [false, true]:
		var rr := DotWeaponRecoilRules.new()
		rr.enabled = on
		var still := _kick("still", false, rr).x
		var tag := " (patterns on)" if on else " (flat kick)"
		_check(_kick("crouch", false, rr).x < still * 0.7, "crouched kicks less" + tag, "%s vs %s" % [_kick("crouch", false, rr).x, still])
		_check(_kick("still", true, rr).x < still, "aimed kicks less" + tag)
		_check(_kick("run", false, rr).x > still and _kick("air", false, rr).x > still, "moving and airborne kick more" + tag)
	var rr2 := DotWeaponRecoilRules.new()
	rr2.enabled = true
	var a := _heavy_arsenal()
	a.recoil_rules = rr2
	(a.current().def.tuning as DotWeaponBallistics).recoil_camera = 0.0
	var out := a.simulate_tick(_cmd(true), _posture("still", 10), null)
	_check(out.used and out.recoil == Vector2.ZERO, "recoil_camera 0 keeps the camera still (the kick goes to the bullet)")
	_drop(a)
	_done()


func _test_accuracy_prediction() -> void:
	_section("server and predicted client agree shot for shot")
	var server := _heavy_arsenal()
	var client := _heavy_arsenal()
	client.authority = false
	var keys := ["still", "run", "run", "air", "crouch", "still", "walk", "sprint"]
	var previous: DotWeaponCommand = null
	var same := true
	var first := ""
	var cones := 0
	for i in range(400):
		var key: String = keys[(i / 20) % keys.size()]
		var cmd := _cmd(i % 40 < 30)
		cmd.set_button(DotWeaponCommand.BUTTON_AIM, i % 50 > 35)
		var s := server.simulate_tick(cmd, _posture(key, 10 + i), previous)
		var c := client.simulate_tick(cmd, _posture(key, 10 + i), previous)
		previous = cmd
		if (server.spread_now() != client.spread_now() or s.used != c.used) and same:
			same = false
			first = "tick %d %s: %s/%s used %s/%s" % [i, key, server.spread_now(), client.spread_now(), s.used, c.used]
		if s.used and c.used:
			cones += 1
			if (s.shots[0].spread != c.shots[0].spread or s.shots[0].pellets != c.shots[0].pellets) and same:
				same = false
				first = "tick %d shot %s/%s" % [i, s.shots[0].spread, c.shots[0].spread]
	_check(same and cones > 50, "every cone, crosshair and pellet matches over %d shots" % cones, first)
	_drop(server)
	_drop(client)
	_done()


func _test_accuracy_distribution() -> void:
	_section("the crosshair cone is the shots' real spread")
	var cat := DotWeaponCatalogue.new()
	var long_mag := _heavy()
	long_mag.magazine = 1000
	cat.add(long_mag)
	var a := _arsenal(cat)
	a.give(&"lmg_test")
	var cones := []
	var widest := 0.0
	var inside_half := 0
	var n := 0
	for i in range(600):
		var ctx := _posture("run", 10 + i * 64)
		var _w := a.simulate_tick(_cmd(false), ctx, null)
		var shown := a.spread_now()
		var out := a.simulate_tick(_cmd(true), _posture("run", 10 + i * 64), null)
		if not out.used:
			continue
		var shot: DotShot = out.shots[0]
		cones.append(absf(shot.spread - shown))
		var angle := rad_to_deg(shot.pellets[0].angle_to(shot.direction))
		widest = maxf(widest, angle / shown)
		if angle <= shown * 0.5:
			inside_half += 1
		n += 1
	var drift := 0.0
	for d: float in cones:
		drift = maxf(drift, d)
	_check(n == 600 and drift < 0.0001, "the shot fires the cone the crosshair showed", "%d shots, drift %s" % [n, drift])
	_check(widest <= 1.0001 and widest > 0.97, "no pellet leaves the drawn cone, and the edge is reached", str(widest))
	var share := float(inside_half) / float(n)
	_check(share > 0.18 and share < 0.32, "a quarter land inside half the radius (uniform over the disc)", str(share))
	_drop(a)
	_done()
