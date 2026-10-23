class_name DotWeaponSpawnSite
extends RefCounted

## One place that gives something out: where, from which pool, how often, how many at once.
##
## A site is plain data so a headless game, a map document and a [DotWeaponSpawnPoint] node all make the same thing. Config files override these fields by the site's [member id] (see [DotWeaponSpawnerConfig]).

## Names the site in the config and the wire; unique in a map.
var id: StringName = &""
var position: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
## Overrides the kind of what is drawn (`ammo`, `trader`); empty keeps the entry's own.
var kind: StringName = &""
## The pool drawn from; empty means the config's default pool.
var pool: StringName = &""
## A fixed item: nothing is drawn, the site just respawns this.
var item: StringName = &""
## Narrows the pool: `{tags_any, tags_all, tags_none, ids}`.
var filter: Dictionary = {}
## Seconds from a take (or a begin) to the next item; see [member respawn_jitter].
var respawn_seconds: float = 30.0
## A fraction of [member respawn_seconds] added at random (seeded), 0 to 1.
var respawn_jitter: float = 0.0
## Seconds after a round begins before the first item; 0 spawns it with the round.
var initial_delay: float = 0.0
## Items this site holds at once.
var max_alive: int = 1
## A taken item is never replaced this round.
var one_shot: bool = false
## Seconds an item lies before it goes away (and the timer restarts); 0 keeps it.
var lifetime_seconds: float = 0.0
## Sites of one group share the cap [member DotWeaponSpawnerConfig.groups] gives it.
var group: StringName = &""
var enabled: bool = true
## Free data carried onto every spawned item, merged under the entry's own.
var data: Dictionary = {}


## Overrides fields from [param d] (a config or entity mapping); unknown keys are ignored and strings are coerced, since a map entity's values arrive as text.
func apply(d: Dictionary) -> DotWeaponSpawnSite:
	for key: Variant in d:
		var v: Variant = d[key]
		match String(key):
			"id": id = StringName(str(v))
			"position":
				if v is Vector3:
					position = v
				elif v is Array and (v as Array).size() >= 3:
					position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			"rotation_y": rotation_y = float(v)
			"kind": kind = StringName(str(v))
			"pool": pool = StringName(str(v))
			"item": item = StringName(str(v))
			"respawn_seconds", "respawn": respawn_seconds = maxf(float(v), 0.0)
			"respawn_jitter": respawn_jitter = clampf(float(v), 0.0, 1.0)
			"initial_delay": initial_delay = maxf(float(v), 0.0)
			"max_alive", "max": max_alive = clampi(int(v), 0, 100000)
			"one_shot": one_shot = _bool(v)
			"lifetime_seconds", "lifetime": lifetime_seconds = maxf(float(v), 0.0)
			"group": group = StringName(str(v))
			"enabled": enabled = _bool(v)
			"data": data = (v as Dictionary).duplicate(true) if v is Dictionary else data
			"tags_any", "tags_all", "tags_none", "ids":
				filter[String(key)] = DotWeaponSpawnPool._strs(v)
			"filter":
				if v is Dictionary:
					for fk: Variant in v:
						filter[String(fk)] = DotWeaponSpawnPool._strs(v[fk])
	return self


## A site from a mapping (see [method apply]).
static func from_dictionary(d: Dictionary) -> DotWeaponSpawnSite:
	return DotWeaponSpawnSite.new().apply(d)


func duplicate_site() -> DotWeaponSpawnSite:
	var out := DotWeaponSpawnSite.new()
	for p in ["id", "position", "rotation_y", "kind", "pool", "item", "respawn_seconds", "respawn_jitter", "initial_delay", "max_alive", "one_shot", "lifetime_seconds", "group", "enabled"]:
		out.set(p, get(p))
	out.filter = filter.duplicate(true)
	out.data = data.duplicate(true)
	return out


static func _bool(v: Variant) -> bool:
	return str(v).to_lower() in ["true", "1", "yes", "on"]
