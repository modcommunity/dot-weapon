class_name DotWeaponAmmoType
extends RefCounted

## One kind of round: multipliers over a weapon's own bullet, and how much armour it ignores. Only read
## while `sv_ballistics` is on, by [DotWeaponBulletBridge].

var id: StringName = &""
var display_name: String = ""
## Multiplies the shot's damage.
var damage: float = 1.0
## Multiplies muzzle velocity.
var velocity: float = 1.0
## Multiplies drag.
var drag: float = 1.0
## Share (0..1) of the victim's armour this round ignores.
var armour_pierce: float = 0.0


static func from_flat(p_id: StringName, c: Dictionary) -> DotWeaponAmmoType:
	var t := DotWeaponAmmoType.new()
	t.id = p_id
	t.display_name = String(c.get("name", ""))
	t.damage = maxf(0.0, float(c.get("damage", 1.0)))
	t.velocity = maxf(0.0, float(c.get("velocity", 1.0)))
	t.drag = maxf(0.0, float(c.get("drag", 1.0)))
	t.armour_pierce = clampf(float(c.get("armour_pierce", 0.0)), 0.0, 1.0)
	return t


## True when the round changes the bullet's flight (a copy of the tuning is needed).
func alters_flight() -> bool:
	return not is_equal_approx(velocity, 1.0) or not is_equal_approx(drag, 1.0)


## A copy of [param b] flown with this round's velocity and drag.
func apply_to(b: DotWeaponBallistics) -> DotWeaponBallistics:
	if not alters_flight():
		return b
	var out := b.duplicate() as DotWeaponBallistics
	out.muzzle_velocity *= velocity
	out.drag *= drag
	return out


func describe() -> Dictionary:
	return {"id": String(id), "damage": damage, "velocity": velocity, "drag": drag, "armour_pierce": armour_pierce}
