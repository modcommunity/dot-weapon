@tool
class_name DotWeaponCatalogue
extends Resource

## Every weapon a game knows, as one table a server can check at boot.
##
## [b]Validating the table is a headless operation.[/b] `validate()` loads no script,
## reads no scene and draws nothing, so a dedicated server with none of the content
## installed still catches a weapon with no id, a duplicate id or a bad charge time at
## startup, which is the only moment anybody is watching. Resolving a behaviour is the
## separate, later question [method instantiate] asks.
##
## [b]Scripts are cached per path, instances are not shared.[/b] Loading the same
## script twice is wasted work; handing the same behaviour instance to two players is a
## bug that shows up as one player's bow charging when the other draws.

@export var weapons: Array[DotWeaponDef] = []

## Behaviour scripts already loaded, keyed by path.
var _scripts: Dictionary = {}

## Definitions by id, built by [method index].
var _by_id: Dictionary = {}

## Definition ids by slot, built by [method index].
var _by_slot: Dictionary = {}

var _indexed: bool = false


# --- Building ---------------------------------------------------------------

func add(def: DotWeaponDef) -> DotWeaponCatalogue:
	weapons.append(def)
	_indexed = false
	return self


## Builds the id and slot lookups. Called for you by [method validate] and by the
## accessors; call it yourself after mutating [member weapons] directly.
func index() -> void:
	_by_id.clear()
	_by_slot.clear()

	for def in weapons:
		if def == null or def.id == &"":
			continue
		_by_id[def.id] = def
		if not _by_slot.has(def.slot):
			_by_slot[def.slot] = [] as Array[StringName]
		var ids: Array = _by_slot[def.slot]
		ids.append(def.id)

	_indexed = true


func _ensure_indexed() -> void:
	if not _indexed:
		index()


# --- Queries ----------------------------------------------------------------

func has(id: StringName) -> bool:
	_ensure_indexed()
	return _by_id.has(id)


func get_def(id: StringName) -> DotWeaponDef:
	_ensure_indexed()
	return _by_id.get(id, null)


func ids() -> Array[StringName]:
	_ensure_indexed()
	var out: Array[StringName] = []
	for key: StringName in _by_id.keys():
		out.append(key)
	out.sort()
	return out


## Every weapon in one slot, in the order they were added.
func ids_in_slot(slot: int) -> Array[StringName]:
	_ensure_indexed()
	var out: Array[StringName] = []
	for id: StringName in _by_slot.get(slot, []):
		out.append(id)
	return out


## Every weapon carrying [param tag].
##
## Tags rather than ids is how a mode says "no explosives" without naming a weapon; see
## [member DotWeaponDef.tags].
func ids_with_tag(tag: StringName) -> Array[StringName]:
	_ensure_indexed()
	var out: Array[StringName] = []
	for id: StringName in ids():
		var def: DotWeaponDef = _by_id[id]
		if def.has_tag(tag):
			out.append(id)
	return out


func size() -> int:
	return weapons.size()


# --- Behaviours -------------------------------------------------------------

## Builds a fresh behaviour for [param id], bound to its definition.
##
## [b]This is where the path is resolved[/b], and where a weapon delivered in a content
## pack that has not been mounted fails — by name, with the path in the message, rather
## than as a null somewhere later.
func instantiate(id: StringName, arsenal: Object = null) -> DotResult:
	var def := get_def(id)
	if def == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "No weapon called %s." % String(id)
		)

	var script_res := _script_for(def)
	if not script_res.ok:
		return script_res

	var script: Script = script_res.value
	var made: Variant = script.new()

	if not (made is DotWeaponBehaviour):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s does not extend DotWeaponBehaviour." % def.behaviour_path,
			String(id)
		)

	var behaviour: DotWeaponBehaviour = made
	behaviour.setup(def, arsenal)
	return DotResult.success(behaviour)


func _script_for(def: DotWeaponDef) -> DotResult:
	if _scripts.has(def.behaviour_path):
		return DotResult.success(_scripts[def.behaviour_path])

	if not ResourceLoader.exists(def.behaviour_path):
		return DotResult.fail(
			DotError.CODE_IO,
			"No script at %s. A weapon delivered in a content pack needs that pack "
			% def.behaviour_path + "mounted before the weapon can be built.",
			String(def.id)
		)

	var loaded: Variant = load(def.behaviour_path)
	if not (loaded is Script):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s is not a script." % def.behaviour_path,
			String(def.id)
		)

	_scripts[def.behaviour_path] = loaded
	return DotResult.success(loaded)


## Drops the script cache. For an editor tool or a test that reloads content.
func forget_scripts() -> void:
	_scripts.clear()


# --- Validation -------------------------------------------------------------

## Checks every row and the table as a whole, without loading a behaviour.
func validate() -> DotResult:
	index()

	var seen: Dictionary = {}

	for i in range(weapons.size()):
		var def := weapons[i]

		if def == null:
			return DotResult.fail(
				DotError.CODE_INVALID, "Entry %d is null." % i
			)

		var res := def.validate()
		if not res.ok:
			return res

		if seen.has(def.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Two weapons share the id %s. An id is what a loadout names, so a "
				% String(def.id) + "duplicate silently gives a player the wrong one.",
				String(def.id)
			)

		seen[def.id] = true

	return DotResult.success(null)


## Checks that every behaviour actually resolves. Loads scripts, so it is not the boot
## check; run it once after content is mounted.
func validate_behaviours() -> DotResult:
	for def in weapons:
		if def == null:
			continue
		var res := _script_for(def)
		if not res.ok:
			return res
	return DotResult.success(null)


func describe() -> Dictionary:
	_ensure_indexed()
	return {
		"weapons": weapons.size(),
		"slots": _by_slot.keys().size(),
		"ids": ids().map(func(i: StringName) -> String: return String(i)),
	}


func describe_lines() -> PackedStringArray:
	_ensure_indexed()
	var out := PackedStringArray()
	out.append("weapons: %d" % weapons.size())
	for id in ids():
		var def: DotWeaponDef = _by_id[id]
		out.append("  %-18s slot %d  %s" % [
			String(id), def.slot, DotWeaponDef.Fire.keys()[def.fire_mode]
		])
	return out
