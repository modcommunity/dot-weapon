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
##
## [b]Two sources, one table.[/b] [member weapons] holds what code registered ([method add]),
## which is the whole table in a build that ships its content. [method follow_content] adds
## weapons a mounted content pack delivered, read from a [DotContentIndex], and only those of
## the index's [i]current session[/i]: a solo (Workshop) weapon is invisible in an online
## session because the index hides it, so a server that never followed anything and a client
## that did agree on what exists. Every query below answers over both.
##
## [b]Code wins an id.[/b] A delivered weapon whose id a code weapon already has is refused
## and logged, never substituted: a loadout names ids, and a subscription must not be able
## to replace the weapon a game balanced.

const CHANNEL := "dot.weapon.catalogue"

## The index kind a weapon pack's entries carry.
const KIND := &"weapon"

## A weapon became visible (registered, or delivered in the current session).
signal weapon_added(listing: DotWeaponListing)

## (Not `changed`: Resource already has one, for the editor.)
## The visible set changed in any way, including a session switch hiding solo weapons. A
## menu rebuilds from [method listings] on this.
signal listings_changed

## Weapons registered from code. Delivered ones are not in here; see [method listings].
@export var weapons: Array[DotWeaponDef] = []

## Menu data for code weapons, by id: {category, icon}.
var _code_meta: Dictionary = {}

var _index: DotContentIndex = null

## Delivered rows that loaded, by entry key.
var _delivered: Dictionary = {}

## Entry keys refused once, so a rebuild does not log the same bad row again.
var _rejected: Dictionary = {}

## Entry keys visible in the index's current session, in index order.
var _visible_keys: Array[String] = []

## Behaviour scripts already loaded, keyed by path.
var _scripts: Dictionary = {}

## Definitions by id, built by [method index].
var _by_id: Dictionary = {}

## Definition ids by slot, built by [method index].
var _by_slot: Dictionary = {}

var _indexed: bool = false


# --- Building ---------------------------------------------------------------

## Registers a weapon from code. [param category] and [param icon_path] are menu data only
## and optional; a game that never builds a menu passes neither.
func add(
	def: DotWeaponDef, category: String = "", icon_path: String = ""
) -> DotWeaponCatalogue:
	weapons.append(def)
	_indexed = false
	if def != null and def.id != &"":
		_code_meta[def.id] = {"category": category, "icon": icon_path}
		weapon_added.emit(_code_listing(def))
		listings_changed.emit()
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

	# Delivered rows after code ones, so an id clash resolves to the code weapon (see the class
	# comment) and a delivered slot list keeps code weapons first.
	for key in _visible_keys:
		var listing: DotWeaponListing = _delivered.get(key, null)
		if listing == null or _by_id.has(listing.id):
			continue
		_by_id[listing.id] = listing.def
		if not _by_slot.has(listing.slot):
			_by_slot[listing.slot] = [] as Array[StringName]
		var slot_ids: Array = _by_slot[listing.slot]
		slot_ids.append(listing.id)

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


## Every id, in text order.
func ids() -> Array[StringName]:
	_ensure_indexed()
	var out: Array[StringName] = []
	for key: StringName in _by_id.keys():
		out.append(key)
	# By the id's text. sort() on StringNames orders them by where each was interned, which
	# differs per process, so a list another program shows (a console's completion) or
	# compares (a pack's own id list) was in no stable order.
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
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


## How many weapons are visible: code ones plus delivered ones in the current session.
func size() -> int:
	_ensure_indexed()
	return weapons.size() + _visible_delivered().size()


# --- Content packs ----------------------------------------------------------

## Starts following [param index] (default [method DotContentIndex.shared]): weapon entries
## of packs mounted for the index's current session become part of this catalogue now and as
## packs are mounted later. Order does not matter, so a catalogue built before the first
## mount and one built after it see the same table. Safe to call twice; the second call
## replaces the first.
func follow_content(index: DotContentIndex = null) -> DotWeaponCatalogue:
	unfollow_content()
	_index = index if index != null else DotContentIndex.shared()
	_index.pack_added.connect(_on_pack_added)
	_index.session_changed.connect(_on_session_changed)
	_refresh()
	return self


## Stops following. Delivered weapons are forgotten; code weapons stay.
func unfollow_content() -> void:
	if _index != null:
		if _index.pack_added.is_connected(_on_pack_added):
			_index.pack_added.disconnect(_on_pack_added)
		if _index.session_changed.is_connected(_on_session_changed):
			_index.session_changed.disconnect(_on_session_changed)
	_index = null
	var had := not _visible_keys.is_empty()
	_delivered.clear()
	_rejected.clear()
	_visible_keys.clear()
	_indexed = false
	if had:
		listings_changed.emit()


func _on_pack_added(_pack: Dictionary, _entries: Array[DotContentEntry]) -> void:
	_refresh()


func _on_session_changed(_session: StringName) -> void:
	_refresh()


