extends "selftest/sections_content.gd"

## dot-weapon's self-test. Headless, no network, no scene but this one.

const CHECKS := 386


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-weapon self-test")
	print("")

	_test_definition()
	_test_catalogue()
	_test_id_order()
	_test_content_follow()
	_test_behaviour_resolution()
	_test_carrying_and_switching()
	_test_cadence()
	_test_ammunition()
	_test_reloading()
	_test_charge_and_bow()
	_test_melee()
	_test_beam()
	_test_thrown()
	_test_determinism()
	_test_idle_tick()
	_test_tick_rate()
	_test_snapshot()
	_test_loadout_bridge()
	_test_inventory_bridge()
	_test_net_sync()
	_test_attachments()
	_test_attachments_wire()
	_test_extension_point()
	_test_player_bridge()
	_test_profiles()
	_test_overlay()
	_test_carry()
	_test_spread_rules()

	print("")
	print("%d sections entered, %d finished, %d passed, %d failed" % [
		_sections_entered, _sections_finished, _passed, _failed
	])

	for line in _failures:
		print("  FAIL  %s" % line)

	# A runtime error in a section's last statement leaves both section counters satisfied with checks
	# missing, so the total is checked too.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 or _sections_entered != _sections_finished else 0)


func _test_definition() -> void:
	_section("a weapon is a document")

	var d := _rifle()
	_check(d.validate().ok, "a well-formed definition validates")

	var no_id := _rifle()
	no_id.id = &""
	_check(not no_id.validate().ok, "one with no id does not")

	var no_behaviour := _rifle()
	no_behaviour.behaviour_path = ""
	_check(
		not no_behaviour.validate().ok,
		"and neither does one with no behaviour: a weapon that does nothing is a "
		+ "typo rather than a design"
	)

	var not_a_script := _rifle()
	not_a_script.behaviour_path = "res://weapons/rifle.tscn"
	_check(
		not not_a_script.validate().ok,
		"a behaviour that names a scene rather than a script is refused"
	)

	var bad_reserve := _rifle()
	bad_reserve.reserve = 500
	bad_reserve.reserve_max = 100
	_check(
		not bad_reserve.validate().ok,
		"a reserve above its own cap is refused, rather than silently clamped"
	)

	var bad_charge := _bow()
	bad_charge.charge_ticks = 0
	_check(
		not bad_charge.validate().ok,
		"a charged weapon with no charge time is refused"
	)

	# Validation must not need the script, because a server checking a catalogue at
	# boot may legitimately not have mounted the pack carrying it yet.
	var unmounted := _rifle()
	unmounted.behaviour_path = "res://not/mounted/yet.gd"
	_check(
		unmounted.validate().ok,
		"a behaviour path that does not resolve yet still validates: a content pack "
		+ "is mounted after boot, and boot is when the table is checked"
	)

	_check(d.charge_at(0) == 0.0, "charge starts at nothing")
	_close(_bow().charge_at(32), 0.5, "and is linear to full")
	_check(_bow().charge_at(9999) == 1.0, "holding past full stays at full")

	_check(d.uses_magazine(), "a magazine-fed weapon says so")
	_check(not _bow().uses_magazine(), "and one that feeds from the reserve does not")

	_done()


func _test_catalogue() -> void:
	_section("the catalogue")

	var c := _catalogue()
	_check(c.validate().ok, "a good table validates")
	_check(c.size() == 7, "with every row", str(c.size()))

	var dupe := _catalogue()
	dupe.add(_rifle())
	_check(
		not dupe.validate().ok,
		"two weapons sharing an id are refused: an id is what a loadout names, so a "
		+ "duplicate silently hands a player the wrong one"
	)

	_check(c.has(&"bow"), "a known id is found")
	_check(not c.has(&"trebuchet"), "an unknown one is not")
	_check(c.get_def(&"bow").slot == 3, "and comes back with its row")

	_check(c.ids_in_slot(1) == ([&"rifle"] as Array[StringName]), "slots are indexed")
	_check(
		c.ids_with_tag(&"primary") == ([&"rifle"] as Array[StringName]),
		"and so are tags, which is how a mode bans a class of weapon without naming one"
	)

	_check(c.validate_behaviours().ok, "every behaviour in this table resolves")

	var missing := DotWeaponCatalogue.new()
	var ghost := _rifle()
	ghost.behaviour_path = "res://fixtures/nothing_here.gd"
	missing.add(ghost)
	_check(missing.validate().ok, "a missing behaviour passes the document check")
	var behaviours := missing.validate_behaviours()
	_check(not behaviours.ok, "and fails the resolution check")
	_check(
		behaviours.error.message.contains("nothing_here.gd"),
		"by name, with the path in the message",
		behaviours.error.message
	)

	_done()


