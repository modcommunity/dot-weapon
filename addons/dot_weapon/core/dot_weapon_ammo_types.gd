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
		f.call("penetration", "float", 0.0, {"min": 0.0, "max": 100.0}),
		f.call("max_depth", "float", 1.0, {"min": 0.01, "max": 20.0}),
		f.call("materials", "string", ""),
		f.call("default_resistance", "float", 1.0, {"min": 0.0, "max": 1000.0}),
		f.call("body_cost", "float", 0.1, {"min": 0.0, "max": 100.0}),
		f.call("body_zones", "string", ""),
		f.call("min_damage", "float", 0.0, {"min": 0.0, "max": 1.0}),
		f.call("max_passes", "int", 4, {"min": 0, "max": 32}),
		f.call("ricochet_materials", "string", ""),
		f.call("ricochet_angle", "float", 0.0, {"min": 0.0, "max": 90.0}),
		f.call("ricochet_keep", "float", 0.6, {"min": 0.0, "max": 1.0}),
		f.call("guns", "string", ""),
		f.call("default", "bool", false),
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
			var d := (res.value as DotProfile).to_dictionary()
			add(DotWeaponAmmoType.from_flat(StringName(id), d.get("values", d)))
			n += 1
	return n


func add(t: DotWeaponAmmoType) -> void:
	_types[t.id] = t


## The type for [param id], or null (no change to the bullet).
func get_type(id: StringName) -> DotWeaponAmmoType:
	return _types.get(id) as DotWeaponAmmoType


## The type [param weapon_id] fires when no round is loaded: one whose `guns` lists it, else the `default` one, else null.
func type_for_weapon(weapon_id: StringName) -> DotWeaponAmmoType:
	var fallback: DotWeaponAmmoType = null
	for id in ids():
		var t := _types[id] as DotWeaponAmmoType
		if t.guns.has(String(weapon_id)):
			return t
		if t.is_default and fallback == null:
			fallback = t
	return fallback


## Ids in text order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _types:
		out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
