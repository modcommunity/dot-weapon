extends Node

## The weapon spawner's self-test: pools and filters, seeded draws, timers, caps, config layers, entities, the replicated view.

var _passed: int = 0
var _failed: int = 0
var _sections_entered: int = 0
var _sections_finished: int = 0

const CHECKS := 59

const CONFIG := {
	"default_pool": "guns",
	"pools": {
		"guns": {"kind": "weapon", "entries": [
			{"id": "pistol", "weight": 1, "tags": ["sidearm"]},
			{"id": "shotgun", "weight": 3, "tags": ["primary", "shell"]},
			{"id": "rifle", "weight": 2, "tags": ["primary"]},
			{"id": "banned", "weight": 0, "tags": ["primary"]},
		]},
		"stock": {"kind": "trader", "entries": [{"id": "medkit", "weight": 1, "data": {"price": 50}}]},
	},
	"sites": {"wall": {"respawn": 20, "max": 2}},
	"groups": {"g": 1},
	"game": {"shop": {"prices": {"primary": 500}}},
	"classes": {"weapon_spawn_*": {"pool": "guns", "tags_any": "primary"}},
	"maps": {
		"zz_*": {"sites": {"wall": {"respawn": 10}}},
		"zz_lot": {"sites": {"wall": {"respawn": 5}}},
	},
}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-weapon spawner self-test")
	_test_pool()
	_test_config()
	_test_cycle()
	_test_determinism()
	_test_caps_and_settings()
	_test_entities_and_marker()
	_test_view()
	print("")
	print("%d sections entered, %d finished, %d passed, %d failed" % [_sections_entered, _sections_finished, _passed, _failed])
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 or _sections_entered != _sections_finished else 0)


func _section(name: String) -> void:
	_sections_entered += 1
	print("-- %s" % name)


func _done() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _spawner(map: String, sites: Array, seed_value: int = 7) -> DotWeaponSpawner:
	var s := DotWeaponSpawner.new()
	s.config.load_dictionary(CONFIG)
	s.config.set_setting("spawner_seed", seed_value)
	s.load_map(map, sites)
	return s


func _site(id: String, extra: Dictionary = {}) -> DotWeaponSpawnSite:
	var d := {"id": id, "position": Vector3(1, 0, 2)}
	d.merge(extra, true)
	return DotWeaponSpawnSite.from_dictionary(d)


func _test_pool() -> void:
	_section("pool filters and weights")
	var pool: DotWeaponSpawnPool = DotWeaponSpawnPool.from_dictionary(&"guns", CONFIG["pools"]["guns"]).value
	_check(pool.candidates().size() == 3, "a zero weight never draws")
	_check(pool.candidates({"tags_any": ["primary"]}).size() == 2, "tags_any")
	_check(pool.candidates({"tags_all": "primary,shell"}).size() == 1, "tags_all, comma string")
	_check(pool.candidates({"tags_none": ["primary"]}).size() == 1, "tags_none")
	_check(pool.candidates({"ids": ["rifle", "nothing"]}).size() == 1, "ids")
	_check(pool.pick({}, 0.0)["id"] == &"pistol", "unit 0 is the first entry by id")
	_check(pool.pick({}, 0.2)["id"] == &"rifle", "entries are in id order, so file order never changes a draw")
	_check(pool.pick({}, 0.99)["id"] == &"shotgun", "unit 0.99 is the last")
	_check(pool.pick({"ids": ["none"]}, 0.1).is_empty(), "an empty filter gives nothing")
	var defs: Array = []
	for t in [["a", "primary"], ["b", "primary"], ["c", "melee"]]:
		var d := DotWeaponDef.new()
		d.id = StringName(t[0])
		d.tags = [StringName(t[1])]
		defs.append(d)
	var cat: DotWeaponSpawnPool = DotWeaponSpawnPool.from_dictionary(&"c", {"catalogue": {"tags_any": ["primary"], "weights": {"b": 4}}, "entries": [{"id": "a", "weight": 9}]}, defs).value
	_check(cat.entries.size() == 2 and float(cat.candidates({"ids": ["a"]})[0]["weight"]) == 9.0, "an explicit entry replaces a catalogue one")
	_check(float(cat.candidates({"ids": ["b"]})[0]["weight"]) == 4.0, "catalogue weights override")
	var weighed: DotWeaponSpawnPool = DotWeaponSpawnPool.from_dictionary(&"w", {"channel": "shop", "catalogue": {"tags_any": ["primary"]}}, defs,
			func(channel: StringName, id: StringName, w: float) -> float: return 0.0 if channel == &"shop" and id == &"b" else w).value
	_check(weighed.channel == &"shop" and weighed.candidates({"ids": ["b"]}).is_empty() and not weighed.candidates({"ids": ["a"]}).is_empty(), "a weigher re-weighs by pool channel (0 removes)")
	_check(not DotWeaponSpawnPool.from_dictionary(&"x", {"entries": [{"weight": 1}]}).ok, "an entry without an id is refused")
	_done()