## Twenty fresh names whose StringName order is not their text order, and the same
## names sorted as text.
##
## Which pointer a fresh name gets is the allocator's call, so interning in a shuffled
## (or reversed) order can still come out in text order by luck. So each attempt draws
## new names -- one already interned keeps its place -- until the StringName order is
## not text order; the caller's first check states that it is not.
func _names_out_of_text_order(rng: RandomNumberGenerator, prefix: String) -> Dictionary:
	var ids: Array[String] = []
	var by_text: Array[String] = []
	var interned: Array[StringName] = []
	var name_order: Array[String] = []
	for attempt in range(8):
		ids.clear()
		interned.clear()
		while ids.size() < 20:
			var id := "%s%d_" % [prefix, attempt]
			for _i in range(6):
				id += char(97 + rng.randi() % 26)
			if not ids.has(id):
				ids.append(id)
		by_text = ids.duplicate()
		by_text.sort()
		var shuffled := ids.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var held: String = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = held
		for id: String in shuffled:
			interned.append(StringName(id))
		var as_names := interned.duplicate()
		as_names.sort_custom(func(a: StringName, b: StringName) -> bool: return a < b)
		name_order.clear()
		for id: StringName in as_names:
			name_order.append(String(id))
		if name_order != by_text:
			break
	return {"interned": interned, "by_text": by_text, "name_order": name_order}


## ids() and pools() are lists other programs read: a console's completion offers ids()
## (game-arena's `give`), and zee-dot-weapons compares ids() with its own id list. They
## sorted with sort(), which orders StringNames by where each was interned, not by text,
## so the order differed per process.
##
## [b]Armed on purpose.[/b] The seven fixture ids can fall in text order by luck, so this
## uses names drawn by [method _names_out_of_text_order], and the first check says their
## StringName order really is not text order -- without it, a pass here would not prove
## the sort compares text. On the old sort() the last three fail.
func _test_id_order() -> void:
	_section("ids and pools are in text order")

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var drawn := _names_out_of_text_order(rng, "zz_weapon_order")
	var interned: Array[StringName] = drawn.interned
	var by_text: Array[String] = drawn.by_text
	var name_order: Array[String] = drawn.name_order
	_check(name_order != by_text,
		"armed: these names compared as StringNames are not in text order",
		", ".join(name_order.slice(0, 4)))

	# Added in intern order, so a sort that did nothing would also fail.
	var c := DotWeaponCatalogue.new()
	var pool := DotWeaponAmmo.new()
	for id: StringName in interned:
		var def := _rifle()
		def.id = id
		c.add(def)
		pool.add(id, 1)

	var listed: Array[String] = []
	for id: StringName in c.ids():
		listed.append(String(id))
	_check(listed == by_text, "catalogue ids() lists every weapon by id as text",
		", ".join(listed.slice(0, 4)))

	var pools: Array[String] = []
	for id: StringName in pool.pools():
		pools.append(String(id))
	_check(pools == by_text, "ammo pools() lists every pool by name as text",
		", ".join(pools.slice(0, 4)))

	# describe() maps ids(), so it follows.
	var described: Array = c.describe().get("ids", [])
	_check(described == (by_text as Array), "and describe() shows them in that order")

	_done()


func _test_behaviour_resolution() -> void:
	_section("behaviours come from a path")

	var c := _catalogue()

	var made := c.instantiate(&"rifle")
	_check(made.ok, "a behaviour is built from its path")
	_check(made.value is DotWeaponHitscan, "as the right type")
	_check((made.value as DotWeaponBehaviour).def.id == &"rifle", "bound to its row")

	var again := c.instantiate(&"rifle")
	_check(
		again.value != made.value,
		"two carriers get two instances: a behaviour holds state, and sharing one "
		+ "makes one player's bow charge when another draws"
	)

	var unknown := c.instantiate(&"trebuchet")
	_check(not unknown.ok, "an unknown weapon fails rather than returning null")

	_done()


