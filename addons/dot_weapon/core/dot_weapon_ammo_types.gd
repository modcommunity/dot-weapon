class_name DotWeaponAmmoTypes
extends RefCounted

## The ammo types of a game, from `ammo` profiles (kind [constant KIND]). A weapon names its loaded round
## through [method DotWeaponArsenal.load_ammo]; an id not listed here changes nothing.

const KIND := "ammo"

var _types: Dictionary = {}


static func schema() -> Array:
	var f := DotProfileSet.field
	return [
		f.call("name", "string", ""),
		f.call("damage", "float", 1.0, {"min": 0.0, "max": 100.0}),
		f.call("velocity", "float", 1.0, {"min": 0.0, "max": 100.0}),
		f.call("drag", "float", 1.0, {"min": 0.0, "max": 100.0}),
		f.call("armour_pierce", "float", 0.0, {"min": 0.0, "max": 1.0}),
	]


## Kind to schema, for dot-core's `profile_check`.
static func profile_schemas() -> Dictionary:
	return {KIND: {"schema": schema()}}


static func make_set(addon: String, game: String, roots: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	var s := DotProfileSet.create(addon, game, KIND, schema())
	s.roots = roots
	return s


## Every profile of [param profiles] as a type; returns how many loaded.
func load_set(profiles: DotProfileSet) -> int:
	var n := 0
	for id in profiles.list_ids():
		var res := profiles.load_profile(id)
		if res.ok:
			add(DotWeaponAmmoType.from_flat(StringName(id), (res.value as DotProfile).to_dictionary()))
			n += 1
	return n


func add(t: DotWeaponAmmoType) -> void:
	_types[t.id] = t


## The type for [param id], or null (no change to the bullet).
func get_type(id: StringName) -> DotWeaponAmmoType:
	return _types.get(id) as DotWeaponAmmoType


## Ids in text order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _types:
		out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
