@tool
class_name DotWeaponAttachment
extends Resource

## One thing that can be fitted to a weapon: a scope, a suppressor, a grip, an extended
## magazine. A document, like [DotWeaponDef], so a server validates it with no content.
##
## [b]An attachment changes numbers, never behaviour.[/b] It scales and adds to fields of
## the definition (or of its tuning) and sets params the presentation reads. What it looks
## like is not here: a view or world model puts a model on the socket named by [member mount].

const MOUNT_OPTIC := &"optic"
const MOUNT_MUZZLE := &"muzzle"
const MOUNT_UNDERBARREL := &"underbarrel"
const MOUNT_SIDE := &"side"
const MOUNT_MAGAZINE := &"magazine"

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Which mount point of a weapon this goes on. Any name; the constants are the common ones.
@export var mount: StringName = &""

## Fits a weapon carrying any of these tags. With [member fits_weapons], both empty means
## it fits every weapon that has the mount.
@export var fits_tags: Array[StringName] = []

## Fits these weapon ids.
@export var fits_weapons: Array[StringName] = []

## Field name -> multiplier. Applied first. A field resolves on the definition, then on its tuning.
@export var scale: Dictionary = {}

## Field name -> amount added after scaling.
@export var add: Dictionary = {}

@export var tags_added: Array[StringName] = []

## Merged into the definition's params (a zoom the presentation reads, say).
@export var params_set: Dictionary = {}


## Whether this can go on [param def]: the weapon has the mount, and the fit lists allow it.
func fits(def: DotWeaponDef) -> bool:
	if def == null or not def.mounts.has(mount):
		return false
	if fits_tags.is_empty() and fits_weapons.is_empty():
		return true
	if fits_weapons.has(def.id):
		return true
	for tag in fits_tags:
		if def.tags.has(tag):
			return true
	return false


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "An attachment needs an id.")
	var where := String(id)
	if mount == &"":
		return DotResult.fail(DotError.CODE_INVALID, "An attachment needs a mount.", where)
	for field: Variant in scale.keys():
		var m: Variant = scale[field]
		if not (m is float or m is int) or not is_finite(float(m)) or float(m) <= 0.0:
			return DotResult.fail(
				DotError.CODE_INVALID,
				"The multiplier for %s must be finite and above zero." % str(field), where
			)
	for field: Variant in add.keys():
		var a: Variant = add[field]
		if not (a is float or a is int) or not is_finite(float(a)):
			return DotResult.fail(
				DotError.CODE_INVALID, "The addition for %s must be finite." % str(field), where
			)
	return DotResult.success(null)


## Applies this to [param def], MUTATING it. [method DotWeaponAttachments.apply] hands it a
## deep copy; never pass a definition from a catalogue.
##
## An unknown or non-numeric field fails (a typo that silently did nothing would ship as a
## suppressor that is not quiet). Whole-number fields round; a count never goes below zero,
## and a magazine that held rounds keeps at least one.
func apply_to(def: DotWeaponDef) -> DotResult:
	var fields: Array[String] = []
	for key: Variant in scale.keys():
		if not fields.has(str(key)):
			fields.append(str(key))
	for key: Variant in add.keys():
		if not fields.has(str(key)):
			fields.append(str(key))
	# Text order, so two machines apply the same sequence.
	fields.sort_custom(func(a: String, b: String) -> bool: return a < b)

	for field in fields:
		var target: Object = _owner_of(def, field)
		if target == null:
			return DotResult.fail(
				DotError.CODE_INVALID,
				"%s changes %s, which is not a number on %s or its tuning." % [
					String(id), field, String(def.id)
				],
				String(id)
			)
		var name := StringName(field)
		var before: Variant = target.get(name)
		var value := float(before)
		value *= float(scale.get(field, scale.get(name, 1.0)))
		value += float(add.get(field, add.get(name, 0.0)))
		if before is int:
			var n := maxi(0, int(round(value)))
			if field == "magazine" and target == def and int(before) > 0:
				n = maxi(1, n)
			target.set(name, n)
		else:
			target.set(name, value)

	for tag in tags_added:
		if not def.tags.has(tag):
			def.tags.append(tag)
	for key: Variant in params_set.keys():
		def.params[key] = params_set[key]
	return DotResult.success(def)


func _owner_of(def: DotWeaponDef, field: String) -> Object:
	for candidate: Object in [def, def.tuning]:
		if candidate == null:
			continue
		for prop: Dictionary in candidate.get_property_list():
			if prop["name"] == field and int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
				var v: Variant = candidate.get(StringName(field))
				if v is int or v is float:
					return candidate
	return null


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name if display_name != "" else String(id),
		"mount": String(mount),
		"fits_tags": fits_tags.map(func(t: StringName) -> String: return String(t)),
		"fits_weapons": fits_weapons.map(func(t: StringName) -> String: return String(t)),
		"scale": scale,
		"add": add,
	}


func _to_string() -> String:
	return "DotWeaponAttachment(%s on %s)" % [String(id), String(mount)]
