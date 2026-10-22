class_name DotWeaponProfiles
extends RefCounted

## Loads weapons from `weapon` profiles (cfg/addons/<addon>/weapon, cfg/game/<game>/weapon, cfg/server/weapon).
##
## A pack's own keys go under `extra:`; [method flat] merges them back for the pack's builder.
## A weapon may be a folder with `upgrades/<id>.yml` children ([method apply_upgrades]).

const KIND := "weapon"
const UPGRADES := "upgrades"
const FIRE_MODES := ["semi", "auto", "burst", "charge", "hold"]
const OPS := ["set", "mul", "add"]


## The common keys (the [DotWeaponDef] fields a pack rarely subclasses). Anything else goes under `extra:`.
static func schema() -> Array:
	var f := DotProfileSet.field
	return [
		f.call("name", "string", ""),
		f.call("description", "string", ""),
		f.call("tags", "list", []),
		f.call("behaviour", "string", ""),
		f.call("slot", "int", 1, {"min": 1, "max": 16}),
		f.call("authored_tick_rate", "int", 0, {"min": 0, "max": 1000}),
		f.call("deploy_ticks", "int", 22, {"min": 0, "max": 10000}),
		f.call("holster_ticks", "int", 13, {"min": 0, "max": 10000}),
		f.call("fire_mode", "string", "semi", {"enum": FIRE_MODES}),
		f.call("use_interval_ticks", "int", 7, {"min": 0, "max": 100000}),
		f.call("burst_count", "int", 3, {"min": 1, "max": 64}),
		f.call("burst_interval_ticks", "int", 3, {"min": 0, "max": 100000}),
		f.call("charge_ticks", "int", 64, {"min": 1, "max": 100000}),
		f.call("charge_requires_min", "bool", false),
		f.call("min_charge", "float", 0.35, {"min": 0.0, "max": 1.0}),
		f.call("ammo_type", "string", ""),
		f.call("magazine", "int", 0, {"min": 0, "max": 10000}),
		f.call("reserve", "int", 0, {"min": 0, "max": 99999}),
		f.call("reserve_max", "int", 0, {"min": 0, "max": 99999}),
		f.call("cost_per_use", "int", 1, {"min": 0, "max": 1000}),
		f.call("infinite_reserve", "bool", false),
		f.call("reload_ticks", "int", 141, {"min": 0, "max": 100000}),
		f.call("reload_per_round", "bool", false),
		f.call("reload_start_ticks", "int", 22, {"min": 0, "max": 100000}),
		f.call("auto_reload", "bool", true),
		f.call("mounts", "list", []),
		f.call("enabled", "bool", true),
		f.call("menu", "dict", {}),
	]


## The schema of an upgrade. `set`, `mul` and `add` name keys of the weapon (schema or `extra:`).
static func upgrade_schema() -> Array:
	var f := DotProfileSet.field
	return [
		f.call("name", "string", ""),
		f.call("description", "string", ""),
		f.call("cost", "int", 0, {"min": 0}),
		f.call("requires", "list", []),
		f.call("set", "dict", {}),
		f.call("mul", "dict", {}),
		f.call("add", "dict", {}),
		f.call("menu", "dict", {}),
	]


## A profile set for weapons of [param addon] and [param game]; [param roots] overrides the config roots (tests).
## [param layer] (a Dictionary, see [member DotWeaponProfileGroup.runtime]) is shared as the set's runtime layer, so live edits reach it.
static func make_set(addon: String, game: String, roots: PackedStringArray = PackedStringArray(), layer: Variant = null) -> DotProfileSet:
	var s := DotProfileSet.create(addon, game, KIND, schema())
	s.roots = roots
	if layer is Dictionary:
		s.runtime = layer
	return s


## Copies every script variable of [param from] onto [param into], so holders of [param into] see a rebuilt definition.
static func refresh_def(into: DotWeaponDef, from: DotWeaponDef) -> void:
	for p: Dictionary in from.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			into.set(p["name"], from.get(p["name"]))


## Weapon ids found on disk, sorted; opens no file.
static func list_ids(profiles: DotProfileSet) -> PackedStringArray:
	return profiles.list_ids()


## One weapon as a flat dictionary: `extra:` keys, then the schema keys over them.
static func flat(profile: DotProfile) -> Dictionary:
	var out: Dictionary = profile.extra.duplicate(true)
	out.merge(profile.values.duplicate(true), true)
	return out


