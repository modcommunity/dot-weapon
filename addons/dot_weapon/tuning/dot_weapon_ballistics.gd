@tool
class_name DotWeaponBallistics
extends DotWeaponTuning

## Tuning for anything that sends damage down a line: a gun, a bow, a crossbow, a
## railgun, a thrown knife.
##
## Shipped because it is the tuning four of the five behaviours in this addon read, and
## because a game whose weapons are all guns should not have to invent it. A game whose
## weapons are not all guns writes its own [DotWeaponTuning] and this one goes unused.

@export_group("Damage")

## Damage one pellet does at full charge, before any rule dot-combat applies.
@export_range(0.0, 10000.0, 0.5, "or_greater") var damage: float = 20.0

## What kind of damage. Null lets dot-combat's default stand.
@export var damage_type: DotDamageType = null

## Damage at zero charge, as a fraction of [member damage].
##
## Only read by a [constant DotWeaponDef.Fire.CHARGE] weapon. A bow at half draw does
## not do half damage in most games that ship one; it does rather less, which is what
## makes holding the draw worth the vulnerability.
@export_range(0.0, 1.0, 0.01) var min_charge_damage: float = 0.25

## Metres past which it hits nothing.
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_range: float = 200.0

@export_group("Pattern")

## Projectiles per use. More than one is a shotgun.
@export_range(1, 64, 1) var pellets: int = 1

## Places the pellets on a ring rather than by hash, so the pattern is learnable.
@export var fixed_pattern: bool = false

@export_group("Accuracy")

## Cone half-angle standing still, in degrees.
@export_range(0.0, 45.0, 0.01) var spread: float = 0.5

## Cone half-angle at full speed.
@export_range(0.0, 45.0, 0.01) var spread_moving: float = 2.0

## The speed at which [member spread_moving] is reached, in metres per second.
##
## Below it the spread is interpolated. A fixed threshold makes a weapon that is
## perfectly accurate at 4.9 m/s and hopeless at 5.1, which players find and abuse.
@export_range(0.1, 100.0, 0.1, "or_greater") var spread_speed_ref: float = 6.0

## Cone half-angle off the ground.
@export_range(0.0, 45.0, 0.01) var spread_airborne: float = 4.0

## Multiplies the spread while crouched.
@export_range(0.0, 2.0, 0.01) var spread_crouched: float = 0.5

## Degrees added per use, and shed while not using.
@export_range(0.0, 10.0, 0.01) var bloom: float = 0.0

## The most bloom may add.
@export_range(0.0, 45.0, 0.1) var bloom_max: float = 5.0

## Degrees of bloom shed per tick.
@export_range(0.0, 10.0, 0.001) var bloom_recovery: float = 0.15

@export_group("Recoil")

## Degrees of upward kick per use.
@export_range(0.0, 20.0, 0.01) var recoil_pitch: float = 0.4

## Degrees of sideways kick per use. Alternates side to side.
@export_range(0.0, 20.0, 0.01) var recoil_yaw: float = 0.15

@export_group("Splash")

@export_range(0.0, 100.0, 0.1) var splash_radius: float = 0.0

@export_range(0.0, 10000.0, 0.5, "or_greater") var splash_damage: float = 0.0

@export var splash_type: DotDamageType = null

@export var splash_hurts_owner: bool = true

@export_group("Projectile")

## Metres per second at full charge. Only read by a behaviour that spawns something.
@export_range(1.0, 5000.0, 1.0, "or_greater") var speed: float = 60.0

## Metres per second at zero charge.
@export_range(0.0, 5000.0, 1.0, "or_greater") var min_speed: float = 20.0

## Gravity multiplier. 0 is a rocket, 1 is an arrow, higher is a lobbed grenade.
@export_range(0.0, 8.0, 0.05) var gravity_scale: float = 0.0

@export_range(0.0, 5.0, 0.01) var radius: float = 0.1

## Ticks before it expires on its own.
@export_range(1, 100000, 1) var life_ticks: int = 384


func validate() -> DotResult:
	if damage < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "damage cannot be negative.")

	if max_range <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "max_range must be positive.")

	if pellets < 1:
		return DotResult.fail(DotError.CODE_INVALID, "pellets must be at least 1.")

	if splash_radius > 0.0 and splash_damage <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A splash radius with no splash damage does nothing. Set both or neither."
		)

	if min_speed > speed:
		return DotResult.fail(
			DotError.CODE_INVALID, "min_speed is above speed."
		)

	return DotResult.success(null)


## The cone half-angle for a carrier in this posture, before bloom.
func spread_for(speed_now: float, airborne: bool, crouched: bool) -> float:
	if airborne:
		return spread_airborne

	var moving := clampf(speed_now / maxf(0.001, spread_speed_ref), 0.0, 1.0)
	var base := lerpf(spread, spread_moving, moving)

	return base * spread_crouched if crouched else base


## Damage at [param charge], between [member min_charge_damage] and full.
func damage_at(charge: float) -> float:
	return damage * lerpf(min_charge_damage, 1.0, clampf(charge, 0.0, 1.0))


## Launch speed at [param charge].
func speed_at(charge: float) -> float:
	return lerpf(min_speed, speed, clampf(charge, 0.0, 1.0))
