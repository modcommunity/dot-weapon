extends "harness.gd"

## Tick-rate, determinism, snapshot, bridge and net-sync sections of the suite.

func _reload_span(arsenal: DotWeaponArsenal, from: int) -> int:
	arsenal.begin_reload(from)
	var t := from
	while arsenal.is_reloading() and t < from + 10000:
		t += 1
		arsenal.simulate_tick(_cmd(false), _ctx(t), _cmd(false))
	return t - from


## Ticks from asking for [param slot] to being able to use it.
func _switch_span(arsenal: DotWeaponArsenal, slot: int, from: int) -> int:
	var previous := _cmd(false)
	arsenal.simulate_tick(_cmd(false, slot), _ctx(from), previous)
	var t := from
	while arsenal.is_switching() and t < from + 10000:
		t += 1
		arsenal.simulate_tick(_cmd(false), _ctx(t), previous)
	return t - from


## A catalogue whose every row says it was written at 64 Hz, as zee-dot-weapons' does.
func _authored_catalogue(rate: int) -> DotWeaponCatalogue:
	var c := DotWeaponCatalogue.new()
	for d: DotWeaponDef in [_rifle(), _pistol(), _bow(), _flamer(), _grenade()]:
		d.authored_tick_rate = rate
		c.add(d)
	return c


func _arsenal_at(catalogue: DotWeaponCatalogue, rate: int) -> DotWeaponArsenal:
	var a := _arsenal(catalogue)
	a.tick_rate = rate
	return a


func _tick_rate_spans(cat: DotWeaponCatalogue) -> Array[Node]:
	# Reload, in seconds rather than ticks.
	var r64 := _arsenal_at(cat, 64)
	var r128 := _arsenal_at(cat, 128)
	r64.give(&"rifle", false)
	r128.give(&"rifle", false)
	r64.add_ammo(&"rifle_rounds", 90)
	r128.add_ammo(&"rifle_rounds", 90)
	var reload64 := _reload_span(r64, 0)
	var reload128 := _reload_span(r128, 0)
	_check(reload64 == 120, "a reload takes its 120 ticks at 64 Hz", str(reload64))
	_check(reload128 == 240, "and the same 1.875 s (240 ticks) at 128 Hz", str(reload128))

	# Holster plus deploy.
	var sw_cat := _authored_catalogue(64)
	for id: StringName in [&"rifle", &"pistol"]:
		sw_cat.get_def(id).holster_ticks = 8
		sw_cat.get_def(id).deploy_ticks = 16
	var s64 := _arsenal_at(sw_cat, 64)
	var s128 := _arsenal_at(sw_cat, 128)
	for a: DotWeaponArsenal in [s64, s128]:
		a.give(&"pistol")
		a.give(&"rifle")
	var switch64 := _switch_span(s64, 1, 0)
	var switch128 := _switch_span(s128, 1, 0)
	_check(switch64 == 24 and switch128 == 48, "a switch takes the same wall-clock time", "%d vs %d" % [switch128, switch64])
	return [r64, r128, s64, s128]


func _tick_rate_fuse(cat: DotWeaponCatalogue) -> Array[Node]:
	# A thrown spawn's fuse leaves in RUNNING ticks, so a game flies it as given. Pin out
	# on one tick, released on the next: one tick of cook at either rate.
	var g64 := _arsenal_at(cat, 64)
	var g128 := _arsenal_at(cat, 128)
	var fuses: Array[int] = []
	for a: DotWeaponArsenal in [g64, g128]:
		a.give(&"grenade")
		a.simulate_tick(_cmd(true), _ctx(0), _cmd(false))
		var out := a.simulate_tick(_cmd(false), _ctx(1), _cmd(true))
		fuses.append(out.spawns[0].fuse_ticks if out.used and not out.spawns.is_empty() else -1)
	_check(fuses[0] == 191, "a three-second fuse cooked one tick leaves 191 at 64 Hz", str(fuses[0]))
	_check(fuses[1] == 383, "and 383 at 128 Hz, the same three seconds", str(fuses[1]))
	return [g64, g128]