func _test_config() -> void:
	_section("config: map blocks, settings")
	var c := DotWeaponSpawnerConfig.new()
	c.load_dictionary(CONFIG)
	_check(c.resolve("zz_lot")["sites"]["wall"]["respawn"] == 5, "the exact map block beats the glob")
	_check(c.resolve("ZZ_other")["sites"]["wall"]["respawn"] == 10, "a glob matches case-insensitively")
	_check(c.resolve("other")["sites"]["wall"]["respawn"] == 20, "no block keeps the base")
	_check((c.resolve("x")["pools"] as Dictionary).size() == 2, "pools built")
	_check(c.set_setting("spawner_respawn_scale", "2.5") and is_equal_approx(c.respawn_scale(), 2.5), "a setting coerces")
	_check(not c.set_setting("sv_gravity", 1), "a foreign key is refused")
	_check(c.resolve("x")["game"]["shop"]["prices"]["primary"] == 500, "the free-form game block comes through")
	_check(DotWeaponSpawnerConfig.map_keys().has("spawner_enabled"), "the schema is exposed for DotMapConfig")
	_done()


func _test_cycle() -> void:
	_section("spawn, take, respawn")
	var s := _spawner("zz_lot", [_site("wall", {"max_alive": 1})])
	var events: Array = []
	s.changed.connect(func(ev: Array) -> void: events.append(ev))
	s.begin_round(100.0, 1)
	s.tick(100.0)
	_check(s.alive() == 2, "the config's max 2 spawns with the round")
	var n := s.alive()
	var inst: int = s.live().keys()[0]
	var r := s.take(inst, &"p1")
	_check(r.ok and r.value["site"] == &"wall", "take returns the item")
	_check(not s.take(inst, &"p2").ok, "a second take of one item fails")
	_check(s.alive() == n - 1, "the slot is freed")
	_check(is_equal_approx(s.seconds_until(&"wall"), 5.0), "the map block's timer, 5 s")
	s.tick(104.0)
	_check(s.alive() == n - 1, "not before the timer")
	s.tick(105.0)
	_check(s.alive() == n, "after the timer it is back")
	_check(events.size() == n + 2, "an event per spawn and take")
	var lived := _spawner("m", [_site("t", {"lifetime": 3, "respawn": 2, "item": "x"})])
	lived.begin_round(0.0, 1)
	lived.tick(0.0)
	lived.tick(3.0)
	_check(lived.alive() == 0 and is_equal_approx(lived.seconds_until(&"t"), 2.0), "an unused item expires and the timer starts")
	var once := _spawner("m", [_site("o", {"one_shot": true, "item": "x"})])
	once.begin_round(0.0, 1)
	once.tick(0.0)
	once.take(once.live().keys()[0])
	once.tick(9999.0)
	_check(once.alive() == 0 and once.seconds_until(&"o") < 0.0, "one_shot never refills")
	_done()


func _items(s: DotWeaponSpawner, round_number: int) -> Array:
	s.begin_round(0.0, round_number)
	s.tick(0.0)
	var out: Array = []
	for i: Dictionary in s.live().values():
		out.append(i["item"])
	return out


func _test_determinism() -> void:
	_section("seeded draws")
	var sites := [_site("a"), _site("b"), _site("c")]
	var one := _spawner("m", sites)
	var two := _spawner("m", sites)
	_check(_items(one, 1) == _items(two, 1), "same seed, map and round, same items")
	var seen := {}
	for r in range(1, 30):
		seen[str(_items(one, r))] = true
	_check(seen.size() > 3, "rounds differ")
	var other := _spawner("m", sites, 99)
	var differs := false
	for r in range(1, 10):
		differs = differs or _items(one, r) != _items(other, r)
	_check(differs, "another seed differs")
	var rolled := one.roll(&"a", 0)
	_check(rolled == one.roll(&"a", 0) and not rolled.is_empty(), "roll is pure")
	var counts := {}
	var big := _spawner("m", [_site("z", {"respawn": 0.0})])
	big.begin_round(0.0, 1)
	for i in 600:
		var e := big.roll(&"z", i)
		counts[e["id"]] = int(counts.get(e["id"], 0)) + 1
	_check(counts.get(&"shotgun", 0) > counts.get(&"pistol", 0) * 2, "weights show in the draws")
	_check(not counts.has(&"banned"), "a zero weight never shows")
	_done()


