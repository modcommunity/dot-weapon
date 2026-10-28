class_name DotWeaponHitzones
extends RefCounted

## Armour per hit zone ([DotHitGroup] name), applied by [DotWeaponBulletBridge]; dot-combat's group multipliers still apply.
## A helmet is `{"head": 0.5}`. [member presence_fn] (`func(entity) -> float`, 0..1) says how much the victim wears;
## unset means all of it. Unlisted zones carry no armour.

var armour: Dictionary = {}
var presence_fn: Callable = Callable()


func set_armour(group: StringName, value: float) -> void:
	armour[group] = clampf(value, 0.0, 1.0)


## Profile-style loading: `{"head": 0.5, ...}`.
static func from_flat(c: Dictionary) -> DotWeaponHitzones:
	var z := DotWeaponHitzones.new()
	for k in c:
		z.set_armour(StringName(str(k)), float(c[k]))
	return z


## Damage multiplier for a hit in [param group] on [param entity] by a round piercing [param pierce].
func multiplier(group: StringName, entity: Node, pierce: float = 0.0) -> float:
	var a := float(armour.get(group, 0.0))
	if a <= 0.0:
		return 1.0
	if presence_fn.is_valid():
		a *= clampf(float(presence_fn.call(entity)), 0.0, 1.0)
	return 1.0 - a * (1.0 - clampf(pierce, 0.0, 1.0))
