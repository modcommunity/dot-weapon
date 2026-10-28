class_name DotWeaponMuzzle
extends RefCounted

## Muzzle flash for a weapon, on dot-fx's `DotMuzzleFlash`, reached by path so this addon parses without dot-fx.
##
## A weapon's profile picks the size with `extra: {muzzle_flash: big|medium|small|very_small|none}`, which lands in [member DotWeaponDef.params]; absent, the category decides. A headless server builds nothing.

const SCRIPT_PATH := "res://addons/dot_fx/runtime/dot_muzzle_flash.gd"
const KEY := "muzzle_flash"

## Flashes built ahead by [method warm], keyed by size and view, waiting for [method attach].
static var _spares := {}


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
	var key := _key(size, first_person)
	var spare: Variant = _spares.get(key)
	_spares.erase(key)
	var flash: Node3D = null
	if spare != null and is_instance_valid(spare):
		# A spare outlives its host (static), so a scene change frees it: typing it before the check errors.
		flash = spare
		# Warmed under the node it is attached to: moving a built flash re-enters its whole subtree, which costs as much as building it.
		flash.process_mode = Node.PROCESS_MODE_INHERIT
		if flash.get_parent() == parent:
			return flash
		if flash.get_parent() != null:
			flash.get_parent().remove_child(flash)
	else:
		flash = script.new()
		flash.set("size", size)
		flash.set("first_person", first_person)
	parent.add_child(flash)
	return flash


## Starts building a flash for [param category] under [param host] (put the node [method attach] will get as its parent, in the tree, under the loading cover; a flash warmed elsewhere is moved, which re-enters it): its pool fills one instance a frame, and the next [method attach] for the same size and view takes it, so the first shot builds nothing. False with no dot-fx, no display or a size of none.
static func warm(
	host: Node, category: String, def: DotWeaponDef = null,
	first_person: bool = false, suppressed: bool = false
) -> bool:
	if host == null or not ResourceLoader.exists(SCRIPT_PATH):
		return false
	var script: GDScript = load(SCRIPT_PATH)
	if not script.call("available"):
		return false
	var size: int = script.call("size_for", category, {KEY: flash_name(def)}, suppressed)
	if size == 0:
		return false
	var key := _key(size, first_person)
	if _spares.has(key) and is_instance_valid(_spares[key]):
		return true
	var flash: Node3D = script.new()
	flash.set("size", size)
	flash.set("first_person", first_person)
	flash.set("variant", 1 + (hash(key) % 6))
	# The host may be a node a load gate froze (disabled): an inheriting flash would never build its pool.
	flash.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(flash)
	_spares[key] = flash
	return true


## True once every flash [method warm] started has its pool built.
static func warm_done() -> bool:
	for flash: Variant in _spares.values():
		if is_instance_valid(flash) and not bool(flash.call("is_ready")):
			return false
	return true


## How many warmed flashes wait for an [method attach].
static func spare_count() -> int:
	return _spares.size()


static func _key(size: int, first_person: bool) -> String:
	return "%d/%s" % [size, first_person]


## Plays one flash; false when [param flash] is null or skipped.
static func fire(flash: Node3D) -> bool:
	return flash != null and is_instance_valid(flash) and bool(flash.call("fire"))