func _test_caps_and_settings() -> void:
	_section("caps, groups, scales")
	var s := _spawner("m", [_site("a", {"max_alive": 3, "item": "x"})])
	s.begin_round(0.0, 1)
	s.tick(0.0)
	_check(s.alive() == 3, "max_alive items at once")
	s.config.set_setting("spawner_max_scale", 0.34)
	s.begin_round(0.0, 2)
	s.tick(0.0)
	_check(s.alive() == 1, "max_scale scales it, never below one")
	s.config.set_setting("spawner_enabled", false)
	s.begin_round(0.0, 3)
	s.tick(0.0)
	_check(s.alive() == 0, "disabled spawns nothing")
	s.config.set_setting("spawner_enabled", true)
	s.config.set_setting("spawner_max_scale", 1.0)
	s.config.set_setting("spawner_respawn_scale", 0.5)
	s.begin_round(0.0, 4)
	s.tick(0.0)
	s.take(s.live().keys()[0])
	_check(is_equal_approx(s.seconds_until(&"a"), 15.0), "respawn_scale halves the 30 s default")
	var g := _spawner("m", [_site("g1", {"group": "g", "item": "x"}), _site("g2", {"group": "g", "item": "x"})])
	g.begin_round(0.0, 1)
	g.tick(0.0)
	_check(g.alive() == 1, "a group cap spans sites")
	g.take(g.live().keys()[0])
	g.tick(1000.0)
	_check(g.alive() == 1, "and refills to the cap")
	var forced := _spawner("m", [_site("f")])
	forced.config.set_setting("spawner_pool", "stock")
	forced.begin_round(0.0, 1)
	forced.tick(0.0)
	var item: Dictionary = forced.live().values()[0]
	_check(item["item"] == &"medkit" and item["kind"] == &"trader" and item["data"]["price"] == 50, "spawner_pool swaps the pool; entry data and kind ride along")
	var bad := _spawner("m", [_site("q", {"pool": "nope"})])
	bad.begin_round(0.0, 1)
	bad.tick(0.0)
	_check(bad.alive() == 0 and bad.seconds_until(&"q") >= 0.0, "an unknown pool spawns nothing now but is retried")
	bad.config.set_setting("spawner_pool", "stock")
	bad.tick(6.0)
	_check(bad.alive() == 1, "an empty draw is retried on a later tick and spawns once the pool exists")
	var dead := _spawner("m", [_site("q", {"pool": "nope"})])
	dead.begin_round(0.0, 1)
	for i in 10:
		dead.tick(float(i) * 6.0)
	_check(dead.alive() == 0 and dead.seconds_until(&"q") < 0.0, "retries are bounded; the slot then rests")
	var huge := _spawner("m", [_site("h", {"max_alive": 999999999, "item": "x"})])
	huge.begin_round(0.0, 1)
	huge.tick(0.0)
	_check(huge.alive() == huge.config.max_alive_cap and huge.config.max_alive_cap == 64, "a marker's max_alive is clamped to the configured cap")
	_done()


func _test_entities_and_marker() -> void:
	_section("map entities and the marker node")
	var s := _spawner("m", [])
	var made := s.add_entities([
		{"classname": "weapon_spawn_ak", "origin": [1.0, 2.0, 3.0], "angle": 90.0},
		{"classname": "dot_weapon_spawn", "origin": Vector3(4, 0, 0), "props": {"pool": "stock", "respawn": "7", "id": "shop"}},
		{"classname": "light", "origin": Vector3.ZERO},
	])
	_check(made.size() == 2, "only matching classes become sites")
	_check(made[0].position == Vector3(1, 2, 3) and is_equal_approx(made[0].rotation_y, PI / 2.0), "origin and angle")
	_check(made[0].pool == &"guns" and made[0].filter["tags_any"] == PackedStringArray(["primary"]), "class defaults apply")
	_check(s.site(&"shop").respawn_seconds == 7.0 and s.site(&"shop").pool == &"stock", "string props are coerced")
	var root := Node3D.new()
	add_child(root)
	var p := DotWeaponSpawnPoint.new()
	p.name = "Armoury"
	p.tags_any = "primary, heavy"
	p.max_alive = 2
	root.add_child(p)
	p.position = Vector3(5, 0, 0)
	var sites := DotWeaponSpawnPoint.collect(root)
	_check(sites.size() == 1 and sites[0].id == &"Armoury" and sites[0].max_alive == 2, "a marker is a site named by its node")
	_check(sites[0].filter["tags_any"] == PackedStringArray(["primary", "heavy"]) and sites[0].position == Vector3(5, 0, 0), "its tags and place")
	root.queue_free()
	_done()


func _test_view() -> void:
	_section("replicated view")
	var s := _spawner("m", [_site("a", {"max_alive": 2})])
	var v := DotWeaponSpawnView.new()
	var seen: Array = []
	v.appeared.connect(func(i: int, _s: StringName, _it: StringName, _k: StringName, _a: Vector3, _r: float, _d: Dictionary) -> void: seen.append(i))
	s.changed.connect(v.apply)
	s.begin_round(0.0, 1)
	s.tick(0.0)
	_check(v.items.size() == 2 and seen.size() == 2, "events mirror spawns")
	s.take(v.items.keys()[0], &"p")
	_check(v.items.size() == 1, "and takes")
	var late := DotWeaponSpawnView.new()
	late.apply_snapshot(s.snapshot())
	_check(late.items.keys() == v.items.keys() and late.waiting.has(&"a"), "a snapshot brings a late joiner level, with the countdown")
	late.apply_snapshot({"round": 2, "items": [], "waiting": []})
	_check(late.items.is_empty(), "a snapshot removes what is gone")
	late.apply([&"future_event", 1])
	_check(true, "an unknown event is ignored")
	_done()
