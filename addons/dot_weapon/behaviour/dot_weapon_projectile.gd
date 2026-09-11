class_name DotWeaponProjectile
extends DotWeaponBehaviour

## A weapon that puts something in the world which will arrive later: a rocket
## launcher, a grenade launcher, a bow, a crossbow.
##
## [b]A bow is this behaviour and nothing else.[/b] Set the definition's fire mode to
## [constant DotWeaponDef.Fire.CHARGE] and the arsenal accumulates the draw; this reads
## [member DotWeaponContext.charge] and scales the arrow's speed and damage between the
## tuning's minimum and full values. That is the whole of it — no bow class, no draw
## field on the definition, no branch in the arsenal. A crossbow is the same row with
## [constant DotWeaponDef.Fire.SEMI] and a reload.
##
## It produces a [DotWeaponSpawn] rather than a [DotShot], because a thing with a
## flight time is not something lag compensation has anything to say about: by the time
## it lands, everybody already agrees where everybody is.

func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var speed := b.speed_at(ctx.charge) if b != null else tune_float(&"speed", 60.0)
	var damage := b.damage_at(ctx.charge) if b != null else tune_float(&"damage", 50.0)

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SPAWN)

	var spawn := DotWeaponSpawn.make(
		StringName(tune(&"projectile_id", def.id)),
		ctx.origin,
		ctx.direction * speed,
		ctx.entity
	)
	spawn.tick = ctx.tick
	spawn.damage = damage

	if b != null:
		spawn.damage_type = b.damage_type
		spawn.gravity_scale = b.gravity_scale
		spawn.radius = b.radius
		spawn.life_ticks = b.life_ticks
		spawn.splash_radius = b.splash_radius
		spawn.splash_damage = b.splash_damage
		out.recoil = Vector2(b.recoil_pitch, b.recoil_yaw)

	spawn.meta["charge"] = ctx.charge
	out.add_spawn(spawn)

	return out