func _test_carrying_and_switching() -> void:
	_section("carrying and switching")

	var a := _arsenal()
	_check(a.is_ready(), "an arsenal with a valid catalogue sets up")

	var bad := DotWeaponArsenal.new()
	add_child(bad)
	_check(not bad.setup().ok, "one with no catalogue does not")
	_drop(bad)

	_check(a.give(&"rifle").ok, "a weapon can be given")
	_check(a.carries(&"rifle"), "and is carried")
	_check(a.current_slot() == 1, "the first one given goes into the hand")
	_check(a.current().magazine == 30, "with a full magazine")
	_check(a.ammo().count(&"rifle_rounds") == 90, "and its reserve")

	a.give(&"pistol")
	_check(a.current_slot() == 1, "a second weapon does not steal the hand")
	_check(a.slots() == ([1, 2] as Array[int]), "both are carried")

	# A switch is a holster then a deploy, and takes the ticks the definitions say.
	var slow := _catalogue()
	slow.get_def(&"rifle").holster_ticks = 10
	slow.get_def(&"pistol").deploy_ticks = 20
	var b := _arsenal(slow)
	b.give(&"rifle")
	b.give(&"pistol")

	_check(b.select(2, 100), "a switch starts")
	_check(b.is_switching(), "and is in progress")

	_drive(b, 100, 9, false)
	_check(b.current_slot() == 1, "the old weapon stays in hand while holstering")

	_drive(b, 109, 2, false)
	_check(b.current_slot() == 2, "then the new one arrives", str(b.current_slot()))
	_check(b.is_switching(), "and is still deploying")

	_drive(b, 111, 21, false)
	_check(not b.is_switching(), "until the deploy finishes")

	# Using during a deploy must do nothing, or a switch is free.
	var c := _arsenal(slow)
	c.give(&"rifle")
	c.give(&"pistol")
	c.select(2, 0)
	# 10 ticks of holster, then 20 of deploy. Firing anywhere in those 30 must do
	# nothing, or a switch costs nothing and quick-switching is free damage.
	var during := _drive(c, 0, 30, true)
	_check(
		during.is_empty(),
		"a weapon cannot be used while it is being switched to",
		"%d uses got through" % during.size()
	)
	var after := _drive(c, 30, 10, true)
	_check(not after.is_empty(), "and can be used once it has arrived")

	# [b]A slot asked for on every tick still arrives.[/b] A networked command carries the
	# slot it wants each tick; a switch restarted by every one of them never finished.
	var held := _arsenal(slow)
	held.give(&"rifle")
	held.give(&"pistol")
	for i in range(40):
		var asking := _cmd(false)
		asking.slot = 2
		var _outcome := held.simulate_tick(asking, _ctx(200 + i, 1), null)
	_check(held.current_slot() == 2 and not held.is_switching(),
		"a slot asked for on every tick arrives, and is not restarted by each request",
		"slot %d, switching %s" % [held.current_slot(), str(held.is_switching())])
	_drop(held)

	_check(a.take(1).ok, "a weapon can be taken away")
	_check(not a.carries(&"rifle"), "and is gone")
	_check(a.current_slot() == 2, "and the hand falls back to another slot")

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _test_cadence() -> void:
	_section("cadence")

	# Automatic: holding produces a use every use_interval_ticks.
	var auto := _arsenal()
	auto.give(&"rifle")
	var held := _drive(auto, 0, 60, true)
	_check(
		held.size() == 10,
		"an automatic weapon fires once per interval while held",
		"%d in 60 ticks at one per 6" % held.size()
	)

	# Semi-automatic: holding produces exactly one.
	var semi := _arsenal()
	semi.give(&"pistol")
	semi.select(2, 0)
	_drive(semi, 0, 1, false)
	var once := _drive(semi, 1, 60, true)
	_check(
		once.size() == 1,
		"a semi-automatic weapon fires once however long the button is held",
		str(once.size())
	)

	# Burst: one press, burst_count uses, at the burst interval.
	var burst_cat := _catalogue()
	var br := burst_cat.get_def(&"rifle")
	br.fire_mode = DotWeaponDef.Fire.BURST
	br.burst_count = 3
	br.burst_interval_ticks = 2
	br.use_interval_ticks = 30
	var burst := _arsenal(burst_cat)
	burst.give(&"rifle")

	var fired := _drive(burst, 0, 10, true)
	_check(fired.size() == 3, "a burst fires exactly its count", str(fired.size()))
	_check(
		fired[1].shots[0].tick - fired[0].shots[0].tick == 2,
		"at the burst interval, not the weapon interval: one interval for both makes "
		+ "a three-round burst indistinguishable from automatic fire",
		str(fired[1].shots[0].tick - fired[0].shots[0].tick)
	)

	_drop(auto)
	_drop(semi)
	_drop(burst)
	_done()


