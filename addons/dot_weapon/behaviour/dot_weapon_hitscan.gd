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
var _class: String = ""
## The cone the last context tick or use computed, for display; -1 before any.
var _shown: float = -1.0


func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _tick(ctx: DotWeaponContext) -> void:
	var b := _ballistics()
	if b == null:
		return

	var since := mini(int(state.get(_SINCE, _NEVER)) + 1, _NEVER)
	state[_SINCE] = since
	if b.bloom > 0.0:
		var now := float(state.get(_BLOOM, 0.0))
		if now > 0.0 and since >= bloom_delay_ticks():
			state[_BLOOM] = maxf(0.0, now - scaled_per_tick(b.bloom_recovery))

	if ctx == null:
		return

	var target_motion := _motion_of(b, ctx)
	var held_motion := float(state.get(_MOTION, 0.0))
	var settle := _class_ticks(b.settle_ticks, "settle")
	var motion := target_motion
	if target_motion < held_motion and settle > 0:
		motion = maxf(target_motion, held_motion - 1.0 / float(settle))
	# A still carrier leaves no key, so this tick's state equals the idle path's (which never sees a ctx).
	if motion > 0.0:
		state[_MOTION] = motion
	else:
		state.erase(_MOTION)

	var rules := _rules()
	if rules != null:
		var target := rules.target_factor(ctx)
		var held := float(state.get(_FACTOR, 1.0))
		state[_FACTOR] = target if target >= held else maxf(target, held - rules.recovery_per_tick(running_tick_rate()))

	_shown = _spread_for(b, ctx)
	# Only state the idle path would also have: a still gun without rules keeps the cone out of it.
	if _rules_object() != null or held_motion > 0.0 or motion > 0.0:
		state[_NOW] = _shown


## A crosshair gets the cone the last tick computed, so it cannot disagree with the shot.
func spread_now() -> float:
	return _shown if _shown >= 0.0 else float(state.get(_NOW, 0.0))


## Needs a context with spread rules attached (the crosshair follows an idle player) or while the cone settles.
func tick_needs_context() -> bool:
	return _rules_object() != null or float(state.get(_MOTION, 0.0)) > 0.0 or super.tick_needs_context()


## The accuracy class of this weapon (see [DotWeaponAccuracyClass]).
func accuracy_class() -> String:
	var b := _ballistics()
	var key := "%s|%s" % [b.accuracy_class if b != null else "", def.id if def != null else &""]
	if key != _class_key:
		_class_key = key
		_class = DotWeaponAccuracyClass.resolve(b.accuracy_class if b != null else "", def.tags if def != null else [], def.id if def != null else &"")
	return _class


## Running ticks after a use before bloom sheds: the class or own delay, never inside the use interval.
func bloom_delay_ticks() -> int:
	var b := _ballistics()
	var own := _class_ticks(b.bloom_delay_ticks, "bloom_delay") if b != null else 0
	var interval := scaled_ticks(def.use_interval_ticks) if def != null else 0
	return maxi(own, interval + 1)


func _class_ticks(own: int, key: String) -> int:
	if own >= 0:
		return scaled_ticks(own)
	var rate := running_tick_rate()
	if rate <= 0:
		rate = def.authored_tick_rate if def != null and def.authored_tick_rate > 0 else 64
	return roundi(DotWeaponAccuracyClass.preset(accuracy_class(), key) * float(rate))


func _motion_of(b: DotWeaponBallistics, ctx: DotWeaponContext) -> float:
	return clampf(ctx.speed / maxf(0.001, b.spread_speed_ref), 0.0, 1.0)


func _rules_object() -> DotWeaponSpreadRules:
	return arsenal.get("spread_rules") as DotWeaponSpreadRules if arsenal != null else null


func _rules() -> DotWeaponSpreadRules:
	var rules := _rules_object()
	return rules if rules != null and rules.enabled else null


## The cone for this context: posture, settling motion, hip, flinch and the server rules, plus bloom;
## aiming then tightens the whole, and `sv_spread_scale` scales it.
func _spread_for(b: DotWeaponBallistics, ctx: DotWeaponContext) -> float:
	var klass := accuracy_class()
	var motion := maxf(float(state.get(_MOTION, 0.0)), _motion_of(b, ctx))
	var out := b.spread_for_motion(motion, ctx.airborne, ctx.crouched)
	if not ctx.aiming:
		out += b.accuracy("spread_hip", klass)
	if ctx.sliding or ctx.wall_running:
		out *= b.accuracy("spread_slide", klass)
	elif ctx.sprinting and not ctx.airborne:
		out *= b.accuracy("spread_sprint", klass)
	if ctx.hurt_tick >= 0 and ctx.tick >= ctx.hurt_tick:
		var rate := float(maxi(running_tick_rate(), 1)) if running_tick_rate() > 0 else 64.0
		var left := 1.0 - float(ctx.tick - ctx.hurt_tick) / (DotWeaponAccuracyClass.FLINCH_SEC * rate)
		out += b.accuracy("spread_flinch", klass) * clampf(left, 0.0, 1.0)
	var rules := _rules()
	if rules != null:
		out = rules.apply(out, float(state.get(_FACTOR, 1.0)))
	var bloom := minf(float(state.get(_BLOOM, 0.0)), b.bloom_max)
	if ctx.crouched:
		bloom *= b.accuracy("bloom_crouch", klass)
	out += bloom
	if ctx.aiming:
		out *= b.accuracy("spread_aim", klass)
	var every := _rules_object()
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
	if DotWeaponBallisticsRules.simulates(arsenal.get("ballistics_rules") as DotWeaponBallisticsRules if arsenal != null else null, b):
		shot.deferred = true
		var round_id: StringName = arsenal.call("ammo_of", def.id) if arsenal.has_method("ammo_of") else &""
		if round_id != &"":
			shot.set_meta(&"ammo", round_id)

	shot.scatter()
	out.add_shot(shot)

	if b != null:
		if rr == null:
			var scale := recoil_posture(b, ctx)
			var flat := arsenal.get("recoil_rules") as DotWeaponRecoilRules if arsenal != null else null
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
