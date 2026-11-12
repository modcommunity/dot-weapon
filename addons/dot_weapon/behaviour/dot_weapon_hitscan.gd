class_name DotWeaponHitscan
extends DotWeaponBehaviour

## A weapon whose damage arrives the instant it is used: a rifle, a pistol, a shotgun,
## a railgun.
##
## Produces [DotShot]s for dot-combat to resolve against a world rewound to the tick
## the trigger was pulled on. It applies nothing itself.
##
## Reads a [DotWeaponBallistics], from [member DotWeaponDef.tuning] or from
## [member DotWeaponDef.params] under the same key names.

## Degrees of bloom currently piled up. Kept in [member state] so it survives the wire
## and a rollback; a bloom held in a plain member desynchronises on the first correction
## and the only symptom is a weapon that is more accurate on one machine than the other.
const _BLOOM := &"bloom"

## The smoothed movement multiplier of [DotWeaponSpreadRules], and the cone last computed.
const _FACTOR := &"spread_factor"
const _NOW := &"spread_now"
## Ticks since the last use, and the smoothed motion (0 still, 1 at the reference speed) that settles.
const _SINCE := &"since_use"
const _MOTION := &"motion"
const _NEVER := 1 << 20

var _class_key: String = ""
var _class_id: StringName = &""
var _class_key_set: bool = false
var _class: String = ""
## The class presets of [member _class] that every cone and settle reads, set with it in [method _class_of]:
## [constant DotWeaponAccuracyClass.PRESETS] is a constant, so they hold until the class changes. A ballistics field of 0
## or more still wins over its preset and is read each time, as [method DotWeaponBallistics.accuracy] does.
var _pre_hip: float = 0.0
var _pre_slide: float = 1.0
var _pre_sprint: float = 1.0
var _pre_flinch: float = 0.0
var _pre_crouch: float = 1.0
var _pre_aim: float = 1.0
var _pre_settle: float = 0.0
## The cone the last context tick or use computed, for display; -1 before any.
var _shown: float = -1.0
## Set by [method rest_tick]: the skipped ticks did not compute the cone, [method spread_now] does it when asked.
var _shown_stale: bool = false
var _settled: DotWeaponContext = null

## Off: every context tick computes the cone, for an A/B of the steady skip (see [method _steady_holds]); results agree.
static var steady_skip: bool = true

# The last context tick that was a fixed point: everything it read, and the cone it computed.
var _steady: bool = false
var _steady_b: DotWeaponBallistics = null
var _steady_rules: DotWeaponSpreadRules = null
var _steady_cone: bool = false
var _steady_airborne: bool = false
var _steady_crouched: bool = false
var _steady_aiming: bool = false
var _steady_sliding: bool = false
var _steady_sprinting: bool = false
var _steady_wall: bool = false
var _steady_motion: float = 0.0
var _steady_bloom: float = 0.0
var _steady_write_now: bool = false
var _steady_shown: float = 0.0
var _steady_enabled: bool = false
var _steady_scale: float = 1.0
var _steady_max: float = 0.0
var _steady_factor: float = 1.0
var _steady_class: String = ""
var _steady_tuning := PackedFloat64Array()


