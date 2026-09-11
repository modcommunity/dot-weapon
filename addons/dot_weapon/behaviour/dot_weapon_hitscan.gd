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


func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _tick(_ctx: DotWeaponContext) -> void:
	var b := _ballistics()
	if b == null or b.bloom <= 0.0:
		return

	var now := float(state.get(_BLOOM, 0.0))
	if now > 0.0:
		state[_BLOOM] = maxf(0.0, now - b.bloom_recovery)


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var damage := b.damage_at(ctx.charge) if b != null else tune_float(&"damage", 20.0)
	var max_range := b.max_range if b != null else tune_float(&"max_range", 200.0)
	var pellets := b.pellets if b != null else tune_int(&"pellets", 1)

	var spread := 0.0
	if b != null:
		spread = b.spread_for(ctx.speed, ctx.airborne, ctx.crouched)
		spread += minf(float(state.get(_BLOOM, 0.0)), b.bloom_max)
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

	shot.scatter()
	out.add_shot(shot)

	if b != null:
		out.recoil = Vector2(b.recoil_pitch, b.recoil_yaw)
		if b.bloom > 0.0:
			state[_BLOOM] = minf(
				float(state.get(_BLOOM, 0.0)) + b.bloom, b.bloom_max
			)

	return out


func describe() -> Dictionary:
	var d := super.describe()
	d["bloom"] = float(state.get(_BLOOM, 0.0))
	return d
