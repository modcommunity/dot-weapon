class_name DotWeaponSpawner
extends RefCounted

## The server's spawner: sites, seeded draws from pools, respawn timers, caps. Authoritative; clients mirror it with [DotWeaponSpawnView].
## It places nothing: it says "item X now lies at P" through [signal changed] and the game makes the pickup. Time is whatever clock the game passes to [method tick].
## Usage and determinism: docs/spawners.md.

const CHANNEL := "weapon.spawner"
## The classname a marker entity uses when the config's `classes` names no other.
const ENTITY_CLASS := "dot_weapon_spawn"

## Event: `[&"spawn", instance, site, item, kind, position, rotation_y, data]`.
const EV_SPAWN := &"spawn"
## Event: `[&"take", instance, taker]` (taker empty when the item expired or was removed).
const EV_TAKE := &"take"

## One event for every change a client must see; feed it to [method DotWeaponSpawnView.apply].
signal changed(event: Array)
signal spawned(instance: int, site: StringName, item: StringName, kind: StringName, at: Vector3)
signal taken(instance: int, site: StringName, item: StringName, taker: StringName)

## An empty draw is retried this many times, this far apart, before the slot rests for the round.
const EMPTY_RETRIES := 5
const EMPTY_RETRY_SECONDS := 5.0

var config := DotWeaponSpawnerConfig.new()
var map_id: String = ""
var round_number: int = 0

var _structure: Dictionary = {}
var _sites: Dictionary = {}
var _order: Array[StringName] = []
var _slots: Dictionary = {}
var _live: Dictionary = {}
var _draws: Dictionary = {}
var _root: DotRandomStream = DotRandomStream.new(0, &"weapon_spawner")
var _next_instance: int = 1
var _now: float = 0.0
var _warned: Dictionary = {}


## Resolves the config for [param p_map_id] and replaces the sites with [param sites] (config `sites:` entries override a site's fields by id). Nothing spawns until [method begin_round].
func load_map(p_map_id: String, sites: Array = []) -> void:
	map_id = p_map_id
	_structure = config.resolve(p_map_id)
	_sites.clear()
	_order.clear()
	_slots.clear()
	_live.clear()
	_draws.clear()
	for s: Variant in sites:
		add_site(s as DotWeaponSpawnSite)


## Adds one site, applying the config's per-id and default-pool overrides. Returns the site as kept.
func add_site(site: DotWeaponSpawnSite) -> DotWeaponSpawnSite:
	var kept := site.duplicate_site()
	var over: Variant = (_structure.get("sites", {}) as Dictionary).get(String(kept.id))
	if over is Dictionary:
		kept.apply(over as Dictionary)
	if kept.pool == &"":
		kept.pool = _structure.get("default_pool", &"")
	if not _sites.has(kept.id):
		_order.append(kept.id)
	_sites[kept.id] = kept
	return kept


## Sites from map entities `{classname, origin (Vector3 or [x,y,z]), angle (degrees, optional), props (strings fine)}`: the config's `classes` globs (and [constant ENTITY_CLASS]) pick the entities, their mapping is the site's defaults, the entity's `props` come over that. Returns the sites added.
func add_entities(entities: Array) -> Array[DotWeaponSpawnSite]:
	var classes: Dictionary = _structure.get("classes", {})
	var out: Array[DotWeaponSpawnSite] = []
	var index := 0
	for e: Variant in entities:
		if not (e is Dictionary):
			continue
		var ed := e as Dictionary
		var cls := str(ed.get("classname", ""))
		var defaults: Variant = null
		for pattern: Variant in classes:
			if cls.matchn(String(pattern)):
				defaults = classes[pattern]
				break
		if defaults == null and cls != ENTITY_CLASS:
			continue
		index += 1
		var d := {"id": "%s_%d" % [cls, index], "position": ed.get("origin", Vector3.ZERO), "rotation_y": deg_to_rad(float(ed.get("angle", 0.0)))}
		if defaults is Dictionary:
			d.merge(defaults as Dictionary, true)
		if ed.get("props") is Dictionary:
			d.merge(ed["props"] as Dictionary, true)
		out.append(add_site(DotWeaponSpawnSite.from_dictionary(d)))
	return out


