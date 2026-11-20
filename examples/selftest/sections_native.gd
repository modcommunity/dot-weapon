extends "sections_knives.gd"

## DotWeaponHitscan.native_tick: a context tick through GameSpice Sim's DotSimWeaponSpread must leave what the GDScript tick
## leaves, bit for bit. Random weapons tick twice, once each way, on shared tuning, rules and arsenal objects edited
## mid-run (each edit must reach the cached native rows); then the rest streams run with the native tick on one arsenal.
## Without GameSpice Sim loaded every check passes as a skip, so the count stays fixed.

const _NATIVE_CASES := 200
const _NATIVE_TICKS := 160


class NativeArsenal:
	extends RefCounted
	var spread_rules: Variant = null
	var crosshair_cone: bool = false
	var tick_rate: Variant = 0


func _test_native_tick() -> void:
	_section("the native spread tick matches the GDScript tick")
	var present := ClassDB.class_exists(&"DotSimWeaponSpread")
	var native_was := DotWeaponHitscan.native_tick
	if not present:
		# The case checks, twice each rest stream's (the bridge check but for explicit_still, the skip, the steady skip of
		# a cone mode) and the streams' agreement (the native tick, then the idle row), and the missing-class fallback.
		# Then the idle gate's four.
		for i in range(4 + (_MODES.size() * 2 - 1 + _CONE_MODES.size() + 1) * 2 + 1 + 4):
			_check(true, "skip: DotSimWeaponSpread not loaded")
		_done()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	var ticks := 0
	var shown_ticks := 0
	var edits := 0
	var native_ran := true
	var script_clean := true
	var steady_off := true
	var first_miss := ""
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hn: DotWeaponHitscan = w[0]
		var hs: DotWeaponHitscan = w[1]
		var ctx := DotWeaponContext.new()
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs)
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.04:
				edits += _native_edit(rng, w)
			if rng.randf() < 0.05:
				# A use between ticks: both states take the same writes.
				var bloom := float(hs.state.get(&"bloom", 0.0)) + rng.randf_range(0.0, 1.5)
				for d: Dictionary in [hn.state, hs.state]:
					d[&"since_use"] = 0
					d[&"bloom"] = bloom
			var none := rng.randf() < 0.1
			DotWeaponHitscan.native_tick = true
			hn._tick(null if none else ctx)
			DotWeaponHitscan.native_tick = false
			hs._tick(null if none else ctx)
			ticks += 1
			if not none:
				shown_ticks += 1
				if hn._native == null:
					native_ran = false
				if hn._steady:
					steady_off = false
			var miss := _native_state_diff(hs.state, hn.state)
			if miss == "" and hn._shown != hs._shown:
				miss = "shown script %s native %s" % [hs._shown, hn._shown]
			if miss != "" and first_miss == "":
				first_miss = "case %d tick %d: %s" % [i, t, miss]
		if hs._native != null:
			script_clean = false
	DotWeaponHitscan.native_tick = native_was

	_check(first_miss == "", "%d ticks of %d random weapons: state and cone match the GDScript tick, key for key and bit for bit" % [ticks, _NATIVE_CASES], first_miss)
	_check(native_ran and steady_off, "every context tick of the native twin ran natively and kept no steady fixed point (%d)" % shown_ticks)
	_check(script_clean, "with native_tick off a behaviour never builds the native twin")
	_check(edits > 200, "the tuning, rules, class, rate and crosshair edits that must refresh the native rows happened", str(edits))

	_check_native_rest_streams(native_was)
	_check_native_row_streams(native_was)
	_check_native_missing_class(native_was)
	_check_idle_gate(native_was)
	_done()


## The rest streams: the native tick and the script tick agree on one arsenal.
func _check_native_rest_streams(native_was: bool) -> void:
	_rest_native = true
	var all_same := true
	var detail := ""
	for mode: String in _MODES:
		var res := _rest_stream(mode)
		if not res["same"] or not res["spread_same"]:
			all_same = false
			detail = res["detail"]
	_rest_native = false
	DotWeaponHitscan.native_tick = native_was
	DotWeaponHitscan.steady_skip = true
	_check(all_same, "the rest streams agree with the native tick on one arsenal: outcomes, snapshots, state and cone", detail)


