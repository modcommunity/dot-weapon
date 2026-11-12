extends "selftest/harness.gd"

## Micro-benchmark of an idle hitscan carrier, the way a server's stand-in is ticked (spread rules on, crosshair_cone off,
## idle_posture bound to DotWeaponPlayerBridge.posture_for): microseconds per call of each piece.
## Run: godot --headless --path . res://examples/idle_bench.tscn -- --rounds=20000

class FakePlayer extends Node3D:
	var player_key := "bot"
	var ctrl: Node = null

	func component(type_name: StringName) -> Object:
		match String(type_name):
			"DotPlayerController", "DotFpsController":
				return ctrl
			_:
				return null


class FakeController extends Node:
	var velocity := Vector3.ZERO
	var grounded := true
	var crouch := 0.0

	func motion() -> Dictionary:
		return {
			"speed": Vector2(velocity.x, velocity.z).length(),
			"vertical": velocity.y,
			"on_floor": grounded,
			"crouched": crouch > 0.5,
			"sliding": false,
			"sprinting": false,
			"sprint_blocks_aim": true,
			"sprint_blocks_fire": false,
			"sprint_shot_follows_barrel": false,
			"facing": 0.0,
		}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _time(label: String, rounds: int, work: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(rounds):
		work.call()
	print("BENCH %-34s %7.2f us" % [label, float(Time.get_ticks_usec() - t0) / rounds])


func _run() -> void:
	var rounds := 20000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			rounds = int(arg.substr(9))

	var player := FakePlayer.new()
	player.ctrl = FakeController.new()
	add_child(player)
	player.add_child(player.ctrl)

	for rules_on in [true, false]:
		var cat := _catalogue()
		var a := _arsenal(cat)
		a.give(&"rifle")
		a.crosshair_cone = false
		if rules_on:
			a.spread_rules = DotWeaponSpreadRules.new()
			a.spread_rules.enabled = true
		a.idle_posture = DotWeaponPlayerBridge.posture_for.bind(player)
		var cmd := DotWeaponCommand.new()
		print("-- spread rules %s" % ("on" if rules_on else "off"))
		_time("is_idle_for", rounds, func() -> void: a.is_idle_for(cmd, null))
		_time("posture_for (provider)", rounds, func() -> void: DotWeaponPlayerBridge.posture_for(player, 5))
		var beh := a.current().behaviour
		var ctx := DotWeaponPlayerBridge.posture_for(player, 5)
		_time("behaviour.tick(posture ctx)", rounds, func() -> void: beh.tick(ctx))
		_time("behaviour.tick(null)", rounds, func() -> void: beh.tick(null))
		_time("still_for (the skip's question)", rounds, func() -> void: DotWeaponPlayerBridge.still_for(player))
		for i in range(3):
			a.idle_tick()
		a.idle_rest_skip = false
		_time("is_idle_for + idle_tick, no skip", rounds, func() -> void:
			if a.is_idle_for(cmd, null):
				a.idle_tick())
		a.idle_rest_skip = true
		_time("is_idle_for + idle_tick, rest skip", rounds, func() -> void:
			if a.is_idle_for(cmd, null):
				a.idle_tick())
		# A moving carrier (a bot running about, never firing): the speed changes every tick, so neither the rest skip
		# nor the steady skip holds and every idle tick computes the cone.
		var step := [0]
		_time("is_idle_for + idle_tick, moving", rounds, func() -> void:
			step[0] += 1
			player.ctrl.velocity = Vector3(3.0 + float(step[0] % 50) * 0.05, 0.0, 0.0)
			if a.is_idle_for(cmd, null):
				a.idle_tick())
		var b: DotWeaponBallistics = a.current().def.tuning
		var moving := DotWeaponPlayerBridge.posture_for(player, 5)
		_time("behaviour.tick(moving ctx)", rounds, func() -> void:
			step[0] += 1
			moving.speed = 3.0 + float(step[0] % 50) * 0.05
			beh.tick(moving))
		_time("  _spread_with (moving)", rounds, func() -> void: beh._spread_with(b, moving, beh._rules()))
		_time("  ballistics.accuracy(spread_hip)", rounds, func() -> void: b.accuracy("spread_hip", "rifle"))
		_time("  _class_ticks_of(settle)", rounds, func() -> void: beh._class_ticks_of(b, b.settle_ticks, "settle"))
		_time("  _settle_ticks_of", rounds, func() -> void: beh._settle_ticks_of(b))
		player.ctrl.velocity = Vector3.ZERO
		_time("(empty callable call)", rounds, func() -> void: pass)

	get_tree().quit(0)