func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _tick(ctx: DotWeaponContext) -> void:
	var b := _ballistics()
	if b == null:
		return

	if _shown_stale:
		# A tick with a context overwrites the cone below; one without keeps it, so settle it before the state moves.
		if ctx == null:
			_refresh_shown(b)
		else:
			_shown_stale = false

	var since := mini(int(state.get(_SINCE, _NEVER)) + 1, _NEVER)
	state[_SINCE] = since
	if b.bloom > 0.0:
		var now := float(state.get(_BLOOM, 0.0))
		if now > 0.0 and since >= _bloom_delay_of(b):
			state[_BLOOM] = maxf(0.0, now - scaled_per_tick(b.bloom_recovery))

	if ctx == null:
		return

	# Read from the arsenal once a tick: the steady check, the factor, the cone and the tracking below all ask for the same rules.
	var rules_object := _rules_object()
	var cone := rules_object != null and bool(arsenal.get(&"crosshair_cone"))
	if steady_skip and _steady and _steady_holds(b, ctx, rules_object, cone):
		_shown = _steady_shown
		return

	var target_motion := _motion_of(b, ctx)
	var had_motion := state.has(_MOTION)
	var held_motion := float(state.get(_MOTION, 0.0))
	var motion := target_motion
	if target_motion < held_motion:
		var settle := _settle_ticks_of(b)
		if settle > 0:
			motion = maxf(target_motion, held_motion - 1.0 / float(settle))
	# A still carrier leaves no key, so this tick's state equals the idle path's (which never sees a ctx).
	if motion > 0.0:
		state[_MOTION] = motion
	else:
		state.erase(_MOTION)

	var rules := rules_object if rules_object != null and rules_object.enabled else null
	var factor_still := true
	if rules != null:
		var target := rules.target_factor(ctx)
		var had_factor := state.has(_FACTOR)
		var held := float(state.get(_FACTOR, 1.0))
		var factor := target if target >= held else maxf(target, held - rules.recovery_per_tick(running_tick_rate()))
		state[_FACTOR] = factor
		factor_still = had_factor and factor == held

	_shown = _spread_with(b, ctx, rules, rules_object)
	# Only state the idle path would also have: a still gun without rules keeps the cone out of it.
	var write_now := cone or held_motion > 0.0 or motion > 0.0
	var now_still := true
	if write_now:
		now_still = state.has(_NOW) and float(state[_NOW]) == _shown
		state[_NOW] = _shown

	# This tick left the state as it found it (only the ticks since the last use moved): keep what it read, so the next
	# tick with the same inputs skips the work. A flinch fades with the tick, so a tick inside one is never a fixed point.
	_steady = false
	if steady_skip and factor_still and now_still and motion == held_motion and had_motion == (motion > 0.0) and not _flinching(ctx):
		_steady_keep(b, ctx, rules_object, cone, motion)


## A context tick with the inputs of the kept fixed point: the same ballistics, rules and tuning, the same posture, a
## state still at that point (motion, factor, bloom and the shown cone) and no flinch. Its [method _tick] would write the
## values already there and compute the kept cone, so only the ticks since the last use (counted above) move.
func _steady_holds(b: DotWeaponBallistics, ctx: DotWeaponContext, rules_object: DotWeaponSpreadRules, cone: bool) -> bool:
	if b != _steady_b or rules_object != _steady_rules or cone != _steady_cone:
		return false
	if ctx.airborne != _steady_airborne or ctx.crouched != _steady_crouched or ctx.aiming != _steady_aiming:
		return false
	if ctx.sliding != _steady_sliding or ctx.sprinting != _steady_sprinting or ctx.wall_running != _steady_wall:
		return false
	if _motion_of(b, ctx) != _steady_motion or float(state.get(_MOTION, 0.0)) != _steady_motion:
		return false
	if state.has(_MOTION) != (_steady_motion > 0.0) or float(state.get(_BLOOM, 0.0)) != _steady_bloom:
		return false
	if _steady_write_now and not (state.has(_NOW) and float(state[_NOW]) == _steady_shown):
		return false
	if rules_object != null:
		if rules_object.enabled != _steady_enabled or rules_object.scale != _steady_scale or rules_object.max_spread != _steady_max:
			return false
		if _steady_enabled:
			if not state.has(_FACTOR) or float(state[_FACTOR]) != _steady_factor or rules_object.target_factor(ctx) != _steady_factor:
				return false
	if _flinching(ctx) or not _tuning_same(b):
		return false
	return _class_of(b) == _steady_class


func _steady_keep(b: DotWeaponBallistics, ctx: DotWeaponContext, rules_object: DotWeaponSpreadRules, cone: bool, motion: float) -> void:
	_steady = true
	_steady_b = b
	_steady_rules = rules_object
	_steady_cone = cone
	_steady_airborne = ctx.airborne
	_steady_crouched = ctx.crouched
	_steady_aiming = ctx.aiming
	_steady_sliding = ctx.sliding
	_steady_sprinting = ctx.sprinting
	_steady_wall = ctx.wall_running
	_steady_motion = motion
	_steady_bloom = float(state.get(_BLOOM, 0.0))
	_steady_write_now = cone or motion > 0.0
	_steady_shown = _shown
	_steady_enabled = rules_object != null and rules_object.enabled
	_steady_scale = rules_object.scale if rules_object != null else 1.0
	_steady_max = rules_object.max_spread if rules_object != null else 0.0
	_steady_factor = float(state.get(_FACTOR, 1.0))
	_steady_class = _class_of(b)
	_steady_tuning = PackedFloat64Array([
		b.spread, b.spread_moving, b.spread_speed_ref, b.spread_airborne, b.spread_crouched, b.bloom_max,
		b.spread_hip, b.spread_slide, b.spread_sprint, b.spread_flinch, b.bloom_crouch, b.spread_aim,
	])