## The rest streams again, with that arsenal's idle ticks as one native call from a posture row (idle_tick_row). The
## idle gate runs its verify mode here (DotWeaponBehaviour.idle_gate 2): _check_idle_gate counts what it found.
func _check_native_row_streams(native_was: bool) -> void:
	_rest_native = true
	_rest_row = true
	_gate_row_misses = DotWeaponBehaviour.idle_gate_misses
	var gate_was := DotWeaponBehaviour.idle_gate
	DotWeaponBehaviour.idle_gate = 2
	var all_same := true
	var detail := ""
	for mode: String in _MODES:
		var res := _rest_stream(mode)
		if not res["same"] or not res["spread_same"]:
			all_same = false
			detail = res["detail"]
	_rest_row = false
	_rest_native = false
	DotWeaponBehaviour.idle_gate = gate_was
	_gate_row_misses = DotWeaponBehaviour.idle_gate_misses - _gate_row_misses
	DotWeaponHitscan.native_tick = native_was
	DotWeaponHitscan.steady_skip = true
	_check(all_same, "the rest streams agree with the idle row on one arsenal: outcomes, snapshots, state and cone", detail)


var _gate_row_misses := 0


## DotWeaponBehaviour.idle_gate: the gated idle row (1) and its verify mode (2) leave what the plain one (0) leaves, bit
## for bit, over three behaviours on one random weapon edited mid-run (tuning, rules, class, rate, crosshair) with uses and
## script ticks between rows; then a posed tick_needs_context answers as the plain one for every kind of weapon.
func _check_idle_gate(native_was: bool) -> void:
	var gate_was := DotWeaponBehaviour.idle_gate
	var misses_was := DotWeaponBehaviour.idle_gate_misses
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var rows := 0
	var held := 0
	var first_miss := ""
	DotWeaponHitscan.native_tick = true
	for i in range(_NATIVE_CASES):
		var w := _native_case(rng)
		var hs: Array[DotWeaponHitscan] = [w[0], w[1], DotWeaponHitscan.new()]
		hs[2].setup(w[3], w[4])
		var arsenal: NativeArsenal = w[4]
		var ctx := DotWeaponContext.new()
		var hold := 0
		for t in range(_NATIVE_TICKS):
			if hold <= 0:
				_native_posture_roll(rng, ctx, hs[0])
				hold = rng.randi_range(1, 24)
			hold -= 1
			ctx.tick = t
			if rng.randf() < 0.04:
				_native_edit(rng, w)
			if rng.randf() < 0.05:
				var bloom := float(hs[0].state.get(&"bloom", 0.0)) + rng.randf_range(0.0, 1.5)
				for h in hs:
					h.state[&"since_use"] = 0
					h.state[&"bloom"] = bloom
			if rng.randf() < 0.05:
				# A script context tick between rows: it may leave a steady fixed point the rows must decline on.
				DotWeaponHitscan.native_tick = false
				for h in hs:
					h._tick(ctx)
				DotWeaponHitscan.native_tick = true
			var row := PackedFloat64Array([ctx.speed, float(ctx.airborne), float(ctx.crouched), float(ctx.aiming),
					float(ctx.sliding), float(ctx.sprinting), float(ctx.wall_running), ctx.tick, ctx.hurt_tick])
			var rest := rng.randf() < 0.5
			var rules: DotWeaponSpreadRules = arsenal.spread_rules
			var rate: int = arsenal.tick_rate
			var took: Array[int] = []
			for g in range(3):
				DotWeaponBehaviour.idle_gate = g
				if g == 1 and hs[1]._idle_gate_holds(rules, arsenal.crosshair_cone and rules != null, rate):
					held += 1
				took.append(hs[g].idle_row_framed(row, rest, rules, arsenal.crosshair_cone, rate))
			rows += 1
			for g in [1, 2]:
				var miss := _native_state_diff(hs[0].state, hs[g].state)
				if miss == "" and (took[g] != took[0] or hs[g]._shown != hs[0]._shown or hs[g]._shown_stale != hs[0]._shown_stale or hs[g]._steady != hs[0]._steady):
					miss = "took %s shown %s/%s stale %s/%s" % [took, hs[0]._shown, hs[g]._shown, hs[0]._shown_stale, hs[g]._shown_stale]
				if miss != "" and first_miss == "":
					first_miss = "gate %d case %d tick %d: %s" % [g, i, t, miss]
	DotWeaponBehaviour.idle_gate = gate_was
	DotWeaponHitscan.native_tick = native_was
	var misses := DotWeaponBehaviour.idle_gate_misses - misses_was
	_check(first_miss == "", "%d idle rows of %d random weapons: gate 1 and its verify mode leave what gate 0 leaves, key for key and bit for bit" % [rows, _NATIVE_CASES], first_miss)
	_check(held > rows / 2 and misses == 0, "the gate held on most rows (%d of %d) and its verify mode found nothing" % [held, rows], "held %d misses %d" % [held, misses])
	_check(_gate_row_misses == 0, "the rest streams' idle rows under the verify mode: the arsenal's frame is the one idle_row reads, the gate never stale", str(_gate_row_misses))

	var cat := _catalogue()
	var a := _arsenal(cat)
	var ctx := DotWeaponContext.new()
	a.idle_posture = func() -> DotWeaponContext: return ctx
	var differ := ""
	for id in cat.ids():
		var made := cat.instantiate(id, a)
		var b: DotWeaponBehaviour = made.value if made.ok else null
		if b == null or b.tick_needs_context_posed() != b.tick_needs_context():
			differ += "%s " % id
	_drop(a)
	_check(differ == "", "with a posture, tick_needs_context_posed answers as tick_needs_context for every weapon in the catalogue", differ)


