extends "sections_accuracy.gd"

## The rest skip of an idle hitscan tick (DotWeaponArsenal.idle_still, DotWeaponBehaviour.rest_tick) must change nothing: the same random
## command and posture stream through an arsenal with it and one without, full state compared (the first also runs DotWeaponHitscan's steady
## skip, the second not); the last three modes keep the cone on, as FC does, and add flinches, in-place tuning edits and restored snapshots.

const _MODES := ["plain", "rules", "rules_cone_off", "rules_edited", "explicit_still", "rules_hurt", "rules_tuning", "rules_restore"]
const _CONE_MODES := ["rules", "rules_hurt", "rules_tuning", "rules_restore"]


## Eight postures a carrier moves through; index 0 is the settled one.
func _posture_data(kind: int) -> Dictionary:
	var m := {"speed": 0.0, "on_floor": true, "crouched": false, "sliding": false, "wall_running": false, "sprinting": false}
	match kind:
		1: m["speed"] = 2.0
		2: m["speed"] = 6.0
		3:
			m["speed"] = 7.0
			m["sprinting"] = true
		4: m["crouched"] = true
		5: m["on_floor"] = false
		6:
			m["speed"] = 5.0
			m["sliding"] = true
		7:
			m["speed"] = 3.0
			m["wall_running"] = true
		8: m["speed"] = 0.02
	return m


func _rest_ctx(player: Node, tick: int) -> DotWeaponContext:
	var c := DotWeaponPlayerBridge.posture_for(player, tick)
	c.entity = 1
	c.origin = Vector3(0.0, 1.6, 0.0)
	c.direction = Vector3.FORWARD
	return c


func _test_idle_rest_skip() -> void:
	_section("an idle tick at rest is skipped without changing anything")

	var skipped_total := 0
	var steady_total := 0
	var all_same := true
	var spread_same := true
	var detail := ""

	for mode: String in _MODES:
		var res := _rest_stream(mode)
		skipped_total += int(res["skipped"])
		steady_total += int(res["steady"])
		if not res["same"]:
			all_same = false
		if not res["spread_same"]:
			spread_same = false
		if res["detail"] != "":
			detail = res["detail"]
		if not all_same:
			break

	_check(all_same, "outcomes, snapshots and behaviour state agree on every tick of every stream", detail)
	_check(spread_same, "and so does the crosshair cone", detail)
	_check(skipped_total > 1000, "the skip took over a thousand ticks in all", str(skipped_total))
	_check(steady_total > 1000, "the steady skip took over a thousand ticks in all", str(steady_total))

	# A settled posture is the only one that skips: a walking carrier is asked about and refused.
	var cat2 := _catalogue()
	var walker := _arsenal(cat2)
	walker.give(&"rifle")
	var asked := [0]
	walker.idle_posture = func() -> DotWeaponContext: return _ctx(0)
	walker.idle_still = func() -> bool:
		asked[0] += 1
		return false
	walker.idle_tick()
	walker.idle_tick()
	walker.idle_tick()
	_check(asked[0] == 3, "the carrier is asked about only while the weapon is at rest, and a no is a normal tick", str(asked[0]))
	_drop(walker)

	_done()


## The two arsenals of one [param mode] (index 0 skips, index 1 does not), each with its carrier and spread rules.
func _rest_pair(mode: String, cat: DotWeaponCatalogue) -> Dictionary:
	var st := {"arsenals": [_arsenal(cat), _arsenal(cat)], "rules": [], "players": [], "controllers": [], "hurt": [-1], "now": [0]}
	var hurt: Array = st["hurt"]
	var now: Array = st["now"]
	for a: DotWeaponArsenal in st["arsenals"]:
		a.give(&"rifle")
		a.give(&"pistol")
		a.give(&"bow")
		a.give(&"knife")
		var player := StubPlayer.new()
		var controller := StubController.new()
		player.stub_controller = controller
		add_child(player)
		add_child(controller)
		st["players"].append(player)
		st["controllers"].append(controller)
		if mode != "plain":
			var r := DotWeaponSpreadRules.new()
			r.enabled = true
			r.recovery = 40.0
			a.spread_rules = r
			st["rules"].append(r)
			a.crosshair_cone = mode in _CONE_MODES
		if mode == "rules_hurt":
			var p := player
			a.idle_posture = func() -> DotWeaponContext:
				var c := DotWeaponPlayerBridge.posture_for(p, now[0])
				c.hurt_tick = hurt[0]
				return c
			a.idle_still = func() -> bool: return DotWeaponPlayerBridge.still_for(p) and (hurt[0] < 0 or now[0] - hurt[0] > 200)
		elif mode == "explicit_still":
			var p := player
			a.idle_posture = func() -> DotWeaponContext: return DotWeaponPlayerBridge.posture_for(p)
			a.idle_still = func() -> bool: return DotWeaponPlayerBridge.still_for(p)
		else:
			a.idle_posture = DotWeaponPlayerBridge.posture_for.bind(player)
	return st