## Every ballistics number the cone reads, against the kept ones: a tuning edited in place (a console, a scaled aim) is seen.
func _tuning_same(b: DotWeaponBallistics) -> bool:
	var t := _steady_tuning
	return (
		t[0] == b.spread and t[1] == b.spread_moving and t[2] == b.spread_speed_ref and t[3] == b.spread_airborne
		and t[4] == b.spread_crouched and t[5] == b.bloom_max and t[6] == b.spread_hip and t[7] == b.spread_slide
		and t[8] == b.spread_sprint and t[9] == b.spread_flinch and t[10] == b.bloom_crouch and t[11] == b.spread_aim
	)


## Whether the flinch term of [method _spread_with] is above zero at this context's tick.
func _flinching(ctx: DotWeaponContext) -> bool:
	if ctx.hurt_tick < 0 or ctx.tick < ctx.hurt_tick:
		return false
	var running := running_tick_rate()
	var rate := float(maxi(running, 1)) if running > 0 else 64.0
	return 1.0 - float(ctx.tick - ctx.hurt_tick) / (DotWeaponAccuracyClass.FLINCH_SEC * rate) > 0.0


## A crosshair gets the cone the last tick computed, so it cannot disagree with the shot.
func spread_now() -> float:
	if _shown_stale:
		var b := _ballistics()
		if b != null:
			_refresh_shown(b)
	return _shown if _shown >= 0.0 else float(state.get(_NOW, 0.0))


## The cone the skipped rest ticks would have computed: the settled posture over today's state, rules and tuning.
func _refresh_shown(b: DotWeaponBallistics) -> void:
	_shown_stale = false
	_shown = _spread_for(b, _settled_ctx())


## A carrier that stands still on the ground, unhurt and not aiming: what [member DotWeaponArsenal.idle_still] stands for.
func _settled_ctx() -> DotWeaponContext:
	if _settled == null:
		_settled = DotWeaponContext.new()
	return _settled


## Nothing to recover (no bloom shedding, no motion settling, no spread factor moving, no cone kept for a crosshair) and a
## settled carrier: a [method tick] with the settled posture would change only the ticks since the last use, which this
## counts, so the rest of it is skipped. Anything else takes the normal tick.
func rest_tick(still: Callable) -> bool:
	var b := _ballistics()
	if b == null:
		return true

	if state.has(_MOTION):
		return false

	if b.bloom > 0.0 and float(state.get(_BLOOM, 0.0)) > 0.0:
		return false

	var rules_object := _rules_object()
	if rules_object != null and bool(arsenal.get(&"crosshair_cone")):
		return false

	if rules_object != null and rules_object.enabled:
		if not state.has(_FACTOR) or float(state[_FACTOR]) != rules_object.target_factor(_settled_ctx()):
			return false

	if not bool(still.call()):
		return false

	state[_SINCE] = mini(int(state.get(_SINCE, _NEVER)) + 1, _NEVER)
	_shown_stale = true
	return true


## Needs a context while enabled spread rules follow the carrier, a crosshair follows an idle player
## ([member DotWeaponArsenal.crosshair_cone]) or the cone settles, unless the arsenal has an
## [member DotWeaponArsenal.idle_posture] to stand in for it.
func tick_needs_context() -> bool:
	var wants := float(state.get(_MOTION, 0.0)) > 0.0
	if not wants:
		var rules_object := _rules_object()
		wants = rules_object != null and (rules_object.enabled or bool(arsenal.get(&"crosshair_cone")))
	if wants and not _posture_provided():
		return true
	return super.tick_needs_context()


func _posture_provided() -> bool:
	return arsenal != null and (arsenal.get(&"idle_posture") as Callable).is_valid()


## The accuracy class of this weapon (see [DotWeaponAccuracyClass]).
func accuracy_class() -> String:
	return _class_of(_ballistics())