## A missing native class leaves the GDScript tick.
func _check_native_missing_class(native_was: bool) -> void:
	var cat := _catalogue()
	var a := _arsenal(cat)
	a.give(&"rifle")
	var h := a.current().behaviour as DotWeaponHitscan
	var present_was := DotWeaponHitscan._native_present
	DotWeaponHitscan._native_present = 0
	DotWeaponHitscan.native_tick = true
	h._tick(_ctx(0))
	_check(h._native == null and h.state.has(&"since_use"), "without the class the GDScript tick runs")
	DotWeaponHitscan._native_present = present_was
	DotWeaponHitscan.native_tick = native_was
	_drop(a)



## A random weapon on a stub arsenal, as GameSpice Sim's parity test builds it: [native behaviour, script behaviour, ballistics,
## def, arsenal]. Both behaviours share the def, tuning and arsenal, so an edit reaches both.
func _native_case(rng: RandomNumberGenerator) -> Array:
	var b := DotWeaponBallistics.new()
	b.spread = rng.randf_range(0.0, 3.0)
	b.spread_moving = rng.randf_range(0.0, 8.0)
	b.spread_speed_ref = [0.1, 3.0, 6.0, rng.randf_range(0.5, 12.0)][rng.randi_range(0, 3)]
	b.spread_airborne = rng.randf_range(0.0, 10.0)
	b.spread_crouched = rng.randf_range(0.2, 1.0)
	b.bloom = 0.0 if rng.randf() < 0.15 else rng.randf_range(0.05, 1.0)
	b.bloom_max = rng.randf_range(0.5, 6.0)
	b.bloom_recovery = rng.randf_range(0.01, 0.5)
	b.accuracy_class = _native_class_roll(rng)
	b.bloom_delay_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 20)
	b.settle_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 12)
	for f: StringName in [&"spread_aim", &"spread_hip", &"spread_sprint", &"spread_slide", &"spread_flinch", &"bloom_crouch"]:
		b.set(f, -1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 2.0))
	var def := DotWeaponDef.new()
	def.id = StringName(["ak", "mp5", "awp", "deagle", "m3", "x"][rng.randi_range(0, 5)])
	def.tuning = b
	def.authored_tick_rate = [0, 64, 128][rng.randi_range(0, 2)]
	def.use_interval_ticks = rng.randi_range(0, 20)
	var arsenal := NativeArsenal.new()
	arsenal.tick_rate = [0, 33, 64, 128][rng.randi_range(0, 3)]
	arsenal.crosshair_cone = rng.randf() < 0.5
	var pick := rng.randi_range(0, 2)
	if pick > 0:
		arsenal.spread_rules = _native_rules_roll(rng, pick == 2)
	var hn := DotWeaponHitscan.new()
	hn.setup(def, arsenal)
	var hs := DotWeaponHitscan.new()
	hs.setup(def, arsenal)
	return [hn, hs, b, def, arsenal]


func _native_class_roll(rng: RandomNumberGenerator) -> String:
	return ["", "rifle", "smg", "lmg", "sniper", "shotgun", "pistol"][rng.randi_range(0, 6)]