## One random stream of [param mode] through both arsenals of [method _rest_pair], compared tick by tick.
func _rest_stream(mode: String) -> Dictionary:
	var cat := _catalogue()
	(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom = 2.0
	(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom_recovery = 0.2
	var st := _rest_pair(mode, cat)
	var skip: DotWeaponArsenal = st["arsenals"][0]
	var plain: DotWeaponArsenal = st["arsenals"][1]
	plain.idle_rest_skip = false
	if mode != "explicit_still":
		_check(skip.idle_still.is_valid() and plain.idle_still.is_valid(), "%s: binding the bridge's posture_for derives idle_still" % mode)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + _MODES.find(mode)
	var roll := {"posture": 0, "posture_left": 0, "command_left": 0, "buttons": 0, "slot": 0}
	var previous: DotWeaponCommand = null
	var res := {"skipped": 0, "steady": 0, "same": true, "spread_same": true, "detail": ""}
	st["saved"] = [{}, {}]
	var rifle := cat.get_def(&"rifle").tuning as DotWeaponBallistics
	if mode in ["rules_hurt", "rules_tuning", "rules_restore"]:
		rifle.spread_flinch = 1.5
		rifle.spread = 1.0
		rifle.spread_moving = 2.0
		rifle.spread_hip = 0.5
	var held := [rifle.spread]

	for tick in range(2400):
		_rest_roll(rng, roll)
		_rest_edit(mode, tick, rng, st, rifle, held)
		st["now"][0] = tick
		var rows := _rest_pair_tick(mode, tick, st, roll, previous, res)
		var results: Array = rows[0]
		var states: Array = rows[1]
		var spreads: Array = rows[2]

		DotWeaponHitscan.steady_skip = true
		previous = DotWeaponCommand.new()
		previous.buttons = roll["buttons"]
		previous.slot = roll["slot"]

		if results[0] != results[1] or states[0] != states[1]:
			res["same"] = false
			res["detail"] = "%s tick %d posture %d: %s vs %s" % [mode, tick, roll["posture"], results, states.map(func(s: String) -> int: return s.hash())]
			break
		if mode != "rules_edited" and not is_equal_approx(spreads[0], spreads[1]):
			res["spread_same"] = false
			res["detail"] = "%s tick %d spread %s" % [mode, tick, spreads]

	_check(int(res["skipped"]) > 300 or mode in _CONE_MODES, "%s: the skip ran for much of the stream" % mode, str(res["skipped"]))
	if mode in _CONE_MODES:
		_check(int(res["steady"]) > 300, "%s: the steady skip ran for much of the stream" % mode, str(res["steady"]))
	for node in st["arsenals"] + st["players"] + st["controllers"]:
		_drop(node)
	return res


## The next posture and command of a stream, drawn from [param rng] into [param roll] when the last ones run out.
func _rest_roll(rng: RandomNumberGenerator, roll: Dictionary) -> void:
	if roll["posture_left"] <= 0:
		roll["posture"] = 0 if rng.randf() < 0.55 else rng.randi_range(1, 8)
		roll["posture_left"] = rng.randi_range(1, 160) if roll["posture"] == 0 else rng.randi_range(1, 30)
	roll["posture_left"] -= 1
	if roll["command_left"] <= 0:
		roll["buttons"] = 0
		roll["slot"] = 0
		var r := rng.randf()
		if r < 0.12:
			roll["buttons"] = DotWeaponCommand.BUTTON_ATTACK
		elif r < 0.15:
			roll["buttons"] = DotWeaponCommand.BUTTON_RELOAD
		elif r < 0.19:
			roll["slot"] = rng.randi_range(1, 4)
		roll["command_left"] = rng.randi_range(1, 12) if roll["buttons"] != 0 or roll["slot"] != 0 else rng.randi_range(5, 200)
	roll["command_left"] -= 1


## The edits a [param mode] makes mid-stream: spread rules, flinches, and tuning swapped or changed in place.
func _rest_edit(mode: String, tick: int, rng: RandomNumberGenerator, st: Dictionary, rifle: DotWeaponBallistics, held: Array) -> void:
	if mode == "rules_edited" and tick % 400 == 399:
		var field := rng.randi_range(0, 2)
		var value := rng.randf_range(0.7, 1.4)
		for r: DotWeaponSpreadRules in st["rules"]:
			match field:
				0: r.mult_stand = value
				1: r.mult_hip = value
				2: r.walk_speed = 0.0 if value > 1.2 else 0.5
	if mode == "rules_hurt" and rng.randf() < 0.004:
		st["hurt"][0] = tick
	if mode == "rules_tuning":
		# A rig swaps the shared tuning for one aimed tick and puts it back; now and then an edit stays.
		if tick % 97 == 40:
			held[0] = rifle.spread
			rifle.spread = held[0] * 1.5
		elif tick % 97 == 41:
			rifle.spread = held[0]
		elif tick % 300 == 299:
			match rng.randi_range(0, 3):
				0: rifle.spread = rng.randf_range(0.5, 2.0)
				1: rifle.spread_moving = rng.randf_range(0.5, 4.0)
				2: rifle.bloom_max = rng.randf_range(1.0, 6.0)
				3: rifle.spread_hip = rng.randf_range(0.0, 2.0)


## One tick of both arsenals; returns [results, states, spreads] and counts skipped and steady ticks into [param res].
func _rest_pair_tick(mode: String, tick: int, st: Dictionary, roll: Dictionary, previous: DotWeaponCommand, res: Dictionary) -> Array:
	var results: Array = []
	var states: Array = []
	var spreads: Array = []
	var saved: Array = st["saved"]
	for i in range(2):
		var a: DotWeaponArsenal = st["arsenals"][i]
		DotWeaponHitscan.steady_skip = i == 0
		if mode == "rules_restore":
			if tick % 211 == 100:
				saved[i] = a.snapshot()
			elif tick % 211 == 160 and not (saved[i] as Dictionary).is_empty():
				a.restore(saved[i])
		(st["controllers"][i] as StubController).motion_data = _posture_data(roll["posture"])
		var cmd := DotWeaponCommand.new()
		cmd.buttons = roll["buttons"]
		cmd.slot = roll["slot"]
		var out: DotWeaponOutcome
		var was_steady: bool = a.current() != null and a.current().behaviour.get("_steady") == true
		var hit := _rest_ctx(st["players"][i], tick)
		hit.hurt_tick = st["hurt"][0]
		if a.is_idle_for(cmd, previous):
			out = a.idle_tick()
			if i == 0 and a.current().behaviour.get("_shown_stale") == true:
				res["skipped"] += 1
		else:
			out = a.simulate_tick(cmd, hit, previous)
		if i == 0 and was_steady and a.current().behaviour.get("_steady") == true:
			res["steady"] += 1
		results.append("%s|%s|%s" % [out.used, out.kind, out.refusal])
		states.append(var_to_str(a.snapshot()) + var_to_str(a.current().behaviour.state))
		spreads.append(a.spread_now())
	return [results, states, spreads]


func _test_reload_shots() -> void:
	_section("the reload review helper spreads fractions and lays a sheet out")
	var shots := preload("../../addons/dot_weapon/view/dot_weapon_reload_shots.gd")
	var f: PackedFloat64Array = shots.fractions(3)
	_check(f.size() == 3 and is_equal_approx(f[0], 0.25) and is_equal_approx(f[2], 0.75), "three fractions are a quarter apart, none at an end", str(f))
	_check(shots.fractions(0).is_empty(), "no frames, no fractions")
	var tiles: Array[Image] = []
	for i in 5:
		tiles.append(Image.create_empty(64, 36, false, Image.FORMAT_RGBA8))
	var sheet: Image = shots.sheet(tiles, 4, Vector2i(32, 18))
	_check(sheet != null and sheet.get_size() == Vector2i(128, 36), "five tiles at four across make two rows", str(sheet.get_size()) if sheet != null else "null")
	_check(shots.sheet([] as Array[Image]) == null, "no tiles, no sheet")
	_done()