## Starts round [param p_round]: every slot empties and takes its first timer, so a new round is a new draw. Items still lying are removed (clients are told).
func begin_round(now: float, p_round: int) -> void:
	_now = now
	round_number = p_round
	_root = DotRandomStream.new(config.seed_override() if config.seed_override() != 0 else map_id.hash(), &"weapon_spawner")
	for inst: int in _live.keys():
		_remove(inst, &"")
	_draws.clear()
	_slots.clear()
	for sid in _order:
		var site: DotWeaponSpawnSite = _sites[sid]
		var slots: Array = []
		if config.enabled() and site.enabled:
			for i in _cap(site):
				slots.append({"inst": 0, "ready": now + site.initial_delay, "until": 0.0})
		_slots[sid] = slots
	DotLog.info(CHANNEL, "round begun", {"map": map_id, "round": p_round, "sites": _order.size()})


## Spawns what is due and expires what has lain too long. Call every server tick with the game clock.
func tick(now: float) -> void:
	_now = now
	for sid in _order:
		var site: DotWeaponSpawnSite = _sites[sid]
		for slot: Dictionary in _slots.get(sid, []):
			if int(slot["inst"]) != 0:
				if float(slot["until"]) > 0.0 and now >= float(slot["until"]):
					_remove(int(slot["inst"]), &"")
					_schedule(site, slot)
			elif float(slot["ready"]) >= 0.0 and now >= float(slot["ready"]):
				_try_spawn(site, slot)


## The item [param instance] was used up by [param taker]: frees its slot and starts the respawn timer. Fails (CODE_STATE) for an instance already gone, so two players using one pickup in a tick cannot both win. Value: `{item, kind, site, data}`.
func take(instance: int, taker: StringName = &"") -> DotResult:
	if not _live.has(instance):
		return DotResult.fail(DotError.CODE_STATE, "no live spawner item %d" % instance)
	var info: Dictionary = (_live[instance] as Dictionary).duplicate()
	var slot: Dictionary = info["slot"]
	_remove(instance, taker)
	_schedule(_sites[info["site"]], slot)
	return DotResult.success({"item": info["item"], "kind": info["kind"], "site": info["site"], "data": info["data"]})


## What site [param site_id] gives at draw number [param index], without spawning (a trader's shelf, a preview): `{id, kind, weight, tags, data}`, empty when the site or pool is unknown or the filter leaves nothing.
func roll(site_id: StringName, index: int) -> Dictionary:
	if not _sites.has(site_id):
		return {}
	var site: DotWeaponSpawnSite = _sites[site_id]
	if site.item != &"":
		return {"id": site.item, "kind": site.kind, "data": site.data.duplicate(true)}
	var pool_id := config.pool_override() if config.pool_override() != &"" else site.pool
	var pool: DotWeaponSpawnPool = (_structure.get("pools", {}) as Dictionary).get(pool_id)
	if pool == null:
		return {}
	return pool.pick(site.filter, _stream(site_id).unit_at(2 * index))


## Live items: `instance -> {site, item, kind, at, data}`.
func live() -> Dictionary:
	var out := {}
	for inst: int in _live:
		var i: Dictionary = _live[inst]
		out[inst] = {"site": i["site"], "item": i["item"], "kind": i["kind"], "at": (_sites[i["site"]] as DotWeaponSpawnSite).position, "data": i["data"]}
	return out


## The config's free-form `game:` block for this map (prices, rules the addon does not read).
func game_block() -> Dictionary:
	return _structure.get("game", {})


func site_ids() -> Array[StringName]:
	return _order


func site(id: StringName) -> DotWeaponSpawnSite:
	return _sites.get(id)


## Items alive at [param site_id], or across all sites when empty.
func alive(site_id: StringName = &"") -> int:
	var n := 0
	for inst: int in _live:
		if site_id == &"" or (_live[inst] as Dictionary)["site"] == site_id:
			n += 1
	return n


## Seconds until the next item at [param site_id] (the soonest waiting slot); -1 when none waits.
func seconds_until(site_id: StringName) -> float:
	var best := -1.0
	for slot: Dictionary in _slots.get(site_id, []):
		if int(slot["inst"]) == 0 and float(slot["ready"]) >= 0.0:
			var t := maxf(float(slot["ready"]) - _now, 0.0)
			best = t if best < 0.0 else minf(best, t)
	return best