func _native_rules_roll(rng: RandomNumberGenerator, enabled: bool) -> DotWeaponSpreadRules:
	var r := DotWeaponSpreadRules.new()
	r.enabled = enabled
	r.scale = rng.randf_range(0.5, 2.0)
	for f: StringName in [&"mult_hip", &"mult_aim", &"mult_stand", &"mult_walk", &"mult_run", &"mult_air", &"mult_sprint", &"mult_slide", &"mult_crouch"]:
		r.set(f, rng.randf_range(0.3, 2.5))
	r.walk_speed = rng.randf_range(0.1, 2.0)
	r.run_speed = rng.randf_range(2.0, 6.0)
	r.recovery = 0.0 if rng.randf() < 0.1 else rng.randf_range(0.5, 12.0)
	r.max_spread = 0.0 if rng.randf() < 0.2 else rng.randf_range(2.0, 20.0)
	return r


## One edit the cached native rows must see: a ballistics field, the class, the def's tick fields, the arsenal's rate,
## crosshair or rules (a field, on/off, a new object or none). Returns 1.
func _native_edit(rng: RandomNumberGenerator, w: Array) -> int:
	var b: DotWeaponBallistics = w[2]
	var def: DotWeaponDef = w[3]
	var arsenal: NativeArsenal = w[4]
	match rng.randi_range(0, 11):
		0: b.spread = rng.randf_range(0.0, 3.0)
		1: b.spread_moving = rng.randf_range(0.0, 8.0)
		2: b.bloom_recovery = rng.randf_range(0.01, 0.5)
		3: b.set([&"spread_aim", &"spread_hip", &"spread_sprint", &"spread_slide", &"spread_flinch", &"bloom_crouch"][rng.randi_range(0, 5)], -1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 2.0))
		4: b.accuracy_class = _native_class_roll(rng)
		5: b.settle_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 12)
		6: def.use_interval_ticks = rng.randi_range(0, 20)
		7: arsenal.tick_rate = [0, 33, 64, 128][rng.randi_range(0, 3)]
		8: arsenal.crosshair_cone = not arsenal.crosshair_cone
		9:
			if arsenal.spread_rules != null:
				var r: DotWeaponSpreadRules = arsenal.spread_rules
				match rng.randi_range(0, 3):
					0: r.mult_stand = rng.randf_range(0.3, 2.5)
					1: r.recovery = rng.randf_range(0.5, 12.0)
					2: r.max_spread = 0.0 if rng.randf() < 0.2 else rng.randf_range(2.0, 20.0)
					3: r.enabled = not r.enabled
		10: arsenal.spread_rules = null if rng.randf() < 0.3 else _native_rules_roll(rng, rng.randf() < 0.7)
		11: b.bloom_delay_ticks = -1 if rng.randf() < 0.5 else rng.randi_range(0, 20)
	return 1


## A random posture: often still, at the rules' thresholds, or flinching.
func _native_posture_roll(rng: RandomNumberGenerator, ctx: DotWeaponContext, h: DotWeaponHitscan) -> void:
	var r := h._rules_object()
	var speeds := [0.0, 0.0, rng.randf_range(0.0, 10.0), rng.randf_range(0.0, 1.0)]
	if r != null:
		speeds.append_array([r.walk_speed, r.run_speed])
	ctx.speed = speeds[rng.randi_range(0, speeds.size() - 1)]
	ctx.airborne = rng.randf() < 0.2
	ctx.crouched = rng.randf() < 0.25
	ctx.aiming = rng.randf() < 0.3
	ctx.sliding = rng.randf() < 0.1
	ctx.sprinting = rng.randf() < 0.2
	ctx.wall_running = rng.randf() < 0.05
	ctx.hurt_tick = ctx.tick - rng.randi_range(-2, 40) if rng.randf() < 0.3 else -1


## "" when the two states hold the same keys with the same types and values, else the first difference.
func _native_state_diff(want: Dictionary, got: Dictionary) -> String:
	if want.size() != got.size():
		return "keys script %s native %s" % [want.keys(), got.keys()]
	for k: Variant in want:
		if not got.has(k):
			return "native has no %s" % k
		if typeof(want[k]) != typeof(got[k]) or want[k] != got[k]:
			return "%s script %s (%s) native %s (%s)" % [k, want[k], type_string(typeof(want[k])), got[k], type_string(typeof(got[k]))]
	return ""