# Takes the ballistics the caller already holds: a tick asks for the class up to three times.
func _class_of(b: DotWeaponBallistics) -> String:
	var explicit := b.accuracy_class if b != null else ""
	var id: StringName = def.id if def != null else &""
	# Compared field by field, not as one formatted key: every spread read asks this, every tick.
	if _class_key_set and explicit == _class_key and id == _class_id:
		return _class
	_class_key_set = true
	_class_key = explicit
	_class_id = id
	_class = DotWeaponAccuracyClass.resolve(explicit, def.tags if def != null else [], id)
	_pre_hip = DotWeaponAccuracyClass.preset(_class, "spread_hip")
	_pre_slide = DotWeaponAccuracyClass.preset(_class, "spread_slide")
	_pre_sprint = DotWeaponAccuracyClass.preset(_class, "spread_sprint")
	_pre_flinch = DotWeaponAccuracyClass.preset(_class, "spread_flinch")
	_pre_crouch = DotWeaponAccuracyClass.preset(_class, "bloom_crouch")
	_pre_aim = DotWeaponAccuracyClass.preset(_class, "spread_aim")
	_pre_settle = DotWeaponAccuracyClass.preset(_class, "settle")
	return _class


## Running ticks after a use before bloom sheds: the class or own delay, never inside the use interval.
func bloom_delay_ticks() -> int:
	return _bloom_delay_of(_ballistics())


func _bloom_delay_of(b: DotWeaponBallistics) -> int:
	var own := _class_ticks_of(b, b.bloom_delay_ticks, "bloom_delay") if b != null else 0
	var interval := scaled_ticks(def.use_interval_ticks) if def != null else 0
	return maxi(own, interval + 1)


func _class_ticks(own: int, key: String) -> int:
	return _class_ticks_of(_ballistics(), own, key)


func _class_ticks_of(b: DotWeaponBallistics, own: int, key: String) -> int:
	if own >= 0:
		return scaled_ticks(own)
	var rate := running_tick_rate()
	if rate <= 0:
		rate = def.authored_tick_rate if def != null and def.authored_tick_rate > 0 else 64
	return roundi(DotWeaponAccuracyClass.preset(_class_of(b), key) * float(rate))


## _class_ticks_of(b, b.settle_ticks, "settle") with the kept preset: a slowing carrier asks it every tick.
func _settle_ticks_of(b: DotWeaponBallistics) -> int:
	if b.settle_ticks >= 0:
		return scaled_ticks(b.settle_ticks)
	var rate := running_tick_rate()
	if rate <= 0:
		rate = def.authored_tick_rate if def != null and def.authored_tick_rate > 0 else 64
	_class_of(b)
	return roundi(_pre_settle * float(rate))


func _motion_of(b: DotWeaponBallistics, ctx: DotWeaponContext) -> float:
	return clampf(ctx.speed / maxf(0.001, b.spread_speed_ref), 0.0, 1.0)


func _cone_tracked() -> bool:
	return _rules_object() != null and bool(arsenal.get(&"crosshair_cone"))


func _rules_object() -> DotWeaponSpreadRules:
	return arsenal.get(&"spread_rules") as DotWeaponSpreadRules if arsenal != null else null


func _rules() -> DotWeaponSpreadRules:
	var rules := _rules_object()
	return rules if rules != null and rules.enabled else null


## The cone for this context: posture, settling motion, hip, flinch and the server rules, plus bloom;
## aiming then tightens the whole, and `sv_spread_scale` scales it.
func _spread_for(b: DotWeaponBallistics, ctx: DotWeaponContext) -> float:
	return _spread_with(b, ctx, _rules())


## [method _spread_for] under [param rules] (null for none), for a caller that already holds them;
## [param every] is [method _rules_object], enabled or not.
func _spread_with(
	b: DotWeaponBallistics, ctx: DotWeaponContext, rules: DotWeaponSpreadRules, every: DotWeaponSpreadRules = _rules_object()
) -> float:
	# Each term is b.accuracy(key, class) without its by-name lookups (an idle moving carrier computes this every tick):
	# the field when 0 or more, else the class preset _class_of keeps.
	_class_of(b)
	var motion := maxf(float(state.get(_MOTION, 0.0)), _motion_of(b, ctx))
	var out := b.spread_for_motion(motion, ctx.airborne, ctx.crouched)
	if not ctx.aiming:
		out += b.spread_hip if b.spread_hip >= 0.0 else _pre_hip
	if ctx.sliding or ctx.wall_running:
		out *= b.spread_slide if b.spread_slide >= 0.0 else _pre_slide
	elif ctx.sprinting and not ctx.airborne:
		out *= b.spread_sprint if b.spread_sprint >= 0.0 else _pre_sprint
	if ctx.hurt_tick >= 0 and ctx.tick >= ctx.hurt_tick:
		var running := running_tick_rate()
		var rate := float(maxi(running, 1)) if running > 0 else 64.0
		var left := 1.0 - float(ctx.tick - ctx.hurt_tick) / (DotWeaponAccuracyClass.FLINCH_SEC * rate)
		out += (b.spread_flinch if b.spread_flinch >= 0.0 else _pre_flinch) * clampf(left, 0.0, 1.0)
	if rules != null:
		out = rules.apply(out, float(state.get(_FACTOR, 1.0)))
	var bloom := minf(float(state.get(_BLOOM, 0.0)), b.bloom_max)
	if ctx.crouched:
		bloom *= b.bloom_crouch if b.bloom_crouch >= 0.0 else _pre_crouch
	out += bloom
	if ctx.aiming:
		out *= b.spread_aim if b.spread_aim >= 0.0 else _pre_aim
	if every != null:
		out *= every.scale
		if every.max_spread > 0.0:
			out = minf(out, every.max_spread)
	return out


