class_name DotWeaponFitting
extends RefCounted

## What is fitted to one weapon: mount -> attachment id. Ids only, so a server with none of
## the content can hold, validate (against its catalogue) and replicate it.

var weapon_id: StringName = &""

var _fitted: Dictionary = {}  ## StringName mount -> StringName attachment id


static func make(p_weapon_id: StringName) -> DotWeaponFitting:
	var f := DotWeaponFitting.new()
	f.weapon_id = p_weapon_id
	return f


func fit(mount: StringName, id: StringName) -> void:
	_fitted[mount] = id


func remove(mount: StringName) -> void:
	_fitted.erase(mount)


func attachment_on(mount: StringName) -> StringName:
	return _fitted.get(mount, &"")


## Mounts with something fitted, in text order (never sort(): interning order differs per process).
func mounts() -> Array[StringName]:
	var out: Array[StringName] = []
	for m: StringName in _fitted.keys():
		out.append(m)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Fitted attachment ids, in text order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m: StringName in _fitted.keys():
		out.append(_fitted[m])
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func is_empty() -> bool:
	return _fitted.is_empty()


func duplicate_fitting() -> DotWeaponFitting:
	var f := DotWeaponFitting.make(weapon_id)
	f._fitted = _fitted.duplicate()
	return f


## "mount=id,mount=id" in mount text order. Equal fittings have equal keys.
func key() -> String:
	var parts := PackedStringArray()
	for m in mounts():
		parts.append("%s=%s" % [String(m), String(_fitted[m])])
	return ",".join(parts)


func to_dictionary() -> Dictionary:
	var mounted: Dictionary = {}
	for m in mounts():
		mounted[String(m)] = String(_fitted[m])
	return {"weapon": String(weapon_id), "mounts": mounted}


## Strict: a value that is not a string is refused, not coerced. A wire payload is not trusted.
static func from_dictionary(d: Dictionary) -> DotResult:
	var weapon: Variant = d.get("weapon", "")
	var mounted: Variant = d.get("mounts", {})
	if not (weapon is String) or not (mounted is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "A fitting needs a weapon string and a mounts dictionary.")
	var f := DotWeaponFitting.make(StringName(weapon as String))
	for m: Variant in (mounted as Dictionary).keys():
		var id: Variant = (mounted as Dictionary)[m]
		if not (m is String) or not (id is String):
			return DotResult.fail(DotError.CODE_PARSE, "A fitting maps mount text to attachment id text.")
		f.fit(StringName(m as String), StringName(id as String))
	return DotResult.success(f)


func describe() -> Dictionary:
	return {"weapon": String(weapon_id), "key": key()}


func _to_string() -> String:
	return "DotWeaponFitting(%s: %s)" % [String(weapon_id), key()]
