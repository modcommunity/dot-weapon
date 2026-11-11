extends "sections_accuracy.gd"

## The rest skip of an idle hitscan tick (DotWeaponArsenal.idle_still, DotWeaponBehaviour.rest_tick) must change nothing:
## the same random stream of commands and postures through an arsenal with the skip and one without, full state compared.
## The first arsenal also runs with the steady skip of DotWeaponHitscan on and the second with it off, so the same streams
## prove that one too; the last three modes keep the cone on (as the arena does, where the rest skip never runs) and add
## flinches, in-place tuning edits (the aimed-tick swap of a weapon rig) and restored snapshots.

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
		var cat := _catalogue()
		(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom = 2.0
		(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom_recovery = 0.2
		var skip := _arsenal(cat)
		var plain := _arsenal(cat)
		var rules: Array = []
		var players: Array = []
		var controllers: Array = []
		var hurt := [-1]
		var now := [0]

		for a: DotWeaponArsenal in [skip, plain]:
			a.give(&"rifle")
			a.give(&"pistol")
			a.give(&"bow")
			a.give(&"knife")
			var player := StubPlayer.new()
			var controller := StubController.new()
			player.stub_controller = controller
			add_child(player)
			add_child(controller)
			players.append(player)
			controllers.append(controller)
			if mode != "plain":
				var r := DotWeaponSpreadRules.new()
				r.enabled = true
				r.recovery = 40.0
				a.spread_rules = r
				rules.append(r)
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

		plain.idle_rest_skip = false
		if mode != "explicit_still":
			_check(skip.idle_still.is_valid() and plain.idle_still.is_valid(), "%s: binding the bridge's posture_for derives idle_still" % mode)

		var rng := RandomNumberGenerator.new()
		rng.seed = 5150 + _MODES.find(mode)
		var posture := 0
		var posture_left := 0
		var command_left := 0
		var buttons := 0
		var slot := 0
		var previous: DotWeaponCommand = null
		var skipped := 0
		var steady := 0
		var saved: Array = [{}, {}]
		var rifle := cat.get_def(&"rifle").tuning as DotWeaponBallistics
		if mode in ["rules_hurt", "rules_tuning", "rules_restore"]:
			rifle.spread_flinch = 1.5
			rifle.spread = 1.0
			rifle.spread_moving = 2.0
			rifle.spread_hip = 0.5
		var held_spread := rifle.spread

		for tick in range(2400):
			if posture_left <= 0:
				posture = 0 if rng.randf() < 0.55 else rng.randi_range(1, 8)
				posture_left = rng.randi_range(1, 160) if posture == 0 else rng.randi_range(1, 30)
			posture_left -= 1
			if command_left <= 0:
				buttons = 0
				slot = 0
				var roll := rng.randf()
				if roll < 0.12:
					buttons = DotWeaponCommand.BUTTON_ATTACK
				elif roll < 0.15:
					buttons = DotWeaponCommand.BUTTON_RELOAD
				elif roll < 0.19:
					slot = rng.randi_range(1, 4)
				command_left = rng.randi_range(1, 12) if buttons != 0 or slot != 0 else rng.randi_range(5, 200)
			command_left -= 1

			if mode == "rules_edited" and tick % 400 == 399:
				var field := rng.randi_range(0, 2)
				var value := rng.randf_range(0.7, 1.4)
				for r: DotWeaponSpreadRules in rules:
					match field:
						0: r.mult_stand = value
						1: r.mult_hip = value
						2: r.walk_speed = 0.0 if value > 1.2 else 0.5
			if mode == "rules_hurt" and rng.randf() < 0.004:
				hurt[0] = tick
			if mode == "rules_tuning":
				# A rig swaps the shared tuning for one aimed tick and puts it back; now and then an edit stays.
				if tick % 97 == 40:
					held_spread = rifle.spread
					rifle.spread = held_spread * 1.5
				elif tick % 97 == 41:
					rifle.spread = held_spread
				elif tick % 300 == 299:
					match rng.randi_range(0, 3):
						0: rifle.spread = rng.randf_range(0.5, 2.0)
						1: rifle.spread_moving = rng.randf_range(0.5, 4.0)
						2: rifle.bloom_max = rng.randf_range(1.0, 6.0)
						3: rifle.spread_hip = rng.randf_range(0.0, 2.0)
			now[0] = tick

			var results: Array = []
			var states: Array = []
			var spreads: Array = []
			for i in range(2):
				var a: DotWeaponArsenal = skip if i == 0 else plain
				DotWeaponHitscan.steady_skip = i == 0
				if mode == "rules_restore":
					if tick % 211 == 100:
						saved[i] = a.snapshot()
					elif tick % 211 == 160 and not (saved[i] as Dictionary).is_empty():
						a.restore(saved[i])
				(controllers[i] as StubController).motion_data = _posture_data(posture)
				var cmd := DotWeaponCommand.new()
				cmd.buttons = buttons
				cmd.slot = slot
				var out: DotWeaponOutcome
				var was_steady: bool = a.current() != null and a.current().behaviour.get("_steady") == true
				var hit := _rest_ctx(players[i], tick)
				hit.hurt_tick = hurt[0]
				if a.is_idle_for(cmd, previous):
					out = a.idle_tick()
					if i == 0 and a.current().behaviour.get("_shown_stale") == true:
						skipped += 1
				else:
					out = a.simulate_tick(cmd, hit, previous)
				if i == 0 and was_steady and a.current().behaviour.get("_steady") == true:
					steady += 1
				results.append("%s|%s|%s" % [out.used, out.kind, out.refusal])
				states.append(var_to_str(a.snapshot()) + var_to_str(a.current().behaviour.state))
				spreads.append(a.spread_now())

			DotWeaponHitscan.steady_skip = true
			previous = DotWeaponCommand.new()
			previous.buttons = buttons
			previous.slot = slot

			if results[0] != results[1] or states[0] != states[1]:
				all_same = false
				detail = "%s tick %d posture %d: %s vs %s" % [mode, tick, posture, results, states.map(func(s: String) -> int: return s.hash())]
				break
			if mode != "rules_edited" and not is_equal_approx(spreads[0], spreads[1]):
				spread_same = false
				detail = "%s tick %d spread %s" % [mode, tick, spreads]

		skipped_total += skipped
		steady_total += steady
		_check(skipped > 300 or mode in _CONE_MODES, "%s: the skip ran for much of the stream" % mode, str(skipped))
		if mode in _CONE_MODES:
			_check(steady > 300, "%s: the steady skip ran for much of the stream" % mode, str(steady))
		for node in [skip, plain] + players + controllers:
			_drop(node)
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