## The weapon's own recoil multiplier for this posture (aim, crouch, moving or airborne).
func recoil_posture(b: DotWeaponBallistics, ctx: DotWeaponContext) -> float:
	var klass := accuracy_class()
	var f := 1.0
	if ctx.aiming:
		f *= b.accuracy("recoil_aim", klass)
	if ctx.crouched:
		f *= b.accuracy("recoil_crouch", klass)
	if ctx.airborne or ctx.speed >= 0.5:
		f *= b.accuracy("recoil_move", klass)
	return f


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var damage := b.damage_at(ctx.charge) if b != null else tune_float(&"damage", 20.0)
	var max_range := b.max_range if b != null else tune_float(&"max_range", 200.0)
	var pellets := b.pellets if b != null else tune_int(&"pellets", 1)

	var spread := 0.0
	if b != null:
		spread = _spread_for(b, ctx)
	else:
		spread = tune_float(&"spread", 0.0)

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SHOT)

	var shot := DotShot.make(def.id, ctx.entity, ctx.tick, ctx.index)
	shot.origin = ctx.origin
	shot.direction = ctx.direction
	shot.spread = spread
	shot.pellet_count = pellets
	shot.damage = damage
	shot.max_range = max_range
	shot.replayed = ctx.replayed

	if b != null:
		shot.damage_type = b.damage_type
		shot.fixed_pattern = b.fixed_pattern
		shot.splash_radius = b.splash_radius
		shot.splash_damage = b.splash_damage
		shot.splash_type = b.splash_type
		shot.splash_hurts_owner = b.splash_hurts_owner

	var rr := DotWeaponRecoilRules.of(arsenal)
	var bullet_offset := Vector2.ZERO
	if b != null and rr != null:
		bullet_offset = rr.apply(out, b, state, ctx, def.id, running_tick_rate(), recoil_posture(b, ctx))
		shot.direction = DotWeaponRecoilRules.offset_direction(shot.direction, bullet_offset)

	# A simulated bullet is flown by DotWeaponBulletBridge; the shot is deferred so dot-combat only
	# records its endpoint. Off (the default) this line never runs and the shot is unchanged.
	if DotWeaponBallisticsRules.simulates(arsenal.get(&"ballistics_rules") as DotWeaponBallisticsRules if arsenal != null else null, b):
		shot.deferred = true
		var round_id: StringName = arsenal.call("ammo_of", def.id) if arsenal.has_method("ammo_of") else &""
		if round_id != &"":
			shot.set_meta(&"ammo", round_id)

	if arsenal != null and arsenal.has_method("round_for") and not shot.deferred:
		var ammo := arsenal.call("round_for", def.id) as DotWeaponAmmoType
		if ammo != null:
			shot.penetration = ammo.make_penetration()
			shot.set_meta(&"ammo", ammo.id)

	shot.scatter()
	out.add_shot(shot)

	if b != null:
		if rr == null:
			var scale := recoil_posture(b, ctx)
			var flat := arsenal.get(&"recoil_rules") as DotWeaponRecoilRules if arsenal != null else null
			if flat != null:
				scale *= flat.scale
			out.recoil = Vector2(b.recoil_pitch, b.recoil_yaw) * scale
		if b.bloom > 0.0:
			state[_BLOOM] = minf(
				float(state.get(_BLOOM, 0.0)) + b.bloom, b.bloom_max
			)
		state[_SINCE] = 0
		state[_NOW] = _spread_for(b, ctx)
		_shown = float(state[_NOW])

	return out


func describe() -> Dictionary:
	var d := super.describe()
	d["bloom"] = float(state.get(_BLOOM, 0.0))
	return d