func _test_ammunition() -> void:
	_section("ammunition")

	var a := _arsenal()
	a.give(&"rifle")

	# An Array, not an int: GDScript lambdas capture locals by value, so a captured
	# counter is incremented on a copy and stays zero here for ever.
	var dry := [0]
	a.dry_used.connect(func(_s: int) -> void: dry[0] += 1)

	var fired := _drive(a, 0, 6 * 31, true)
	_check(fired.size() == 30, "a magazine holds exactly its rounds", str(fired.size()))
	_check(a.current().magazine == 0, "and empties")
	_check(dry[0] > 0, "then reports a dry trigger rather than firing silently")

	# Pools are shared by name, which is what lets two weapons feed from one box.
	var shared := _catalogue()
	shared.get_def(&"pistol").ammo_type = &"rifle_rounds"
	shared.get_def(&"pistol").reserve = 0
	var b := _arsenal(shared)
	b.give(&"rifle")
	b.give(&"pistol")
	_check(
		b.ammo().count(&"rifle_rounds") == 90,
		"two weapons declaring one ammo type share one reserve",
		str(b.ammo().count(&"rifle_rounds"))
	)

	# A pickup that does not fit must report what it left behind.
	var pool := DotWeaponAmmo.new()
	pool.set_cap(&"rifle_rounds", 100)
	pool.set_count(&"rifle_rounds", 96)
	_check(
		pool.add(&"rifle_rounds", 30) == 4,
		"a pickup returns how many rounds actually fitted: a caller that assumed it "
		+ "all went in creates ammunition"
	)
	_check(pool.count(&"rifle_rounds") == 100, "and the pool stops at its cap")

	_check(pool.take(&"rifle_rounds", 250) == 100, "taking more than exists takes what there is")
	_check(pool.count(&"rifle_rounds") == 0, "leaving none")

	# Infinite reserve still empties a magazine.
	var inf := _catalogue()
	inf.get_def(&"rifle").infinite_reserve = true
	var c := _arsenal(inf)
	c.give(&"rifle")
	var shots := _drive(c, 0, 6 * 31, true)
	_check(
		shots.size() == 30,
		"an infinite reserve still has to reload: the magazine is the limit",
		str(shots.size())
	)

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _test_reloading() -> void:
	_section("reloading")

	var a := _arsenal()
	a.give(&"rifle")

	var started := [0]
	var finished := [0]
	a.reload_started.connect(func(_s: int) -> void: started[0] += 1)
	a.reload_finished.connect(func(_s: int, _r: int) -> void: finished[0] += 1)

	_drive(a, 0, 6 * 10, true)
	var spent := a.current().magazine
	_check(spent < 30, "firing spends the magazine", str(spent))

	_check(a.begin_reload(100), "a reload starts")
	_check(a.is_reloading(), "and is in progress")

	_drive(a, 100, 119, false)
	_check(a.is_reloading(), "still running before its time")

	_drive(a, 219, 2, false)
	_check(not a.is_reloading(), "and finishes on time")
	_check(a.current().magazine == 30, "with a full magazine", str(a.current().magazine))
	_check(
		a.ammo().count(&"rifle_rounds") == 90 - (30 - spent),
		"taking exactly what it put in from the reserve",
		str(a.ammo().count(&"rifle_rounds"))
	)
	_check(started[0] == 1 and finished[0] == 1, "reporting both ends once",
		"%d started, %d finished" % [started[0], finished[0]])

	# Firing cancels a reload rather than being refused by it.
	a.begin_reload(400)
	var during := _drive(a, 400, 3, true)
	_check(
		not during.is_empty(),
		"using a weapon mid-reload fires instead of being refused: the alternative "
		+ "is a player held hostage by a reload they started by accident"
	)
	_check(not a.is_reloading(), "and cancels the reload")

	# Holding the trigger through an empty magazine must still reload.
	#
	# This is the check that was missing when the bug shipped: every reload test above
	# releases the trigger first, and a bot does not. Cancelling the reload before
	# asking whether the weapon can pay made a held trigger restart the reload on every
	# cadence tick, so it never finished and the weapon never fired again.
	var holder := _arsenal()
	holder.give(&"rifle")
	var before_empty := _drive(holder, 0, 6 * 31, true)
	_check(before_empty.size() == 30, "a held trigger empties the magazine")
	_check(holder.current().magazine == 0, "and it is empty")

	var after := _drive(holder, 6 * 31, 400, true)
	_check(
		not after.is_empty(),
		"and holding it through the reload fires again once the reload lands",
		"%d uses after the magazine ran out" % after.size()
	)
	_check(
		holder.current().magazine > 0 or after.size() > 0,
		"rather than restarting the reload for ever on every cadence tick"
	)
	_drop(holder)

	# Per-round reloading keeps going until the magazine is full.
	var shell_cat := _catalogue()
	var sh := shell_cat.get_def(&"pistol")
	sh.reload_per_round = true
	sh.reload_ticks = 10
	sh.reload_start_ticks = 5
	sh.magazine = 6
	sh.reserve = 30
	var b := _arsenal(shell_cat)
	b.give(&"pistol")
	b.select(2, 0)
	_drive(b, 0, 1, false)
	b.current().magazine = 0

	b.begin_reload(0)
	_drive(b, 0, 200, false)
	_check(
		b.current().magazine == 6,
		"a per-round reload fills the whole magazine rather than loading one shell "
		+ "and standing there",
		str(b.current().magazine)
	)

	_drop(a)
	_drop(b)
	_done()


