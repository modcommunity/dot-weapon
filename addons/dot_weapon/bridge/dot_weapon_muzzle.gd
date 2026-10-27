class_name DotWeaponMuzzle
extends RefCounted

## Muzzle flash for a weapon, on dot-fx's `DotMuzzleFlash`, reached by path so this addon parses without dot-fx.
##
## A weapon's profile picks the size with `extra: {muzzle_flash: big|medium|small|very_small|none}`, which lands in [member DotWeaponDef.params]; absent, the category decides. A headless server builds nothing.

const SCRIPT_PATH := "res://addons/dot_fx/runtime/dot_muzzle_flash.gd"
const KEY := "muzzle_flash"


## The profile's size name ("big", "none"...), or "" when the weapon does not say.
static func flash_name(def: DotWeaponDef) -> String:
	if def == null:
		return ""
	return str(def.params.get(KEY, ""))


## Builds a flash under [param parent] (a muzzle point or view-model node) and returns it, or null with no dot-fx, no display, or a size of none. Call [method fire] per shot.
static func attach(
	parent: Node3D, category: String, def: DotWeaponDef = null,
	first_person: bool = false, suppressed: bool = false
) -> Node3D:
	if parent == null or not ResourceLoader.exists(SCRIPT_PATH):
		return null
	var script: GDScript = load(SCRIPT_PATH)
	if not script.call("available"):
		return null
	var extra := {KEY: flash_name(def)}
	var size: int = script.call("size_for", category, extra, suppressed)
	if size == 0:
		return null
	var flash: Node3D = script.new()
	flash.set("size", size)
	flash.set("first_person", first_person)
	parent.add_child(flash)
	return flash


## Plays one flash; false when [param flash] is null or skipped.
static func fire(flash: Node3D) -> bool:
	return flash != null and is_instance_valid(flash) and bool(flash.call("fire"))
