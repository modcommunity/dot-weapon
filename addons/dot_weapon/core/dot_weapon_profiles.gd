class_name DotWeaponProfiles
extends RefCounted

## Loads weapons from `weapon` profiles (the `cfg/addons`, `cfg/game`, `cfg/server/addons` and `cfg/server/game` tiers).
## A pack's own keys go under `extra:`; [method flat] merges them back. A weapon may be a folder with `upgrades/<id>.yml` children ([method apply_upgrades]).

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
		f.call("fire_modes", "list", []),
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
		f.call("weight", "float", 0.0, {"min": 0.0, "max": 1000.0}),
		f.call("mounts", "list", []),
		f.call("enabled", "bool", true),
		f.call("menu", "dict", {}),
	]


## Kind to schema for tools that validate profiles without a game (dot-core profile_check).
static func profile_schemas() -> Dictionary:
	return {"weapon": {"schema": schema(), "children": {"upgrades": upgrade_schema()}}}


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
	if c.has("fire_modes"):
		var modes := PackedStringArray()
		for m in c["fire_modes"]:
			if DotWeaponDef.fire_mode_named(str(m)) >= 0:
				modes.append(str(m).to_lower())
		d.fire_modes = modes
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
	if c.has("weight"):
		d.weight = float(c["weight"])


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

# Overlay of profiles on a pack's code-built defs: only keys a file sets ([member DotProfile.file_keys])
# change a def. `extra: tuning:` and `extra: params:` hold the tuning numbers and the def's params;
# upgrades name them flat (`tuning.damage`, `params.x`, `magazine`).
const OVERLAY_CHANNEL := "weapon.profiles"
const OVERLAY_TUNING := "tuning"
const OVERLAY_PARAMS := "params"
const OVERLAY_SKIP := ["menu", "enabled"]


## The profile set of [param addon] for a code-built pack (see [method tune]); a mounted pack's cfg root ([param pack_root]) is the weakest root.
static func overlay_set(addon: String, game: String = "", pack_root: String = "", base_roots: PackedStringArray = PackedStringArray(), layer: Variant = null) -> DotProfileSet:
	var roots := base_roots if not base_roots.is_empty() else DotProfileSet.default_roots()
	if pack_root != "":
		roots = PackedStringArray([pack_root]) + roots
	return make_set(addon, game, roots, layer)


## Lays the profiles over [param defs] in place; a profile with no weapon here is ignored with a WARN.
## Returns the profiles that failed to load (their weapons keep the builder's numbers).
static func tune(defs: Array[DotWeaponDef], set: DotProfileSet) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := set.list_ids()
	if ids.is_empty():
		return errors
	var by_id := {}
	for def in defs:
		by_id[String(def.id)] = def
	for id in ids:
		if not by_id.has(id):
			continue
		var res := set.load_profile(id)
		if not res.ok:
			errors.append(res.error.message)
			DotLog.error(OVERLAY_CHANNEL, "weapon profile skipped", {"id": id, "why": res.error.message})
			continue
		apply_flat(by_id[id], file_flat(res.value))
	set.clear_cache()
	return errors


## The keys [param p]'s files set, as the flat form [method flat_of] writes.
static func file_flat(p: DotProfile) -> Dictionary:
	var out := {}
	for path in p.file_keys:
		var parts := String(path).split(".")
		if parts[0] == DotProfileSet.EXTRA_KEY:
			if parts.size() > 2:
				out[".".join(parts.slice(1))] = DotYaml.at(p.extra, ".".join(parts.slice(1)))
		elif parts[0] not in OVERLAY_SKIP:
			out[parts[0]] = p.values[parts[0]]
	return out


## Applies a flat dictionary (see [method flat_of]) to [param def]; unknown tuning keys are logged and skipped.
static func apply_flat(def: DotWeaponDef, values: Dictionary) -> void:
	var common := {}
	for key: String in values:
		if key.begins_with(OVERLAY_TUNING + "."):
			_set_tuning(def, key.trim_prefix(OVERLAY_TUNING + "."), values[key])
		elif key.begins_with(OVERLAY_PARAMS + "."):
			var pk := StringName(key.trim_prefix(OVERLAY_PARAMS + "."))
			def.params[pk] = _coerce(def.params.get(pk), values[key])
		else:
			common[key] = values[key]
	apply_common(def, common)


static func _set_tuning(def: DotWeaponDef, name: String, value: Variant) -> void:
	if def.tuning == null or not (name in def.tuning) or typeof(def.tuning.get(name)) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		DotLog.warn(OVERLAY_CHANNEL, "unknown tuning key in profile; ignored", {"weapon": String(def.id), "key": name})
		return
	def.tuning.set(name, _coerce(def.tuning.get(name), value))