func _test_charge_and_bow() -> void:
	_section("a bow is one row, not a class")

	var a := _arsenal()
	a.give(&"bow")
	a.select(3, 0)
	_drive(a, 0, 1, false)

	var full_draws := [0]
	a.charge_full.connect(func(_s: int) -> void: full_draws[0] += 1)

	# Hold for a full draw, then release.
	var previous: DotWeaponCommand = null
	var outcome: DotWeaponOutcome = null

	for i in range(70):
		var cmd := _cmd(true)
		a.simulate_tick(cmd, _ctx(100 + i), previous)
		previous = cmd

	_check(full_draws[0] == 1, "a full draw is announced once", str(full_draws[0]))

	var release := _cmd(false)
	outcome = a.simulate_tick(release, _ctx(170), previous)

	_check(outcome.used, "releasing a drawn bow looses an arrow")
	_check(outcome.kind == DotWeaponOutcome.KIND_SPAWN, "as a spawn, not a hitscan")
	_check(outcome.spawns.size() == 1, "one arrow")

	var arrow := outcome.spawns[0]
	_close(arrow.speed(), 90.0, "at full speed when fully drawn", 0.5)
	_close(arrow.damage, 70.0, "and full damage", 0.5)
	_check(arrow.gravity_scale == 1.0, "an arrow falls, unlike a rocket")

	# A tap is a weak arrow, which is the whole point of a charged weapon.
	var b := _arsenal()
	b.give(&"bow")
	b.select(3, 0)
	_drive(b, 0, 1, false)

	var p2 := _cmd(true)
	b.simulate_tick(p2, _ctx(200), null)
	for i in range(7):
		var c2 := _cmd(true)
		b.simulate_tick(c2, _ctx(201 + i), p2)
		p2 = c2

	var weak := b.simulate_tick(_cmd(false), _ctx(208), p2)
	_check(weak.used, "a tapped bow still looses something")
	_check(
		weak.spawns[0].speed() < 40.0,
		"much slower",
		"%.1f m/s" % weak.spawns[0].speed()
	)
	_check(
		weak.spawns[0].damage < 30.0,
		"and much weaker, which is what makes holding the draw worth the vulnerability",
		"%.1f" % weak.spawns[0].damage
	)

	# A minimum draw refuses rather than releasing weakly.
	var strict := _catalogue()
	strict.get_def(&"bow").charge_requires_min = true
	strict.get_def(&"bow").min_charge = 0.5
	var c := _arsenal(strict)
	c.give(&"bow")
	c.select(3, 0)
	_drive(c, 0, 1, false)

	var p3 := _cmd(true)
	c.simulate_tick(p3, _ctx(300), null)
	var refused := c.simulate_tick(_cmd(false), _ctx(302), p3)
	_check(not refused.used, "a bow below its minimum draw refuses")
	_check(
		c.ammo().count(&"arrows") == 20,
		"and costs no arrow",
		str(c.ammo().count(&"arrows"))
	)

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _test_melee() -> void:
	_section("melee is a very short shot")

	var a := _arsenal()
	a.give(&"knife")
	a.select(4, 0)
	_drive(a, 0, 1, false)

	var swings := _drive(a, 10, 2, true)
	_check(swings.size() == 1, "a swing happens")

	var swing := swings[0]
	_check(swing.kind == DotWeaponOutcome.KIND_SWING, "and says it is a swing")
	_check(swing.shots.size() == 1, "producing one shot")
	_check(swing.shots[0].pellet_count == 5, "sampled across the arc")
	_close(swing.shots[0].max_range, 2.0, "reaching only as far as the blade")
	_check(
		swing.shots[0].fixed_pattern,
		"on a fixed pattern: a swing that scattered differently every time would "
		+ "sometimes miss a target standing still in front of it"
	)
	_check(
		swing.shots[0].pellets.size() == 5,
		"and the arc directions are built",
		str(swing.shots[0].pellets.size())
	)

	# A knife costs no ammunition and needs none declared.
	_check(a.current().def.ammo_type == &"", "a knife declares no ammunition")
	var many := 0
	var prev: DotWeaponCommand = null
	for i in range(200):
		# Tapped, not held: a knife is semi-automatic, so holding it is one swing.
		var cmd := _cmd(i % 25 == 0)
		if a.simulate_tick(cmd, _ctx(1000 + i), prev).used:
			many += 1
		prev = cmd
	_check(many >= 6, "and swings for as long as you like", str(many))

	_drop(a)
	_done()


