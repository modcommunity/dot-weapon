class_name DotWeaponBeam
extends DotWeaponBehaviour

## A weapon that does its work continuously while the button is down: a laser, a
## flamethrower, a repair tool, a healing beam.
##
## Used with [constant DotWeaponDef.Fire.HOLD], so the arsenal calls [method _use] every
## tick the button is held and [member DotWeaponDef.use_interval_ticks] sets how often
## a tick of damage actually lands.
##
## [b]The damage is per use, not per second.[/b] It is the same decision dot-effects
## makes about periodic effects: "3 damage every 4 ticks" and "0.75 damage every tick"
## are different weapons, because the first can be interrupted between ticks and the
## second cannot, and a tick rate the game changes later must not silently change how
## much a beam does.
##
## [b]Ramp-up is read from [member DotWeaponContext.held_ticks][/b], which the arsenal
## maintains. A flamethrower that takes half a second to reach full output, and a
## repair tool that speeds up the longer it stays on one target, are the same field.

func _ballistics() -> DotWeaponBallistics:
	if def != null and def.tuning is DotWeaponBallistics:
		return def.tuning
	return null


func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var b := _ballistics()

	var damage := b.damage if b != null else tune_float(&"damage", 8.0)
	var reach := b.max_range if b != null else tune_float(&"max_range", 20.0)

	# Ramp is a fraction of full output at zero held ticks, reaching 1 after
	# `ramp_ticks`. Zero ramp_ticks means full output immediately.
	var ramp_ticks := tune_int(&"ramp_ticks", 0)
	if ramp_ticks > 0:
		var ramp_from := tune_float(&"ramp_from", 0.4)
		var t := clampf(float(ctx.held_ticks) / float(ramp_ticks), 0.0, 1.0)
		damage *= lerpf(ramp_from, 1.0, t)

	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_BEAM)

	var shot := DotShot.make(def.id, ctx.entity, ctx.tick, ctx.index)
	shot.origin = ctx.origin
	shot.direction = ctx.direction
	shot.damage = damage
	shot.max_range = reach
	shot.replayed = ctx.replayed
	shot.pellet_count = 1
	shot.spread = b.spread_for(ctx.speed, ctx.airborne, ctx.crouched) if b != null else 0.0

	if b != null:
		shot.damage_type = b.damage_type

	shot.scatter()
	out.add_shot(shot)

	return out


func _release(_ctx: DotWeaponContext) -> DotWeaponOutcome:
	# The beam stopping is worth announcing even though it produced nothing: a looping
	# sound and a particle stream both need an off switch, and a game that only listens
	# for uses never gets one.
	var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_BEAM)
	out.used = false
	out.add_event({"event": "beam_stopped", "weapon": String(def.id)})
	return out