## Everything a joining client needs: `{round, items: [spawn events], waiting: [[site, seconds]]}`; feed it to [method DotWeaponSpawnView.apply_snapshot].
func snapshot() -> Dictionary:
	var items: Array = []
	for inst: int in _live:
		items.append(_spawn_event(inst))
	var waiting: Array = []
	for sid in _order:
		var t := seconds_until(sid)
		if t >= 0.0:
			waiting.append([sid, t])
	return {"round": round_number, "items": items, "waiting": waiting}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray(["DotWeaponSpawner map=%s round=%d sites=%d alive=%d" % [map_id, round_number, _order.size(), _live.size()]])
	for sid in _order:
		out.append("  %s pool=%s alive=%d next=%.1fs" % [sid, (_sites[sid] as DotWeaponSpawnSite).pool, alive(sid), seconds_until(sid)])
	return out


func _cap(site: DotWeaponSpawnSite) -> int:
	if site.max_alive <= 0 or config.max_scale() <= 0.0:
		return 0
	var want := maxi(roundi(site.max_alive * config.max_scale()), 1)
	if want > config.max_alive_cap:
		if not _warned.has(StringName("cap_" + String(site.id))):
			_warned[StringName("cap_" + String(site.id))] = true
			DotLog.warn(CHANNEL, "a spawner site's max_alive was clamped", {"site": String(site.id), "wanted": want, "cap": config.max_alive_cap})
		return config.max_alive_cap
	return want


func _stream(site_id: StringName) -> DotRandomStream:
	return _root.stream(site_id).stream_for(&"round", round_number)


func _schedule(site: DotWeaponSpawnSite, slot: Dictionary) -> void:
	slot["inst"] = 0
	if site.one_shot:
		slot["ready"] = -1.0
		return
	var n: int = _draws.get(site.id, 0)
	var jitter := _stream(site.id).unit_at(2 * n + 1) * site.respawn_jitter
	slot["ready"] = _now + site.respawn_seconds * config.respawn_scale() * (1.0 + jitter)


func _try_spawn(site: DotWeaponSpawnSite, slot: Dictionary) -> void:
	if site.group != &"":
		var cap: Variant = (_structure.get("groups", {}) as Dictionary).get(String(site.group))
		if cap != null and _group_alive(site.group) >= maxi(roundi(float(cap) * config.max_scale()), 1 if float(cap) > 0.0 else 0):
			return
	var n: int = _draws.get(site.id, 0)
	var entry := roll(site.id, n)
	_draws[site.id] = n + 1
	if entry.is_empty():
		if not _warned.has(site.id):
			_warned[site.id] = true
			DotLog.warn(CHANNEL, "a spawner site has nothing to draw", {"site": String(site.id), "pool": String(site.pool)})
		var tries: int = int(slot.get("retries", 0))
		if tries < EMPTY_RETRIES:
			slot["retries"] = tries + 1
			slot["ready"] = _now + EMPTY_RETRY_SECONDS
		else:
			slot["ready"] = -1.0
		return
	slot["retries"] = 0
	var inst := _next_instance
	_next_instance += 1
	var data: Dictionary = site.data.duplicate(true)
	data.merge(entry.get("data", {}), true)
	var kind: StringName = site.kind if site.kind != &"" else entry.get("kind", &"weapon")
	slot["inst"] = inst
	slot["until"] = _now + site.lifetime_seconds if site.lifetime_seconds > 0.0 else 0.0
	_live[inst] = {"site": site.id, "item": entry["id"], "kind": kind, "data": data, "slot": slot}
	spawned.emit(inst, site.id, entry["id"], kind, site.position)
	changed.emit(_spawn_event(inst))


func _spawn_event(inst: int) -> Array:
	var i: Dictionary = _live[inst]
	var site: DotWeaponSpawnSite = _sites[i["site"]]
	return [EV_SPAWN, inst, i["site"], i["item"], i["kind"], site.position, site.rotation_y, i["data"]]


func _group_alive(group: StringName) -> int:
	var n := 0
	for inst: int in _live:
		if (_sites[(_live[inst] as Dictionary)["site"]] as DotWeaponSpawnSite).group == group:
			n += 1
	return n


func _remove(inst: int, taker: StringName) -> void:
	var info: Dictionary = _live[inst]
	_live.erase(inst)
	taken.emit(inst, info["site"], info["item"], taker)
	changed.emit([EV_TAKE, inst, taker])