func _test_tick_rate() -> void:
	_section("a weapon written at 64 Hz keeps its wall-clock timing at 128")

	# The arithmetic, on the definition.
	var d := _rifle()
	_check(d.ticks_at(6, 128) == 6, "a row naming no rate is used as written at any rate")
	d.authored_tick_rate = 64
	_check(d.ticks_at(6, 64) == 6, "a row at its own rate is unchanged")
	_check(d.ticks_at(6, 128) == 12, "and doubles at twice the rate", str(d.ticks_at(6, 128)))
	_check(d.ticks_at(1, 20) == 1, "a count above zero never rounds to zero")
	_check(d.ticks_at(0, 128) == 0, "and zero stays zero")
	_close(d.per_tick_at(0.15, 128), 0.075, "a per-tick amount halves at twice the rate", 0.00001)
	_check(d.validate().ok, "a row naming a rate validates")

	# [b]The property itself: the same second of a held trigger fires the same number of
	# shots.[/b] Before the arsenal honoured authored_tick_rate, a 64 Hz row fired 22 times
	# in a 128 Hz second against 11 at 64, which is every zee weapon in the 128 Hz sandbox.
	var cat := _authored_catalogue(64)
	var at64 := _arsenal_at(cat, 64)
	var at128 := _arsenal_at(cat, 128)
	at64.give(&"rifle")
	at128.give(&"rifle")
	var shots64 := _drive(at64, 0, 64, true).size()
	var shots128 := _drive(at128, 0, 128, true).size()
	_check(shots64 == 11, "a 64 Hz rifle fires 11 times in a second at 64 Hz", str(shots64))
	_check(shots128 == shots64, "and as many in a second at 128 Hz", "%d vs %d" % [shots128, shots64])

	# The default is what it always was: an unscaled row at 128 fires on its raw count.
	var raw := _arsenal_at(_catalogue(), 128)
	raw.give(&"rifle")
	var raw_shots := _drive(raw, 0, 128, true).size()
	_check(raw_shots == 22, "a row naming no rate still fires on its raw count", str(raw_shots))

	var spans := _tick_rate_spans(cat)

	# A charge fills in the same time, and so does what a behaviour reads per tick.
	var bow: DotWeaponDef = cat.get_def(&"bow")
	_close(at128.charge_for(bow, 64), 0.5, "half a second of draw is half a charge at 128 Hz")
	_close(at64.charge_for(bow, 64), 1.0, "and a full one at 64")
	var behaviour := at128.slot_at(1).behaviour
	_close(behaviour.scaled_per_tick(0.15), 0.075, "bloom recovers half as much per tick at 128 Hz", 0.00001)

	spans.append_array(_tick_rate_fuse(cat))

	# Prediction: a client restored from the server's snapshot mid-reload, at the same
	# rate, finishes on the same tick as the server.
	var server := _arsenal_at(cat, 128)
	var client := _arsenal_at(cat, 128)
	server.give(&"rifle", false)
	client.give(&"rifle", false)
	server.add_ammo(&"rifle_rounds", 90)
	client.add_ammo(&"rifle_rounds", 90)
	server.begin_reload(1000)
	for t in range(1001, 1100):
		server.simulate_tick(_cmd(false), _ctx(t), _cmd(false))
	var restored := client.restore(server.snapshot())
	_check(restored.ok, "a client takes the server's snapshot mid-reload")
	var server_done := -1
	var client_done := -1
	for t in range(1100, 1400):
		server.simulate_tick(_cmd(false), _ctx(t), _cmd(false))
		client.simulate_tick(_cmd(false), _ctx(t), _cmd(false))
		if server_done < 0 and not server.is_reloading():
			server_done = t
		if client_done < 0 and not client.is_reloading():
			client_done = t
	_check(server_done == 1240 and client_done == server_done, "and both finish on tick 1240", "%d / %d" % [server_done, client_done])

	for a: Node in [at64, at128, raw, server, client] + spans:
		_drop(a)

	_done()