func _test_beam() -> void:
	_section("a beam ramps while it is held")

	var a := _arsenal()
	a.give(&"flamer")
	a.select(5, 0)
	_drive(a, 0, 1, false)

	var ticks := _drive(a, 10, 40, true)
	_check(ticks.size() == 10, "a held beam works every interval", str(ticks.size()))

	var first := ticks[0].shots[0].damage
	var last := ticks[ticks.size() - 1].shots[0].damage
	_check(first < last, "ramping up as it is held", "%.2f then %.2f" % [first, last])
	_close(last, 6.0, "to its full output", 0.1)

	# Releasing announces the stop even though it produced nothing, because a looping
	# sound and a particle stream both need an off switch.
	var previous := _cmd(true)
	a.simulate_tick(previous, _ctx(200), null)
	var stop := a.simulate_tick(_cmd(false), _ctx(201), previous)
	_check(not stop.used, "releasing produces no damage")
	_check(stop.events.size() == 1, "but does announce the beam stopping")

	_drop(a)
	_done()


func _test_thrown() -> void:
	_section("a grenade's fuse starts when the pin comes out")

	var a := _arsenal()
	a.give(&"grenade")
	a.select(6, 0)
	_drive(a, 0, 1, false)

	# A quick throw keeps almost the whole fuse.
	var p := _cmd(true)
	a.simulate_tick(p, _ctx(100), null)
	for i in range(9):
		var c := _cmd(true)
		a.simulate_tick(c, _ctx(101 + i), p)
		p = c

	var quick := a.simulate_tick(_cmd(false), _ctx(110), p)
	_check(quick.used, "a grenade is thrown")
	_check(quick.kind == DotWeaponOutcome.KIND_THROW, "as a throw")
	_check(
		quick.spawns[0].fuse_ticks > 170,
		"with most of its fuse left",
		str(quick.spawns[0].fuse_ticks)
	)

	# A cooked one keeps much less.
	var b := _arsenal()
	b.give(&"grenade")
	b.select(6, 0)
	_drive(b, 0, 1, false)

	var p2 := _cmd(true)
	b.simulate_tick(p2, _ctx(200), null)
	for i in range(120):
		var c2 := _cmd(true)
		b.simulate_tick(c2, _ctx(201 + i), p2)
		p2 = c2

	var cooked := b.simulate_tick(_cmd(false), _ctx(321), p2)
	_check(
		cooked.spawns[0].fuse_ticks < quick.spawns[0].fuse_ticks,
		"cooking spends the fuse",
		"%d vs %d" % [cooked.spawns[0].fuse_ticks, quick.spawns[0].fuse_ticks]
	)

	# Cooking all the way goes off in the hand, which is the cost of cooking at all.
	var c3 := _arsenal()
	c3.give(&"grenade")
	c3.select(6, 0)
	_drive(c3, 0, 1, false)

	var p3 := _cmd(true)
	c3.simulate_tick(p3, _ctx(400), null)
	for i in range(200):
		var cc := _cmd(true)
		c3.simulate_tick(cc, _ctx(401 + i), p3)
		p3 = cc

	var boom := c3.simulate_tick(_cmd(false), _ctx(601), p3)
	_check(boom.used, "a fully cooked grenade still leaves the definition")
	_check(boom.spawns[0].fuse_ticks == 0, "with no fuse left")
	_check(
		boom.spawns[0].velocity == Vector3.ZERO,
		"and no velocity: it went off in the hand, which is what cooking risks"
	)
	_check(boom.events.size() == 1, "and that is announced")

	_drop(a)
	_drop(b)
	_drop(c3)
	_done()


