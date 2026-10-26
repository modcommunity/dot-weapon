class_name DotWeaponProfileGroup
extends DotProfileSet

## Every pack's `weapon` profiles behind the one kind, sharing one runtime layer.
## [DotProfileRuntime] keys a set by kind, so packs cannot each register `weapon`; ids stay bare and an edit lands in [member DotProfileSet.runtime], which every member set reads.

var _members: Array[DotProfileSet] = []


## A group for [param p_game]; [param p_roots] replaces the config roots (tests).
static func make(p_game: String, p_roots: PackedStringArray = PackedStringArray()) -> DotWeaponProfileGroup:
	var g := new()
	g.game = p_game
	g.rel_path = DotWeaponProfiles.KIND
	g.schema = DotWeaponProfiles.schema()
	g.roots = p_roots
	return g


## The member set of [param addon], made on first use.
func add_pack(addon: String) -> DotProfileSet:
	for m in _members:
		if m.addon_name == addon:
			return m
	var m := DotWeaponProfiles.make_set(addon, game, roots, runtime)
	_members.append(m)
	return m


## The profile id a definition id belongs to: the same id, else the one it ends with (`zz_m4` is `m4`); "" if none.
func profile_for(def_id: String) -> String:
	var ids := list_ids()
	if ids.has(def_id):
		return def_id
	var best := ""
	for id in ids:
		if def_id.ends_with("_" + id) and id.length() > best.length():
			best = id
	return best


func list_ids() -> PackedStringArray:
	var seen := {}
	for m in _members:
		for id in m.list_ids():
			seen[id] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


func has_id(id: String) -> bool:
	return _owner_of(id) != null


func load_profile(id: String) -> DotResult:
	var m := _owner_of(id)
	if m == null:
		return DotResult.fail(DotError.CODE_INVALID, "%s/%s: no such profile" % [rel_path, id])
	return m.load_profile(id)


func check_edit(id: String, path: String, value: Variant) -> DotResult:
	var m := _owner_of(id)
	if m == null:
		return DotResult.fail(DotError.CODE_INVALID, "%s: no such profile" % id)
	return m.check_edit(id, path, value)


func clear_cache() -> void:
	super.clear_cache()
	for m in _members:
		m.clear_cache()


func set_runtime(id: String, paths: Dictionary) -> void:
	super.set_runtime(id, paths)
	for m in _members:
		m.clear_cache()


func _owner_of(id: String) -> DotProfileSet:
	for m in _members:
		if m.has_id(id):
			return m
	return null