func _test_determinism() -> void:
	_section("two machines agree")

	# The same commands into two arsenals must produce identical pellets. This is the
	# property a predicting client and a resolving server depend on, and the one that
	# fails silently: the symptom is "hit registration feels bad", never an error.
	var spread_cat := _catalogue()
	var sc: DotWeaponBallistics = spread_cat.get_def(&"rifle").tuning
	sc.spread = 3.0
	sc.pellets = 8

	var a := _arsenal(spread_cat)
	var b := _arsenal(spread_cat)
	a.give(&"rifle")
	b.give(&"rifle")

	var fired_a := _drive(a, 500, 40, true, 7)
	var fired_b := _drive(b, 500, 40, true, 7)

	_check(fired_a.size() == fired_b.size(), "both fired the same number of times")

	var identical := true
	for i in range(fired_a.size()):
		var pa: Array[Vector3] = fired_a[i].shots[0].pellets
		var pb: Array[Vector3] = fired_b[i].shots[0].pellets
		if pa.size() != pb.size():
			identical = false
			break
		for j in range(pa.size()):
			if pa[j].distance_to(pb[j]) > 0.0:
				identical = false
				break

	_check(identical, "and every pellet went in exactly the same direction")

	# A different shooter must scatter differently, or every player's spread is the
	# same and the pattern is learnable across the whole server.
	var c := _arsenal(spread_cat)
	c.give(&"rifle")
	var fired_c := _drive(c, 500, 40, true, 9)
	var differs := false
	for j in range(fired_a[0].shots[0].pellets.size()):
		if fired_a[0].shots[0].pellets[j].distance_to(fired_c[0].shots[0].pellets[j]) > 0.0:
			differs = true
			break
	_check(differs, "a different shooter scatters differently")

	# Every pellet must actually be inside the stated cone, and spread around it.
	var quadrants := [false, false, false, false]
	var worst := 0.0
	for outcome in fired_a:
		for pellet: Vector3 in outcome.shots[0].pellets:
			worst = maxf(worst, rad_to_deg(Vector3.FORWARD.angle_to(pellet)))
			if absf(pellet.x) > 0.00001 or absf(pellet.y) > 0.00001:
				var q := (0 if pellet.x >= 0.0 else 1) + (0 if pellet.y >= 0.0 else 2)
				quadrants[q] = true

	_check(worst <= 3.0001, "no pellet leaves the cone", "%.4f degrees" % worst)
	_check(
		quadrants.count(true) == 4,
		"and pellets reach all four quadrants: a maximum-angle check alone passes for "
		+ "a half-moon, which is exactly the bug this family already shipped once",
		str(quadrants)
	)

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _test_idle_tick() -> void:
	_section("an idle tick skips the context and changes nothing")

	var cat := _catalogue()
	(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom = 2.0
	(cat.get_def(&"rifle").tuning as DotWeaponBallistics).bloom_recovery = 0.2
	var slow := _arsenal(cat)
	var fast := _arsenal(cat)

	for a in [slow, fast]:
		a.give(&"rifle")
		a.give(&"pistol")
		a.give(&"bow")
		a.give(&"knife")

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var skipped := 0
	var same := true
	var previous: DotWeaponCommand = null

	for tick in range(1200):
		var cmd := DotWeaponCommand.new()
		# Long quiet stretches (the case being skipped) between bursts of every button.
		if (tick / 40) % 3 == 0:
			cmd.set_button(DotWeaponCommand.BUTTON_ATTACK, rng.randf() < 0.7)
			cmd.set_button(DotWeaponCommand.BUTTON_RELOAD, rng.randf() < 0.03)
			cmd.slot = rng.randi_range(1, 4) if rng.randf() < 0.05 else 0

		var want := slow.simulate_tick(cmd, _ctx(tick), previous)
		var got: DotWeaponOutcome
		if fast.is_idle_for(cmd, previous):
			got = fast.idle_tick()
			skipped += 1
		else:
			got = fast.simulate_tick(cmd, _ctx(tick), previous)

		if want.used != got.used or want.kind != got.kind or want.refusal != got.refusal \
				or var_to_str(slow.snapshot()) != var_to_str(fast.snapshot()):
			same = false
			break

		previous = cmd

	_check(same, "outcomes and snapshots agree on every tick of a mixed stream")
	_check(skipped > 300, "and the idle path ran for much of it", str(skipped))

	_drop(slow)
	_drop(fast)
	_done()


func _test_snapshot() -> void:
	_section("a snapshot survives a correction")

	var a := _arsenal()
	a.give(&"rifle")
	a.give(&"bow")

	_drive(a, 0, 6 * 5, true)
	var magazine := a.current().magazine
	_check(magazine < 30, "the magazine is spent", str(magazine))

	var snap := a.snapshot()

	_drive(a, 100, 6 * 5, true)
	_check(a.current().magazine < magazine, "and spent further")

	_check(a.restore(snap).ok, "a snapshot restores")
	_check(a.current().magazine == magazine, "putting the magazine back")

	# The behaviour's own state has to travel too. A snapshot that carried the
	# magazine and not the bow's draw reconciles a correction by silently un-drawing
	# it, which reads to the player as the bow firing by itself.
	var b := _arsenal()
	b.give(&"bow")
	b.select(3, 0)
	_drive(b, 0, 1, false)

	var rod := _arsenal()
	rod.give(&"rod")
	rod.select(7, 0)
	_drive(rod, 0, 1, false)
	_drive(rod, 10, 2, true)

	var behaviour: DotWeaponBehaviour = rod.current().behaviour
	var after_use: int = behaviour.charges_left()
	_check(after_use == 2, "a behaviour's own state changes when it is used", str(after_use))

	var rod_snap := rod.snapshot()
	_drive(rod, 40, 2, true)
	_check(behaviour.charges_left() == 1, "and changes again")

	rod.restore(rod_snap)
	_check(
		(rod.current().behaviour as DotWeaponBehaviour).charges_left() == 2,
		"and a restore puts the behaviour's state back, not only the ammunition",
		str((rod.current().behaviour as DotWeaponBehaviour).charges_left())
	)

	# Restoring onto an arsenal carrying something else rebuilds what it should hold.
	var c := _arsenal()
	c.give(&"knife")
	_check(c.restore(snap).ok, "a snapshot restores onto a different arsenal")
	_check(c.carries(&"rifle"), "rebuilding what it should be carrying")
	_check(not c.carries(&"knife"), "and dropping what it should not")

	_drop(a)
	_drop(b)
	_drop(c)
	_drop(rod)
	_done()


func _test_loadout_bridge() -> void:
	_section("filling from a loadout")

	var a := _arsenal()

	# The shape dot-loadout's resolve() returns, without naming dot-loadout: an array
	# of dictionaries with an arsenal_slot and an item that has an id.
	var resolved: Array = [
		{"slot": &"primary", "arsenal_slot": 1, "item": _fake_item(&"rifle"), "count": 1},
		{"slot": &"sidearm", "arsenal_slot": 2, "item": _fake_item(&"pistol"), "count": 1},
		{"slot": &"hat", "arsenal_slot": 0, "item": _fake_item(&"party_hat"), "count": 1},
	]

	var res := DotWeaponLoadoutBridge.fill(a, resolved)
	_check(res.ok, "a loadout fills an arsenal")
	_check(int(res.value) == 2, "with the weapons in it", str(res.value))
	_check(
		a.carries(&"rifle") and a.carries(&"pistol"),
		"both of them"
	)
	_check(
		not a.carries(&"party_hat"),
		"and the hat is skipped rather than failing the whole loadout: a loadout "
		+ "carries cosmetics and perks as well as weapons"
	)

	# A game whose item ids differ from its weapon ids passes a mapping.
	var b := _arsenal()
	var mapped: Array = [
		{"arsenal_slot": 1, "item": _fake_item(&"item_ak"), "count": 1},
	]
	var res2 := DotWeaponLoadoutBridge.fill(b, mapped, {&"item_ak": &"rifle"})
	_check(res2.ok and b.carries(&"rifle"), "an item id maps to a weapon id")

	# Nothing recognisable is a refusal, not a silently empty arsenal.
	var c := _arsenal()
	var junk: Array = [{"arsenal_slot": 1, "item": _fake_item(&"nothing"), "count": 1}]
	_check(
		not DotWeaponLoadoutBridge.fill(c, junk).ok,
		"a loadout naming no weapon we know is refused, rather than leaving a player "
		+ "holding nothing and wondering why"
	)

	# A server can check before the player is in the world.
	var clash: Array = [
		{"arsenal_slot": 1, "item": _fake_item(&"rifle"), "count": 1},
		{"arsenal_slot": 1, "item": _fake_item(&"rifle2"), "count": 1},
	]
	var clash_cat := _catalogue()
	var r2 := _rifle()
	r2.id = &"rifle2"
	clash_cat.add(r2)
	_check(
		not DotWeaponLoadoutBridge.check(clash_cat, clash).ok,
		"two weapons wanting one slot are caught on the join path, where refusing is "
		+ "cheap"
	)

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _fake_item(id: StringName) -> RefCounted:
	var item := _FakeItem.new()
	item.id = id
	return item


class _FakeItem extends RefCounted:
	var id: StringName = &""
	var count: int = 1


func _test_inventory_bridge() -> void:
	_section("agreeing with a bag")

	var a := _arsenal()
	a.give(&"rifle")

	var bag: Array = [_fake_stack(&"box_rifle", 45), _fake_stack(&"bandage", 3)]
	var pools := {&"box_rifle": &"rifle_rounds"}

	DotWeaponInventoryBridge.load_ammo(a, bag, pools)
	_check(
		a.ammo().count(&"rifle_rounds") == 45,
		"a bag's ammunition is read into the pool",
		str(a.ammo().count(&"rifle_rounds"))
	)
	_check(
		a.ammo().count(&"bandage") == 0,
		"and a bandage is not ammunition"
	)

	# Called twice, it must not double. Adding rather than setting turns every refresh
	# into a duplication bug, and this is called on a schedule.
	DotWeaponInventoryBridge.load_ammo(a, bag, pools)
	_check(
		a.ammo().count(&"rifle_rounds") == 45,
		"reading it twice does not double it"
	)

	var counts := DotWeaponInventoryBridge.ammo_counts(a)
	_check(
		int(counts.get(&"rifle_rounds", 0)) == 45,
		"and what the bag should hold comes back for the caller to apply"
	)

	var carried := DotWeaponInventoryBridge.carried(a)
	_check(carried.size() == 1, "what is carried is reportable")
	_check(bool(carried[0]["in_hand"]), "including which one is in hand")

	_drop(a)
	_done()


func _fake_stack(id: StringName, count: int) -> RefCounted:
	var item := _FakeItem.new()
	item.id = id
	item.count = count
	return item


func _test_net_sync() -> void:
	_section("the wire")

	var specs := DotWeaponNetSync.specs()
	_check(specs.size() == 3, "the bridge describes the weapon half", str(specs.size()))

	var owner_only := 0
	for spec in specs:
		if bool(spec["owner_only"]):
			owner_only += 1
	_check(
		owner_only == 2,
		"ammunition is owner-only: exact counts are information an opponent should "
		+ "not have, and sending them is how a modified client knows when to push"
	)

	var a := _arsenal()
	a.give(&"rifle")
	a.give(&"pistol")

	var fake := _FakeNet.new()
	DotWeaponNetSync.pull(a, fake)
	_check(fake.net_slot == 1, "the held slot replicates")
	_check(fake.net_magazine == 30, "and the magazine")
	_check(fake.net_reserve == 90, "and the reserve")

	var b := _arsenal()
	b.give(&"rifle")
	b.give(&"pistol")
	b.select(2, 0)
	_drive(b, 0, 1, false)
	_check(b.current_slot() == 2, "a second arsenal is on another slot")

	DotWeaponNetSync.push(fake, b)
	_check(b.current_slot() == 1 or b.is_switching(), "which the wire corrects")

	# A correction writes the counts; an ordinary snapshot must not.
	b.restore(a.snapshot())
	b.current().magazine = 4
	DotWeaponNetSync.correct_ammo(fake, b)
	_check(
		b.current().magazine == 30,
		"a correction puts the predicted magazine right",
		str(b.current().magazine)
	)

	fake.free()
	_drop(a)
	_drop(b)
	_done()


class _FakeNet extends Object:
	var net_slot: int = 0
	var net_magazine: int = 0
	var net_reserve: int = 0
