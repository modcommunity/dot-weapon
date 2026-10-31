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
## Metres of resistance-1 material a hitscan round crosses at full strength; 0 passes nothing.
var penetration: float = 0.0
## Farthest the round looks for the far side of a wall, in metres.
var max_depth: float = 1.0
## Resistance per surface material (power spent per metre).
var materials: Dictionary = {}
## Resistance of a material `materials` does not list.
var default_resistance: float = 1.0
## Power spent crossing a body, and a per-hit-group multiplier on it.
var body_cost: float = 0.1
var body_zones: Dictionary = {}
## Damage never falls below this share after a pass while power remains.
var min_damage: float = 0.0
var max_passes: int = 4
## Materials a shallow hit bounces off (comma list); needs `penetration` above 0 and the server's `sv_ricochet`.
var ricochet_materials: PackedStringArray = PackedStringArray()
## Largest angle from the surface, in degrees, that still bounces; 0 turns ricochet off for this round.
var ricochet_angle: float = 0.0
## Share of power a bounce keeps.
var ricochet_keep: float = 0.6
## Weapon ids this round is the default for (a profile can serve several guns).
var guns: PackedStringArray = PackedStringArray()
## The round every weapon that no profile lists uses.
var is_default: bool = false


## "wood:0.5,metal:4" to a dictionary of floats.
static func parse_map(text: String) -> Dictionary:
	var out := {}
	for part in text.split(",", false):
		var kv := part.split(":")
		if kv.size() == 2 and kv[1].strip_edges().is_valid_float():
			out[StringName(kv[0].strip_edges())] = kv[1].strip_edges().to_float()
	return out


static func from_flat(p_id: StringName, c: Dictionary) -> DotWeaponAmmoType:
	var t := DotWeaponAmmoType.new()
	t.id = p_id
	t.display_name = String(c.get("name", ""))
	t.damage = maxf(0.0, float(c.get("damage", 1.0)))
	t.velocity = maxf(0.0, float(c.get("velocity", 1.0)))
	t.drag = maxf(0.0, float(c.get("drag", 1.0)))
	t.armour_pierce = clampf(float(c.get("armour_pierce", 0.0)), 0.0, 1.0)
	t.penetration = maxf(0.0, float(c.get("penetration", 0.0)))
	t.max_depth = maxf(0.01, float(c.get("max_depth", 1.0)))
	t.materials = parse_map(String(c.get("materials", "")))
	t.default_resistance = maxf(0.0, float(c.get("default_resistance", 1.0)))
	t.body_cost = maxf(0.0, float(c.get("body_cost", 0.1)))
	t.body_zones = parse_map(String(c.get("body_zones", "")))
	t.min_damage = clampf(float(c.get("min_damage", 0.0)), 0.0, 1.0)
	t.max_passes = maxi(0, int(c.get("max_passes", 4)))
	for m in String(c.get("ricochet_materials", "")).split(",", false):
		t.ricochet_materials.append(m.strip_edges())
	t.ricochet_angle = clampf(float(c.get("ricochet_angle", 0.0)), 0.0, 90.0)
	t.ricochet_keep = clampf(float(c.get("ricochet_keep", 0.6)), 0.0, 1.0)
	for g in String(c.get("guns", "")).split(",", false):
		t.guns.append(g.strip_edges())
	t.is_default = bool(c.get("default", false))
	return t


## What a hitscan round of this type can pass through, for dot-combat's [code]DotShot.penetration[/code]. Null when it passes nothing.
func make_penetration() -> DotPenetration:
	if penetration <= 0.0:
		return null
	var p := DotPenetration.new()
	p.power = penetration
	p.max_depth = max_depth
	p.materials = materials
	p.default_resistance = default_resistance
	p.body_cost = body_cost
	p.body_zones = body_zones
	p.min_damage = min_damage
	p.max_passes = max_passes
	p.ricochet_materials = ricochet_materials
	p.ricochet_angle = ricochet_angle
	p.ricochet_keep = ricochet_keep
	return p


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
