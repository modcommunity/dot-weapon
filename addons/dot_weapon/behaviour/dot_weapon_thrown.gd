class_name DotWeaponThrown
extends DotWeaponBehaviour

## Something the carrier holds and then lets go of: a grenade, a molotov, a throwing
## knife, a bait can.
##
## [b]The fuse starts when the pin comes out, not when the object leaves the hand.[/b]
## That is the whole reason this is not just [DotWeaponProjectile] with a timer: cooking
## a grenade is a real decision with a real cost, and a fuse that starts on release
## makes every grenade a four-second warning for whoever it lands near. Used with
## [constant DotWeaponDef.Fire.CHARGE], the charge is the cook, and the spawn's
## remaining fuse is what is left of it.
##
## [b]Cooking past the fuse kills the carrier, and it should.[/b] A grenade that simply
## refuses to go off in your hand is one with no downside to holding. The behaviour
## spawns it in place with no velocity and a zero fuse, which is what a grenade going
## off at your feet is, and lets the ordinary splash rules do the rest.

func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var fuse := tune_int(&"fuse_ticks", 256)
	var cooked := int(round(ctx.charge * float(def.charge_ticks)))
	var left := maxi(0, fuse - cooked)

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_THROW)

	var speed := b.speed_at(ctx.charge) if b != null else tune_float(&"speed", 18.0)
	# A cooked grenade is not thrown harder. Charge is the cook here, so the launch
	# speed comes off the tuning's full value rather than scaling with the hold, and a
	# player who cooks for three seconds does not also lob it twice as far.
	if tune_bool(&"speed_scales_with_cook", false) == false and b != null:
		speed = b.speed

	var spawn := DotWeaponSpawn.make(
		StringName(tune(&"projectile_id", def.id)),
		ctx.origin,
		ctx.direction * speed,
		ctx.entity
	)
	spawn.tick = ctx.tick
	spawn.fuse_ticks = left
	spawn.damage = b.damage if b != null else tune_float(&"damage", 0.0)

	if b != null:
		spawn.damage_type = b.damage_type
		spawn.gravity_scale = maxf(b.gravity_scale, 1.0)
		spawn.radius = b.radius
		spawn.life_ticks = maxi(b.life_ticks, left + 1)
		spawn.splash_radius = b.splash_radius
		spawn.splash_damage = b.splash_damage

	if left <= 0:
		# It went off in the hand. No velocity, no fuse, at the carrier's own position.
		spawn.velocity = Vector3.ZERO
		spawn.origin = ctx.origin
		out.add_event({"event": "cooked_off", "weapon": String(def.id)})

	spawn.meta["cooked_ticks"] = cooked
	out.add_spawn(spawn)

	return out