## Ticks for one weapon to finish a reload started on [param from], driving no buttons.


func _test_carry() -> void:
	_section("carry weight")
	var cat := _catalogue()
	var twin := _pistol()
	twin.id = &"pistol2"
	cat.add(twin)
	cat.get_def(&"rifle").weight = 12.0
	cat.get_def(&"pistol").weight = 4.0
	twin.weight = 5.0
	cat.get_def(&"knife").weight = 1.0
	var a := _arsenal(cat)
	_check(a.give(&"rifle").ok and a.carried_weight() == 0.0 and a.capacity() == INF, "with no carry rules nothing weighs and nothing is refused")
	_check(a.give(&"pistol2").ok and a.weapons_in(2).size() == 1, "and a slot holds one weapon")
	a.clear()
	var carry := DotWeaponCarry.new()
	a.carry = carry
	_check(a.give(&"rifle").ok and a.carried_weight() == 0.0, "a disabled carry weighs nothing")
	carry.enabled = true
	carry.base_limit = 20.0
	carry.slot_capacity = 2
	_check(is_equal_approx(a.carried_weight(), 12.0) and is_equal_approx(a.capacity(), 20.0), "enabled, weights count and the limit is the base")
	_check(a.give(&"pistol").ok and is_equal_approx(a.carried_weight(), 16.0), "a weapon under the limit is taken")
	var refused := a.give(&"pistol2")
	_check(not refused.ok and refused.error.code == DotError.CODE_QUOTA and refused.error.message.contains("Too heavy"), "an over-weight pickup is refused with a message")
	_check(a.weapons_in(2).size() == 1 and not a.carries(&"pistol2"), "and nothing changed")
	_check(not a.equip_backpack(4) and a.equip_backpack(1) and is_equal_approx(a.capacity(), 30.0), "a backpack raises the limit, a tier that does not exist is refused")
	_check(not a.equip_backpack(1), "and the same tier again is not an upgrade")
	_check(a.give(&"pistol2").ok and a.weapons_in(2).size() == 2, "the same pickup now fits and stows beside the first")
	_check(a.slot_at(2).id() == &"pistol2" and a.weapons_in(2)[1].id() == &"pistol", "the new weapon is in hand, the old behind it")
	_check(a.carries(&"pistol") and a.carries(&"pistol2"), "carries sees stowed weapons")
	_check(a.select(2, 0) and a.is_switching(), "slot 2 selected")
	_drive(a, 1, 60, false)
	_check(a.current_slot() == 2, "slot 2 is in hand")
	_check(a.cycle_slot(100) and a.slot_at(2).id() == &"pistol" and a.weapons_in(2)[1].id() == &"pistol2", "the slot key again brings the next weapon")
	_check(a.is_switching(), "and it deploys")
	_check(not a.cycle_slot(101) or a.slot_at(2).id() == &"pistol2", "cycling twice returns")
	var snap := a.snapshot()
	var b := _arsenal(cat)
	b.carry = carry
	_check(b.restore(snap).ok and b.weapons_in(2).size() == 2 and b.backpack_tier == 1, "a snapshot carries the shelf and the backpack")
	_check(is_equal_approx(b.carried_weight(), a.carried_weight()), "and the same weight")
	carry.set_modifier(&"heavy_box", 2.0)
	_check(is_equal_approx(carry.weight_factor(), 2.0) and a.over_by() > 0.0, "a modifier doubling weights puts the carrier over")
	_check(a.speed_scale() < 1.0 and a.speed_scale() >= carry.slow_floor, "SLOW mode slows within the floor")
	carry.over_limit = DotWeaponCarry.OverLimit.DROP
	_check(is_equal_approx(a.speed_scale(), 1.0), "DROP mode does not slow")
	var dropped := a.enforce_limit()
	_check(a.over_by() <= 0.0001 and not dropped.is_empty() and a.current() != null, "DROP sheds weapons until under, keeping the one in hand")
	carry.clear_modifier(&"heavy_box")
	carry.set_modifier(&"depression", 1.0, 0.5)
	_check(is_equal_approx(a.capacity(), 15.0), "a limit modifier halves the capacity")
	carry.set_modifier(&"depression", 1.0, 1.0, 5.0)
	_check(is_equal_approx(a.capacity(), 35.0), "a flat addition raises it")
	carry.clear_modifiers()
	carry.multiplier = 0.5
	_check(is_equal_approx(carry.weight_of(cat.get_def(&"rifle")), 6.0), "the global multiplier scales a weight")
	carry.over_limit = DotWeaponCarry.OverLimit.SLOW
	_check(carry.speed_scale(10.0, 20.0) == 1.0 and carry.speed_scale(40.0, 20.0) == 0.5, "speed scale is 1 under, floored over")
	var from_file := DotWeaponDef.new()
	DotWeaponProfiles.apply_common(from_file, {"weight": 7.5})
	_check(is_equal_approx(from_file.weight, 7.5), "weight is a profile key")
	_check(str(DotWeaponProfiles.schema()).contains("weight"), "and in the schema")
	var t := a.take(2)
	_check(t.ok and a.carried_weight() < 16.0, "take removes a weapon")
	_done()