## Fills the common [DotWeaponDef] fields from [param c] for the keys it holds; the rest is the pack's.
static func apply_common(d: DotWeaponDef, c: Dictionary) -> void:
	if c.has("name"):
		d.display_name = String(c["name"])
	if c.has("description"):
		d.description = String(c["description"])
	if c.has("behaviour") and String(c["behaviour"]) != "":
		d.behaviour_path = String(c["behaviour"])
	if c.has("tags"):
		var tags: Array[StringName] = []
		for t in c["tags"]:
			tags.append(StringName(str(t)))
		d.tags = tags
	if c.has("mounts"):
		var mounts: Array[StringName] = []
		for m in c["mounts"]:
			mounts.append(StringName(str(m)))
		d.mounts = mounts
	if c.has("ammo_type"):
		d.ammo_type = StringName(str(c["ammo_type"]))
	if c.has("fire_mode"):
		var i := FIRE_MODES.find(str(c["fire_mode"]))
		if i >= 0:
			d.fire_mode = i as DotWeaponDef.Fire
	for k in ["slot", "authored_tick_rate", "deploy_ticks", "holster_ticks", "use_interval_ticks", "burst_count",
			"burst_interval_ticks", "charge_ticks", "magazine", "reserve", "reserve_max", "cost_per_use",
			"reload_ticks", "reload_start_ticks"]:
		if c.has(k):
			d.set(k, int(c[k]))
	for k in ["charge_requires_min", "infinite_reserve", "reload_per_round", "auto_reload"]:
		if c.has(k):
			d.set(k, bool(c[k]))
	if c.has("min_charge"):
		d.min_charge = float(c["min_charge"])


## Loads one profile into a [DotWeaponDef] of the common fields, with [member DotWeaponDef.params] taken from `extra:`.
## The value of the result.
static func load_def(profiles: DotProfileSet, id: String) -> DotResult:
	var res := profiles.load_profile(id)
	if not res.ok:
		return res
	var d := DotWeaponDef.new()
	d.id = StringName(id)
	apply_common(d, res.value.values)
	d.params = res.value.extra.duplicate(true)
	return DotResult.success(d)


## Menu entries `{id, category, icon, sort, hidden}` for the visible weapons, sorted by sort then id.
## Reads each profile's yml, never a model or script.
static func menu_entries(profiles: DotProfileSet, include_hidden: bool = false) -> Array:
	var out: Array = []
	for id in profiles.list_ids():
		var res := profiles.load_profile(id)
		if not res.ok:
			continue
		var m: Dictionary = res.value.get_value("menu", {})
		var hidden := bool(m.get("hidden", false)) or not bool(res.value.get_value("enabled", true))
		if hidden and not include_hidden:
			continue
		out.append({
			"id": id,
			"category": str(m.get("category", "")),
			"icon": str(m.get("icon", "")),
			"sort": int(m.get("sort", 0)),
			"hidden": hidden,
		})
	out.sort_custom(func(a, b): return a["sort"] < b["sort"] or (a["sort"] == b["sort"] and a["id"] < b["id"]))
	return out


## The upgrade set of weapon [param id] (`weapon/<id>/upgrades`).
static func upgrade_set(profiles: DotProfileSet, id: String) -> DotProfileSet:
	return profiles.child_set(id, UPGRADES, upgrade_schema())


## Upgrade ids of weapon [param id], sorted; opens no file.
static func list_upgrades(profiles: DotProfileSet, id: String) -> PackedStringArray:
	return upgrade_set(profiles, id).list_ids()


## Applies the upgrades [param ids], in order, to [param base] (a flat weapon dictionary).
## Per upgrade `set` runs, then `mul`, then `add`; a `requires` id must come earlier in the list.
## Value: `{values, cost}`, [param base] itself is untouched.
static func apply_upgrades(base: Dictionary, ups: DotProfileSet, ids: Array) -> DotResult:
	var out: Dictionary = base.duplicate(true)
	var done := {}
	var cost := 0
	for raw_id in ids:
		var uid := str(raw_id)
		if done.has(uid):
			return DotResult.fail(DotError.CODE_INVALID, "upgrade %s applied twice" % uid)
		var res := ups.load_profile(uid)
		if not res.ok:
			return res
		var u: DotProfile = res.value
		for req in u.get_value("requires", []):
			if not done.has(str(req)):
				return DotResult.fail(DotError.CODE_INVALID, "upgrade %s needs %s first" % [uid, str(req)])
		for op in OPS:
			var mods: Dictionary = u.get_value(op, {})
			for key in mods:
				var applied := _apply_op(out, str(key), op, mods[key])
				if applied != "":
					return DotResult.fail(DotError.CODE_INVALID, "upgrade %s: %s" % [uid, applied])
		cost += int(u.get_value("cost", 0))
		done[uid] = true
	return DotResult.success({"values": out, "cost": cost})


## An error text, or "" when [param op] was applied to [param key] in [param c].
static func _apply_op(c: Dictionary, key: String, op: String, v: Variant) -> String:
	if not c.has(key):
		return "no key '%s' to %s" % [key, op]
	var cur: Variant = c[key]
	if op == "set":
		var numeric := (cur is int or cur is float) and (v is int or v is float)
		if numeric:
			c[key] = int(round(float(v))) if cur is int else float(v)
		elif typeof(cur) == typeof(v):
			c[key] = v
		else:
			return "set '%s' needs a %s" % [key, type_string(typeof(cur))]
		return ""
	if not ((cur is int or cur is float) and (v is int or v is float)):
		return "%s '%s' needs a number" % [op, key]
	var n: float = float(cur) * float(v) if op == "mul" else float(cur) + float(v)
	c[key] = int(round(n)) if cur is int else n
	return ""