## Rebuilds the visible delivered set from the index and announces what is new. Idempotent.
func _refresh() -> void:
	if _index == null:
		return
	var before := _visible_keys.duplicate()
	var next: Array[String] = []
	var added: Array[DotWeaponListing] = []

	for entry in _index.entries(KIND):
		var listing: DotWeaponListing = _delivered.get(entry.key, null)
		if listing == null:
			if _rejected.has(entry.key):
				continue
			var made := _load_entry(entry)
			if not made.ok:
				_rejected[entry.key] = true
				DotLog.warn(CHANNEL, "refused a delivered weapon", {
					"key": entry.key, "why": made.error.message,
				})
				continue
			listing = made.value
			_delivered[entry.key] = listing
		next.append(entry.key)
		if not before.has(entry.key):
			added.append(listing)

	_visible_keys = next
	_indexed = false
	if next == before:
		return
	for listing in added:
		weapon_added.emit(listing)
	listings_changed.emit()


## Turns one index entry into a listing, or says why it cannot be one.
func _load_entry(entry: DotContentEntry) -> DotResult:
	var def_path := entry.path("def")
	if def_path == "":
		return DotResult.fail(DotError.CODE_INVALID, "Weapon entry %s names no `def`." % entry.key)
	if not ResourceLoader.exists(def_path):
		return DotResult.fail(DotError.CODE_IO, "No definition at %s." % def_path)
	var def := load(def_path) as DotWeaponDef
	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "%s is not a DotWeaponDef." % def_path)
	if String(def.id) != entry.id:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s has id %s but its entry is %s. A loadout names one id, so they must match."
			% [def_path, String(def.id), entry.id]
		)
	var checked := def.validate()
	if not checked.ok:
		return checked
	if _code_has(def.id):
		return DotResult.fail(
			DotError.CODE_CONFLICT,
			"%s is already a weapon registered from code; code wins." % String(def.id)
		)

	var l := DotWeaponListing.new()
	l.id = def.id
	l.def = def
	l.display_name = entry.name if entry.name != "" else def.name_or_id()
	l.category = entry.category
	l.icon_path = entry.path("thumbnail")
	l.def_path = def_path
	l.slot = def.slot
	l.tags = entry.tags
	l.meta = entry.meta
	l.source = entry.source
	l.content_id = entry.content_id
	l.version = entry.version
	l.pack_title = entry.pack_title
	l.entry_key = entry.key
	return DotResult.success(l)


func _code_has(id: StringName) -> bool:
	for def in weapons:
		if def != null and def.id == id:
			return true
	return false


func _visible_delivered() -> Array[DotWeaponListing]:
	var out: Array[DotWeaponListing] = []
	var seen: Dictionary = {}
	for key in _visible_keys:
		var l: DotWeaponListing = _delivered.get(key, null)
		# Two packs delivering one id: the first mounted keeps it.
		if l != null and not seen.has(l.id):
			seen[l.id] = true
			out.append(l)
	return out


func _code_listing(def: DotWeaponDef) -> DotWeaponListing:
	var meta: Dictionary = _code_meta.get(def.id, {})
	var l := DotWeaponListing.new()
	l.id = def.id
	l.def = def
	l.display_name = def.name_or_id()
	l.category = str(meta.get("category", ""))
	l.icon_path = str(meta.get("icon", ""))
	l.slot = def.slot
	l.tags = PackedStringArray(def.tags)
	return l


# --- Menu queries -----------------------------------------------------------

## Every visible weapon as a menu row: code weapons in the order added, then delivered ones
## in mount order. Pass [param category] to keep one group.
func listings(category: String = "") -> Array[DotWeaponListing]:
	var out: Array[DotWeaponListing] = []
	var seen: Dictionary = {}
	for def in weapons:
		if def == null or def.id == &"" or seen.has(def.id):
			continue
		seen[def.id] = true
		out.append(_code_listing(def))
	for l in _visible_delivered():
		if not seen.has(l.id):
			seen[l.id] = true
			out.append(l)
	if category == "":
		return out
	return out.filter(func(l: DotWeaponListing) -> bool: return l.category == category)


## The row for [param id], or null.
func listing(id: StringName) -> DotWeaponListing:
	_ensure_indexed()
	for l in listings():
		if l.id == id:
			return l
	return null


## The categories in use, in text order ("" is a real category: weapons with none).
func categories() -> PackedStringArray:
	var seen: Dictionary = {}
	for l in listings():
		seen[l.category] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


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
		"weapons": size(),
		"delivered": _visible_keys.size(),
		"session": String(_index.session()) if _index != null else "",
		"slots": _by_slot.keys().size(),
		"ids": ids().map(func(i: StringName) -> String: return String(i)),
	}


func describe_lines() -> PackedStringArray:
	_ensure_indexed()
	var out := PackedStringArray()
	out.append("weapons: %d (%d delivered%s)" % [
		size(), _visible_delivered().size(),
		", following session %s" % String(_index.session()) if _index != null else "",
	])
	for id in ids():
		var def: DotWeaponDef = _by_id[id]
		var l := listing(id)
		out.append("  %-18s slot %d  %-6s %s%s" % [
			String(id), def.slot, DotWeaponDef.Fire.keys()[def.fire_mode],
			l.category if l != null else "",
			"  <- %s" % l.content_id if l != null and l.is_delivered() else "",
		])
	return out