func _test_spread_rules() -> void:
	_section("movement-dependent spread")

	var rules := DotWeaponSpreadRules.new()
	var ctx := _ctx(1)
	_check(is_equal_approx(rules.target_factor(ctx), 1.0), "off: every posture is factor 1")
	rules.enabled = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_stand * rules.mult_hip), "still at the hip")
	ctx.speed = 2.0
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_walk), "walking")
	ctx.speed = 6.0
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_run), "running")
	ctx.airborne = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_air), "in the air, speed ignored")
	ctx.sliding = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_slide), "sliding")
	ctx.airborne = false
	ctx.sliding = false
	ctx.speed = 0.0
	ctx.crouched = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_crouch), "crouched tightens")
	ctx.aiming = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_crouch * rules.mult_aim), "aimed and crouched tightest")
	_check(is_equal_approx(rules.apply(5.0, 10.0), rules.max_spread), "the cap holds")
	_check(rules.set_cvar("sv_spread_mult_run", "2.5") and is_equal_approx(rules.mult_run, 2.5), "a cvar sets a multiplier")
	_check(rules.set_cvar("sv_spread_mult_run", "99") and is_equal_approx(rules.mult_run, 10.0), "and is clamped to its range")
	_check(not rules.set_cvar("sv_nonsense", "1") and not rules.set_cvar("sv_spread_mult_run", "x"), "unknown names and values are refused")

	var a := _arsenal()
	a.give(&"rifle")
	var tuning := a.current().def.tuning as DotWeaponBallistics
	tuning.spread = 1.0
	tuning.spread_moving = 1.0
	tuning.spread_airborne = 1.0
	a.spread_rules = rules
	rules.mult_run = 3.0
	rules.mult_hip = 1.0
	rules.mult_crouch = 1.0
	rules.recovery = 64.0
	var moving := _ctx(2)
	moving.speed = 6.0
	var out := a.simulate_tick(_cmd(true), moving, null)
	_check(out.used and is_equal_approx(out.shots[0].spread, 3.0), "a run triples the gun's own spread", str(out.shots[0].spread))
	_check(is_equal_approx(a.spread_now(), 3.0), "and the crosshair reads the same cone")
	var still := _ctx(3)
	var _t := a.simulate_tick(_cmd(false), still, null)
	_check(a.spread_now() > 1.0 and a.spread_now() < 3.0, "settles over ticks, not at once", str(a.spread_now()))
	for i in range(80):
		var _s := a.simulate_tick(_cmd(false), _ctx(4 + i), null)
	_check(is_equal_approx(a.spread_now(), 1.0), "and recovers to the base", str(a.spread_now()))
	var aimed := _ctx(100)
	var aim_cmd := _cmd(false)
	aim_cmd.set_button(DotWeaponCommand.BUTTON_AIM, true)
	var _u := a.simulate_tick(aim_cmd, aimed, null)
	_check(is_equal_approx(a.spread_now(), 0.5), "aiming halves it", str(a.spread_now()))
	rules.enabled = false
	var _v := a.simulate_tick(_cmd(false), _ctx(101), null)
	_check(is_equal_approx(a.spread_now(), 1.0), "disabled, the gun keeps its own spread")
	_drop(a)
	_done()
