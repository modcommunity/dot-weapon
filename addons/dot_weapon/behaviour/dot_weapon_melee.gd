class_name DotWeaponMelee
extends DotWeaponBehaviour

## A weapon that reaches a short distance in front of the carrier: a knife, a crowbar,
## a bat, a fist.
##
## [b]It is a [DotShot] with a very short range and several pellets in an arc[/b],
## rather than a system of its own. A swing that sweeps an arc and a shotgun that
## sprays a cone are the same question asked at different scales, and expressing the
## first as the second means it goes through the same lag compensation, the same hit
## groups and the same damage rules as everything else — which is what a player means
## when they say a knife "should have hit".
##
## The arc is [code]arc_degrees[/code] wide and sampled at [code]rays[/code] points.
## One ray is a lunge; five across sixty degrees is a sweep.

func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var reach := b.max_range if b != null else tune_float(&"reach", 2.0)
	var damage := b.damage_at(ctx.charge) if b != null else tune_float(&"damage", 50.0)
	var arc := tune_float(&"arc_degrees", 30.0)
	var rays := maxi(1, tune_int(&"rays", 3))

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SWING)

	var shot := DotShot.make(def.id, ctx.entity, ctx.tick, ctx.index)
	shot.origin = ctx.origin
	shot.direction = ctx.direction
	shot.damage = damage
	shot.max_range = reach
	shot.replayed = ctx.replayed
	shot.pellet_count = rays
	# A fixed pattern rather than a hashed one: a swing that scattered differently
	# every time would be a melee weapon that sometimes misses a target standing still
	# in front of it, which reads as broken rather than as spread.
	shot.fixed_pattern = true
	shot.spread = arc * 0.5

	if b != null:
		shot.damage_type = b.damage_type

	shot.scatter()
	out.add_shot(shot)

	return out
