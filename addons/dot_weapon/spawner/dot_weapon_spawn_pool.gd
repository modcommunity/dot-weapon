class_name DotWeaponSpawnPool
extends RefCounted

## What a spawner may hand out: weighted entries (an id, a kind, tags, free data), drawn through a tag filter.
## An entry id is any string a game's catalogue knows; [member kind] is only what the game does with it.
## A filter is `{tags_any, tags_all, tags_none, ids}`, each a list of strings; an absent key allows everything.

## The pool's name in the config.
var id: StringName = &""
## The kind an entry gets when it names none (`weapon`, `ammo`, `trader`...).
var kind: StringName = &"weapon"
## A free label the game gives a pool (`channel:` in the config: where its items are offered, e.g. a shop or a crate); [member DotWeaponSpawnerConfig.weigher] is told it.
var channel: StringName = &""
## Each entry: `{id: StringName, kind: StringName, weight: float, tags: PackedStringArray, data: Dictionary}`.
var entries: Array[Dictionary] = []


## Appends an entry; a weight of zero or less never draws. Chainable.
func add(item: StringName, weight: float = 1.0, tags: PackedStringArray = PackedStringArray(), data: Dictionary = {}, p_kind: StringName = &"") -> DotWeaponSpawnPool:
	entries.append({"id": item, "kind": p_kind if p_kind != &"" else kind, "weight": weight, "tags": tags, "data": data})
	return self


## The entries [param filter] allows with a positive weight, in the order they were added.
func candidates(filter: Dictionary = {}) -> Array[Dictionary]:
	var any := _strs(filter.get("tags_any"))
	var all := _strs(filter.get("tags_all"))
	var none := _strs(filter.get("tags_none"))
	var ids := _strs(filter.get("ids"))
	var out: Array[Dictionary] = []
	for e in entries:
		if float(e["weight"]) <= 0.0:
			continue
		var tags: PackedStringArray = e["tags"]
		if not ids.is_empty() and not ids.has(String(e["id"])):
			continue
		if not any.is_empty() and not _shares(tags, any):
			continue
		if not _has_all(tags, all) or _shares(tags, none):
			continue
		out.append(e)
	return out


## The entry [param unit] (0 up to 1, from a seeded stream) lands on by weight; empty when the filter leaves nothing.
func pick(filter: Dictionary, unit: float) -> Dictionary:
	var pool := candidates(filter)
	var total := 0.0
	for e in pool:
		total += float(e["weight"])
	if pool.is_empty() or total <= 0.0:
		return {}
	var at := clampf(unit, 0.0, 0.9999999) * total
	for e in pool:
		at -= float(e["weight"])
		if at < 0.0:
			return e
	return pool[pool.size() - 1]


## Builds a pool from its config mapping (entries end up in id order, so layering order never changes a draw): `kind`, `channel`, `entries` (list of `{id, weight, tags, data, kind}`) and an optional `catalogue` block that adds every def of [param defs] (`DotWeaponDef`s) whose tags match `{tags_any, tags_none, weight, weights: {id: w}}`. An explicit entry replaces a catalogue one of the same id. [param weigher] `(channel, id, weight) -> weight` lets the game re-weigh every entry (0 removes it).
static func from_dictionary(pool_id: StringName, d: Dictionary, defs: Array = [], weigher: Callable = Callable()) -> DotResult:
	var pool := DotWeaponSpawnPool.new()
	pool.id = pool_id
	pool.kind = StringName(str(d.get("kind", "weapon")))
	pool.channel = StringName(str(d.get("channel", "")))
	var by_id := {}
	var cat: Variant = d.get("catalogue")
	if cat is Dictionary:
		var cd := cat as Dictionary
		var any := _strs(cd.get("tags_any"))
		var none := _strs(cd.get("tags_none"))
		var weights: Dictionary = cd.get("weights", {}) if cd.get("weights") is Dictionary else {}
		for def: Variant in defs:
			var tags := PackedStringArray()
			for t: Variant in def.get("tags"):
				tags.append(String(t))
			if (not any.is_empty() and not _shares(tags, any)) or _shares(tags, none):
				continue
			var item := String(def.get("id"))
			by_id[item] = {"id": StringName(item), "kind": pool.kind, "weight": float(weights.get(item, cd.get("weight", 1.0))), "tags": tags, "data": {}}
	var raw: Variant = d.get("entries", [])
	if not (raw is Array):
		return DotResult.fail(DotError.CODE_INVALID, "pool '%s': entries must be a list" % pool_id)
	for e: Variant in raw as Array:
		if not (e is Dictionary) or str((e as Dictionary).get("id", "")) == "":
			return DotResult.fail(DotError.CODE_INVALID, "pool '%s': an entry needs an id" % pool_id)
		var ed := e as Dictionary
		var item := str(ed["id"])
		by_id[item] = {"id": StringName(item), "kind": StringName(str(ed.get("kind", pool.kind))), "weight": float(ed.get("weight", 1.0)), "tags": _strs(ed.get("tags")), "data": ed.get("data", {}) if ed.get("data") is Dictionary else {}}
	var ids := by_id.keys()
	ids.sort()
	for item: Variant in ids:
		var entry: Dictionary = by_id[item]
		if weigher.is_valid():
			entry["weight"] = float(weigher.call(pool.channel, entry["id"], float(entry["weight"])))
		pool.entries.append(entry)
	return DotResult.success(pool)


## A list in any of the shapes a file or a marker gives one: an array, a packed array, or `"a, b"`.
static func _strs(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is String or v is StringName:
		for part in String(v).split(",", false):
			out.append(part.strip_edges())
	elif v is Array or v is PackedStringArray:
		for x: Variant in v:
			out.append(String(x).strip_edges())
	return out


static func _shares(a: PackedStringArray, b: PackedStringArray) -> bool:
	for x in b:
		if a.has(x):
			return true
	return false


static func _has_all(a: PackedStringArray, b: PackedStringArray) -> bool:
	for x in b:
		if not a.has(x):
			return false
	return true