## Keeps the builder's type, so `magazine: 30.0` stays an int. A new key (no current value) is taken as written.
static func _coerce(current: Variant, given: Variant) -> Variant:
	if current is bool or current == null:
		return given
	if current is int and (given is int or given is float):
		return int(round(float(given)))
	if current is float and (given is int or given is float):
		return float(given)
	return given


## Every tunable of [param def] as one flat dictionary: the schema keys, `tuning.*` and `params.*`.
static func flat_of(def: DotWeaponDef) -> Dictionary:
	var out := {
		"name": def.display_name, "description": def.description,
		"tags": Array(def.tags).map(func(t: StringName) -> String: return String(t)),
		"behaviour": def.behaviour_path, "slot": def.slot, "authored_tick_rate": def.authored_tick_rate,
		"deploy_ticks": def.deploy_ticks, "holster_ticks": def.holster_ticks,
		"fire_mode": FIRE_MODES[def.fire_mode], "fire_modes": Array(def.fire_modes),
		"use_interval_ticks": def.use_interval_ticks, "burst_count": def.burst_count,
		"burst_interval_ticks": def.burst_interval_ticks, "charge_ticks": def.charge_ticks,
		"charge_requires_min": def.charge_requires_min, "min_charge": def.min_charge,
		"ammo_type": String(def.ammo_type), "magazine": def.magazine, "reserve": def.reserve,
		"reserve_max": def.reserve_max, "cost_per_use": def.cost_per_use,
		"infinite_reserve": def.infinite_reserve, "reload_ticks": def.reload_ticks,
		"reload_per_round": def.reload_per_round, "reload_start_ticks": def.reload_start_ticks,
		"auto_reload": def.auto_reload, "weight": def.weight,
		"mounts": Array(def.mounts).map(func(m: StringName) -> String: return String(m)),
	}
	if def.tuning != null:
		for p: Dictionary in def.tuning.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(p["type"]) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				out["%s.%s" % [OVERLAY_TUNING, p["name"]]] = def.tuning.get(p["name"])
	for k in def.params:
		if def.params[k] is int or def.params[k] is float or def.params[k] is bool or def.params[k] is String:
			out["%s.%s" % [OVERLAY_PARAMS, k]] = def.params[k]
	return out


## The yml text of [param def]'s builder numbers: what the shipped `weapon/<id>.yml` holds.
static func to_yaml(def: DotWeaponDef, addon_title: String) -> String:
	var fl := flat_of(def)
	var top: PackedStringArray = ["# %s: %s. Durations are ticks at %d Hz; delete a key to keep the builder's value." % [addon_title, def.id, def.authored_tick_rate]]
	var tuning: PackedStringArray = []
	var params: PackedStringArray = []
	for key: String in fl:
		if key.begins_with(OVERLAY_TUNING + "."):
			tuning.append("    %s: %s" % [key.trim_prefix(OVERLAY_TUNING + "."), _scalar(fl[key])])
		elif key.begins_with(OVERLAY_PARAMS + "."):
			params.append("    %s: %s" % [key.trim_prefix(OVERLAY_PARAMS + "."), _scalar(fl[key])])
		else:
			top.append("%s: %s" % [key, _scalar(fl[key])])
	top.append("extra:")
	if not tuning.is_empty():
		top.append("  tuning:")
		top.append_array(tuning)
	if not params.is_empty():
		top.append("  params:")
		top.append_array(params)
	return "\n".join(top) + "\n"


static func _scalar(v: Variant) -> String:
	if v is String:
		return JSON.stringify(v)
	if v is Array:
		return "[" + ", ".join(PackedStringArray((v as Array).map(func(x: Variant) -> String: return _scalar(x)))) + "]"
	if v is float:
		return "%s" % v if is_finite(v) else "0.0"
	return str(v)


## Where the shipped yml for [param id] lives under [param root]: the folder form when the weapon has one (for its upgrades).
static func profile_path(addon: String, id: String, root: String = "res://cfg") -> String:
	var base := root.path_join("addons").path_join(addon).path_join("weapon")
	if DirAccess.dir_exists_absolute(base.path_join(id)):
		return base.path_join(id).path_join("%s.yml" % id)
	return base.path_join("%s.yml" % id)


## [param def] with the upgrades [param ids] applied, a copy; value `{def, cost}`.
static func upgraded(def: DotWeaponDef, ids: Array, set: DotProfileSet) -> DotResult:
	var ups := upgrade_set(set, String(def.id))
	var res := apply_upgrades(flat_of(def), ups, ids)
	ups.clear_cache()
	if not res.ok:
		return res
	var copy := def.duplicate(true) as DotWeaponDef
	apply_flat(copy, res.value["values"])
	return DotResult.success({"def": copy, "cost": res.value["cost"]})
