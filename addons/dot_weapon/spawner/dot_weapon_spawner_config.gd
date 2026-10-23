class_name DotWeaponSpawnerConfig
extends RefCounted

## The spawner's rules, layered: what pools exist, per-site defaults, groups, and what a map changes.
##
## [b]Two kinds of setting.[/b] The structure (pools, sites, groups) is `spawner.yml` in each `dot-weapon` tier of [DotAddonConfig]: `cfg/addons/dot_weapon/`, `cfg/game/<game>/dot_weapon/`, then the operator's `cfg/server/...` copies, merged weakest first. A top-level `maps:` mapping holds per-map blocks (same keys) under a map id or a glob (`zz_*`, case-insensitive); the more literal characters win. The scalars in [method map_keys] go through dot-map's per-map files instead (`dot_map/map/<name>.yml`), which is where a game's [code]DotGameModule._map_config_get/_set[/code] reach them, so a map can switch spawners off or halve a timer without a block here.
##
## [codeblock]
## pools:
##   wall_guns:
##     kind: weapon
##     catalogue: {tags_any: [primary], tags_none: [heavy], weight: 1, weights: {shotgun: 3}}
##     entries: [{id: medkit, kind: item, weight: 2, tags: [heal], data: {price: 50}}]
## sites:                  # defaults by spawner id, over what the marker says
##   armoury: {pool: wall_guns, respawn: 45, max: 2, group: guns}
## groups: {guns: 6}       # at most six alive across the group
## classes:                # entity classnames a converter maps to spawners
##   weapon_spawn_*: {pool: wall_guns}
## default_pool: wall_guns
## game: {shop: {prices: {primary: 500}}}   # free-form block for the game, merged per map like the rest
## maps:
##   zz_lot: {sites: {armoury: {respawn: 20}}}
## [/codeblock]

const CHANNEL := "weapon.spawner"
const ADDON := "dot-weapon"
const FILE := "spawner.yml"

## The scalars dot-map's per-map files may set, as the `allow` schema [DotMapConfig] takes. Merge them into a game's `_map_config_keys()`.
const MAP_KEYS := {
	"spawner_enabled": {"type": "bool"},
	"spawner_respawn_scale": {"type": "float", "min": 0.05, "max": 100.0},
	"spawner_max_scale": {"type": "float", "min": 0.0, "max": 100.0},
	"spawner_seed": {"type": "int"},
	"spawner_pool": {"type": "string"},
}

## The game whose `cfg/game/<game>/` tiers are read.
var game: String = ""
## An extra config root, as [method DotAddonConfig.file_layers] takes.
var config_dir: String = ""
## `DotWeaponDef`s a pool's `catalogue:` block draws from (any array of objects with `id` and `tags`).
var defs: Array = []
## Names used when a site names no pool.
var default_pool: StringName = &""
## The merged file content, before a map is picked.
var raw: Dictionary = {}

var _settings := {"spawner_enabled": true, "spawner_respawn_scale": 1.0, "spawner_max_scale": 1.0, "spawner_seed": 0, "spawner_pool": ""}
var _files := PackedStringArray()


## Reads every `spawner.yml` layer. A file that does not parse is skipped and logged; value: the paths read.
func load_files() -> DotResult:
	raw = {}
	_files = PackedStringArray()
	for path in DotAddonConfig.file_layers(ADDON, FILE, config_dir):
		var parsed := DotYaml.parse_file(path)
		if not parsed.ok or not (parsed.value is Dictionary or parsed.value == null):
			DotLog.warn(CHANNEL, "spawner file unreadable", {"file": path})
			continue
		if parsed.value != null:
			DotAddonConfig.merge(raw, parsed.value as Dictionary)
		_files.append(path)
	return DotResult.success(_files)


## Uses [param d] as the file content (tests, and games that build the config in code).
func load_dictionary(d: Dictionary) -> void:
	raw = d.duplicate(true)


## The resolved structure for [param map_id]: `{pools: {id: DotWeaponSpawnPool}, sites: {id: Dictionary}, groups, classes, default_pool}`, base then matching `maps:` blocks weakest to strongest. A pool that fails to build is logged and left out.
func resolve(map_id: String) -> Dictionary:
	var merged := raw.duplicate(true)
	merged.erase("maps")
	var blocks: Array = []
	var maps: Variant = raw.get("maps")
	if maps is Dictionary:
		for pattern: Variant in maps as Dictionary:
			if map_id.matchn(String(pattern)) and maps[pattern] is Dictionary:
				blocks.append([String(pattern), maps[pattern]])
	blocks.sort_custom(func(a: Array, b: Array) -> bool:
		var la := _literals(a[0])
		var lb := _literals(b[0])
		return la < lb if la != lb else String(a[0]) < String(b[0]))
	for b: Array in blocks:
		DotAddonConfig.merge(merged, b[1] as Dictionary)
	var pools := {}
	var pool_dicts: Variant = merged.get("pools", {})
	if pool_dicts is Dictionary:
		for pid: Variant in pool_dicts as Dictionary:
			if not (pool_dicts[pid] is Dictionary):
				continue
			var built := DotWeaponSpawnPool.from_dictionary(StringName(str(pid)), pool_dicts[pid], defs)
			if built.ok:
				pools[StringName(str(pid))] = built.value
			else:
				DotLog.warn(CHANNEL, "spawner pool refused", {"pool": str(pid), "why": built.error.message})
	return {
		"pools": pools,
		"sites": merged.get("sites", {}) if merged.get("sites") is Dictionary else {},
		"groups": merged.get("groups", {}) if merged.get("groups") is Dictionary else {},
		"classes": merged.get("classes", {}) if merged.get("classes") is Dictionary else {},
		"game": merged.get("game", {}) if merged.get("game") is Dictionary else {},
		"default_pool": StringName(str(merged.get("default_pool", default_pool))),
	}


## Hooks for [DotMapConfig]: the setting's current value, null for a key that is not one.
func get_setting(key: String) -> Variant:
	return _settings.get(key)


## Hook for [DotMapConfig]: false for a key that is not a spawner setting. Coerces to the schema's type.
func set_setting(key: String, value: Variant) -> bool:
	if not _settings.has(key):
		return false
	match String(MAP_KEYS[key]["type"]):
		"bool": _settings[key] = str(value).to_lower() in ["true", "1", "yes", "on"]
		"float": _settings[key] = float(value)
		"int": _settings[key] = int(value)
		_: _settings[key] = str(value)
	return true


func enabled() -> bool:
	return bool(_settings["spawner_enabled"])


func respawn_scale() -> float:
	return maxf(float(_settings["spawner_respawn_scale"]), 0.05)


func max_scale() -> float:
	return maxf(float(_settings["spawner_max_scale"]), 0.0)


func seed_override() -> int:
	return int(_settings["spawner_seed"])


func pool_override() -> StringName:
	return StringName(str(_settings["spawner_pool"]))


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray(["DotWeaponSpawnerConfig game=%s files=%d" % [game, _files.size()]])
	for key: String in _settings:
		out.append("  %s = %s" % [key, _settings[key]])
	return out


static func map_keys() -> Dictionary:
	return MAP_KEYS


static func _literals(pattern: Variant) -> int:
	var n := 0
	for c in String(pattern):
		if c != "*" and c != "?":
			n += 1
	return n
