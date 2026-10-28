extends "selftest/sections_content.gd"

## dot-weapon's self-test. Headless, no network, no scene but this one.

const CHECKS := 522


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
	_test_spread_ladder()
	_test_recoil_rules()
	_test_fire_modes()
	_test_muzzle()
	_test_ballistics()
	_test_bullets()
	_test_hitscan_unchanged()
	_test_bullet_bridge()
	_test_ammo_hitzones()

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
	ctx.sprinting = true
	_check(is_equal_approx(rules.target_factor(ctx), rules.mult_sprint), "sprinting")
	ctx.sprinting = false
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
	var sprint_ctx := _ctx(200)
	sprint_ctx.sprinting = true
	sprint_ctx.sprint_blocks_aim = true
	var _w := a.simulate_tick(aim_cmd, sprint_ctx, null)
	_check(not sprint_ctx.aiming, "sprinting with sprint_blocks_aim drops the aim")
	var reload_cmd := _cmd(false)
	reload_cmd.set_button(DotWeaponCommand.BUTTON_RELOAD, true)
	var _x := a.simulate_tick(reload_cmd, sprint_ctx, null)
	_check(not a.is_reloading(), "and refuses a reload")
	sprint_ctx.sprint_blocks_aim = false
	sprint_ctx.tick = 201
	var _y := a.simulate_tick(reload_cmd, sprint_ctx, null)
	_check(a.is_reloading() and sprint_ctx.sprinting, "sprinting alone leaves the reload and the aim alone")
	var fired := _arsenal()
	fired.give(&"rifle")
	var fire_ctx := _ctx(300)
	fire_ctx.sprinting = true
	fire_ctx.sprint_blocks_fire = true
	var blocked := fired.simulate_tick(_cmd(true), fire_ctx, null)
	_check(not blocked.used, "sv_sprint_shoot 0 refuses the trigger while sprinting")
	fire_ctx.sprint_blocks_fire = false
	fire_ctx.tick = 301
	_check(fired.simulate_tick(_cmd(true), fire_ctx, null).used, "and sprinting may shoot when it is allowed")
	_drop(fired)
	_drop(a)
	_done()


## Standing < walking < running < sprinting and airborne; crouched and aimed tighter. Through the
## arsenal's spread_now, with the data a shotgun ships (spread_moving below spread, crouched 1+).
func _test_spread_ladder() -> void:
	_section("spread ladder: still < walk < run < air")
	for shotgun in [false, true]:
		var rules := DotWeaponSpreadRules.new()
		rules.enabled = true
		rules.recovery = 0.0
		var a := _arsenal()
		a.give(&"rifle")
		var t := a.current().def.tuning as DotWeaponBallistics
		t.spread = 4.0 if shotgun else 0.5
		t.spread_moving = 0.5 if shotgun else 2.0
		t.spread_airborne = 1.0 if shotgun else 4.0
		t.spread_crouched = 4.0 if shotgun else 0.5
		a.spread_rules = rules
		var tick := 10
		var got := {}
		for key: String in ["still", "walk", "run", "sprint", "air", "crouch", "aim"]:
			var c := _ctx(tick)
			tick += 1
			c.speed = {"walk": 2.0, "run": 6.0, "sprint": 7.0}.get(key, 0.0)
			c.sprinting = key == "sprint"
			c.airborne = key == "air"
			c.crouched = key == "crouch"
			var cmd := _cmd(false)
			if key == "aim":
				cmd.set_button(DotWeaponCommand.BUTTON_AIM, true)
			var _o := a.simulate_tick(cmd, c, null)
			got[key] = a.spread_now()
		var tag := " (shotgun data)" if shotgun else ""
		_check(got["still"] < got["walk"] and got["walk"] < got["run"], "still < walk < run" + tag, str(got))
		_check(got["run"] < got["sprint"] and got["run"] < got["air"], "run < sprint and air" + tag, str(got))
		_check(got["crouch"] < got["still"] and got["aim"] < got["still"], "crouched and aimed are tighter" + tag, str(got))
		_drop(a)
	var bal := DotWeaponBallistics.new()
	var sniper := bal.crosshair_scale_for([&"primary", &"scoped"])
	var smg := bal.crosshair_scale_for([&"primary", &"automatic"])
	var plain := bal.crosshair_scale_for([&"primary"])
	_check(sniper > plain and plain > smg, "gap scale: sniper > usual gun > automatic", "%s %s %s" % [sniper, plain, smg])
	bal.crosshair_scale = 2.0
	_check(is_equal_approx(bal.crosshair_scale_for([&"automatic"]), 2.0), "an explicit crosshair_scale beats the class default")
	var xs := DotWeaponDef.new()
	DotWeaponProfiles.apply_common(xs, {"crosshair_scale": 3.0})
	_check(is_equal_approx(xs.crosshair_scale, 3.0) and str(DotWeaponProfiles.schema()).contains("crosshair_scale"), "crosshair_scale is a schema field the def takes")
	var xa := _arsenal()
	xa.give(&"rifle")
	var xdef := xa.current().def
	xdef.crosshair_scale = 0.0
	(xdef.tuning as DotWeaponBallistics).crosshair_scale = 1.5
	_check(is_equal_approx(xa.crosshair_scale(), 1.5), "def field 0 falls back to extra.tuning crosshair_scale")
	xdef.crosshair_scale = 0.5
	_check(is_equal_approx(xa.crosshair_scale(), 0.5), "the def field beats the tuning path")
	_drop(xa)
	_done()


func _burst(rules: DotWeaponRecoilRules, shots: int, start_tick: int) -> Array:
	var a := _arsenal()
	a.give(&"rifle")
	a.recoil_rules = rules
	var out: Array = []
	for i in range(shots):
		var o := a.simulate_tick(_cmd(true), _ctx(start_tick + i * 6), null)
		out.append(o)
		var _r := a.simulate_tick(_cmd(false), _ctx(start_tick + i * 6 + 1), null)
	_drop(a)
	return out


func _test_recoil_rules() -> void:
	_section("per-weapon recoil patterns")

	var rules := DotWeaponRecoilRules.new()
	_check(DotWeaponRecoilRules.of(null) == null, "no arsenal, no rules")
	var off := _burst(rules, 3, 10)
	_check(off[0].recoil == Vector2(0.5, 0.2) and not off[0].recoil_signed, "off: the flat kick")
	rules.enabled = true
	rules.horizontal = 1.0
	var tuning := _rifle().tuning as DotWeaponBallistics
	_check(tuning.recoil_build > 0.0, "ballistics carry a build")

	var run1 := _burst(rules, 6, 10)
	var run2 := _burst(rules, 6, 10)
	var same := true
	for i in range(6):
		same = same and run1[i].recoil == run2[i].recoil
	_check(same, "the pattern repeats exactly from the same seed")
	_check(run1[0].recoil_signed and run1[0].recoil_recovery > 0.0, "the outcome carries a signed kick and its recovery")
	_check(run1[0].recoil.x > 0.0 and is_equal_approx(run1[0].recoil.x, 0.5), "first shot is the base kick", str(run1[0].recoil))
	_check(run1[5].recoil.x > run1[0].recoil.x, "sustained fire builds", str(run1[5].recoil.x))
	_check(run1[5].recoil.x <= 0.5 * (1.0 + tuning.recoil_build_max) + 0.001, "and is capped")
	var yaws := {}
	for i in range(6):
		yaws[snappedf(run1[i].recoil.y, 0.0001)] = true
	_check(yaws.size() > 2, "sideways drift varies shot to shot")
	_check(is_equal_approx(DotWeaponRecoilRules.drift(7, 3), DotWeaponRecoilRules.drift(7, 3)) and DotWeaponRecoilRules.drift(7, 3) != DotWeaponRecoilRules.drift(8, 3), "drift is a pure function of seed and index")
	_check(DotWeaponRecoilRules.seed_for(null, &"ak") == DotWeaponRecoilRules.seed_for(null, &"ak") and DotWeaponRecoilRules.seed_for(null, &"ak") != DotWeaponRecoilRules.seed_for(null, &"m4"), "an id seeds stably")

	var gap := _burst(rules, 2, 10)
	_check(is_equal_approx(gap[1].recoil.x, 0.5 * (1.0 + tuning.recoil_build)), "the second shot of a burst is built up")

	var a := _arsenal()
	a.give(&"rifle")
	a.recoil_rules = rules
	var first := a.simulate_tick(_cmd(true), _ctx(10), null)
	var _r := a.simulate_tick(_cmd(false), _ctx(11), null)
	var later := a.simulate_tick(_cmd(true), _ctx(10 + 64 * 3), null)
	_check(is_equal_approx(later.recoil.x, first.recoil.x) and is_equal_approx(later.recoil.y, first.recoil.y), "released long enough, the pattern starts over")
	_drop(a)

	var ctx := _ctx(1)
	var base := rules.posture(ctx)
	ctx.aiming = true
	var aimed := rules.posture(ctx)
	ctx.crouched = true
	_check(aimed < base and rules.posture(ctx) < aimed, "aim and crouch tighten it")
	ctx = _ctx(1)
	ctx.speed = 6.0
	var moving := rules.posture(ctx)
	ctx.airborne = true
	_check(moving > base and rules.posture(ctx) > moving, "moving and air widen it")

	rules.scale = 2.0
	var doubled := _burst(rules, 1, 10)
	_check(is_equal_approx(doubled[0].recoil.x, 1.0), "the master scale multiplies")
	rules.scale = 1.0
	rules.punch = 0.0
	var split := _burst(rules, 1, 10)
	_check(split[0].recoil == Vector2.ZERO and split[0].shots[0].direction != Vector3.FORWARD, "punch 0 leaves the view alone and offsets the bullet")
	var again := _burst(rules, 1, 10)
	_check(split[0].shots[0].direction.is_equal_approx(again[0].shots[0].direction), "the bullet offset repeats too")
	rules.punch = 1.0
	_check(_burst(rules, 1, 10)[0].shots[0].direction.is_equal_approx(Vector3.FORWARD), "punch 1 keeps the bullet on the view")

	var view := DotWeaponRecoil.new()
	for o: DotWeaponOutcome in run1:
		view.kick_outcome(o)
	var peak := view.offset().x
	_check(peak > 2.0, "the view climbs over a burst", str(peak))
	view.advance(1.0)
	_check(view.offset().x < peak * 0.1, "and settles on release", str(view.offset().x))

	_check(rules.set_cvar("sv_recoil_scale", "0.5") and is_equal_approx(rules.scale, 0.5), "a cvar sets a multiplier")
	_check(rules.set_cvar("sv_recoil_punch", "9") and is_equal_approx(rules.punch, 1.0), "and is clamped")
	_check(rules.set_cvar("sv_recoil", "0") and not rules.enabled and DotWeaponRecoilRules.of(null) == null, "sv_recoil switches it off")
	_done()


func _test_fire_modes() -> void:
	_section("fire modes")

	var cat := _catalogue()
	var rifle := cat.get_def(&"rifle")
	rifle.fire_modes = PackedStringArray(["auto", "semi", "burst"])
	rifle.burst_count = 3
	rifle.burst_interval_ticks = 2
	var a := _arsenal(cat)
	a.give(&"rifle")
	a.give(&"pistol")
	var seen: Array[int] = []
	a.fire_mode_changed.connect(func(_s: int, m: int) -> void: seen.append(m))

	_check(a.fire_mode() == DotWeaponDef.Fire.AUTO, "the first listed mode is the default")
	var auto_shots := _drive(a, 0, 60, true).size()
	_check(auto_shots == 10, "auto fires on every interval while held", str(auto_shots))

	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.SEMI, "cycling goes auto to semi")
	var semi_shots := _drive(a, 100, 60, true).size()
	_check(semi_shots == 1, "semi fires once per press however long it is held", str(semi_shots))

	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.BURST, "then semi to burst")
	var burst_shots := _drive(a, 200, 40, true)
	_check(burst_shots.size() == 3, "burst fires exactly three shots per press", str(burst_shots.size()))
	_check(a.cycle_fire_mode() and a.fire_mode() == DotWeaponDef.Fire.AUTO, "burst wraps back to auto")
	_check(seen == [DotWeaponDef.Fire.SEMI, DotWeaponDef.Fire.BURST, DotWeaponDef.Fire.AUTO], "fire_mode_changed announces each change", str(seen))

	_check(not a.set_fire_mode(DotWeaponDef.Fire.CHARGE), "a mode the gun does not list is refused")
	_check(a.fire_mode() == DotWeaponDef.Fire.AUTO, "and the mode is unchanged")

	# The button is a rising edge: held over many ticks it cycles once.
	var before := a.fire_mode()
	var prev: DotWeaponCommand = null
	for i in range(5):
		var c := DotWeaponCommand.new()
		c.set_button(DotWeaponCommand.BUTTON_FIRE_MODE, true)
		var _o := a.simulate_tick(c, _ctx(300 + i), prev)
		prev = c
	_check(a.fire_mode() != before and a.fire_mode() == DotWeaponDef.Fire.SEMI, "the fire-mode button cycles once per press")

	# A pistol without a list has no choice and refuses.
	_check(a.select(2, 400), "switch to the pistol")
	var _d := _drive(a, 401, 2, false)
	_check(a.fire_modes_available().size() == 1 and not a.cycle_fire_mode(), "a gun with one mode refuses to cycle")

	# Selection belongs to the weapon instance and survives a switch and a snapshot.
	var _s := a.select(1, 500)
	var snap := a.snapshot()
	var b := _arsenal(cat)
	var res := b.restore(snap)
	_check(res.ok and b.fire_mode() == DotWeaponDef.Fire.SEMI, "the selection survives a weapon switch and a snapshot")
	_drop(a)
	_drop(b)
	_done()


func _test_muzzle() -> void:
	_section("the muzzle flash bridge falls back without dot-fx or a display")

	var d := _rifle()
	_check(DotWeaponMuzzle.flash_name(d) == "" and DotWeaponMuzzle.flash_name(null) == "", "no profile size is an empty name")
	d.params[DotWeaponMuzzle.KEY] = "big"
	_check(DotWeaponMuzzle.flash_name(d) == "big", "the profile's size name is read")
	var host := Node3D.new()
	add_child(host)
	_check(not DotWeaponMuzzle.warm(host, "rifle", d), "warm builds nothing here (no dot-fx or headless)")
	_check(not DotWeaponMuzzle.warm(null, "rifle"), "warm with no host is false")
	_check(DotWeaponMuzzle.attach(host, "rifle", d) == null and host.get_child_count() == 0, "attach returns null and adds nothing here")
	_check(DotWeaponMuzzle.warm_done() and DotWeaponMuzzle.spare_count() == 0, "nothing warming, nothing waiting")
	host.queue_free()
	_done()


func _test_ballistics() -> void:
	_section("ballistic trajectory")
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 800.0
	b.max_range = 1200.0
	_check(DotWeaponTrajectory.is_simulated(b) and not DotWeaponTrajectory.is_simulated(DotWeaponBallistics.new()), "velocity 0 stays hitscan")
	var carbine := DotWeaponBallistics.new()
	carbine.muzzle_velocity = 350.0
	var sniper := DotWeaponBallistics.new()
	sniper.muzzle_velocity = 900.0
	sniper.drag = 0.0002
	sniper.max_range = 1200.0
	var last := {}
	for w in [carbine, b, sniper]:
		var d100 := DotWeaponTrajectory.drop_at(w, 100.0)
		var d300 := DotWeaponTrajectory.drop_at(w, 300.0)
		_check(d300.drop > d100.drop and d100.drop > 0.0, "drop grows with range", "%f %f" % [d100.drop, d300.drop])
		_check(d300.time > d100.time and d300.speed < w.muzzle_velocity, "it takes time and slows")
		last = d300
	var nodrag := DotWeaponBallistics.new()
	nodrag.muzzle_velocity = 500.0
	nodrag.drag = 0.0
	var t100 := DotWeaponTrajectory.drop_at(nodrag, 100.0)
	_close(t100.drop, 0.5 * 9.8 * 0.2 * 0.2, "no drag: drop is g*t^2/2 at t = 0.2 s", 0.04)
	var wall := func(from: Vector3, to: Vector3) -> Dictionary:
		if from.z > -400.0 and to.z <= -400.0:
			return {"position": Vector3(from.x, from.y, -400.0)}
		return {}
	var shot := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, wall)
	_check(not shot.hit.is_empty(), "a bullet at 900 m/s does not tunnel a paper-thin wall at 400 m")
	_close(shot.position.z, -400.0, "and stops on it")
	var open_shot := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, Callable())
	_check(open_shot.hit.is_empty() and open_shot.distance >= sniper.max_range - 1.0, "with nothing in the way it runs out at max range")
	var again := DotWeaponTrajectory.fly(Vector3.ZERO, Vector3(0, 0, -1), sniper, wall)
	_check(again.position == shot.position and again.time == shot.time, "the flight is deterministic")
	var fb := DotWeaponBallistics.new()
	fb.max_range = 100.0
	fb.falloff_start = 20.0
	fb.falloff_min = 0.5
	_close(DotWeaponTrajectory.falloff(fb, 10.0) + DotWeaponTrajectory.falloff(fb, 100.0), 1.5, "falloff: full inside, half at max range")
	fb.penetration = 0.4
	_close(DotWeaponTrajectory.through(fb, 0.1), 0.75, "a thin wall costs a quarter")
	_close(DotWeaponTrajectory.through(fb, 0.5), 0.0, "a thick one stops it")
	var pitch := DotWeaponTrajectory.solve_pitch(sniper, 300.0, 0.0)
	_check(pitch > 0.0 and pitch < 0.02, "the solver raises the bore for drop", str(pitch))
	var aim := DotWeaponTrajectory.lead(sniper, Vector3.ZERO, Vector3(0, 0, -300), Vector3(5, 0, 0))
	_check(aim.x > 1.0 and aim.y > 0.0, "bots lead a mover and hold over for drop", str(aim))
	_check(is_nan(DotWeaponTrajectory.solve_pitch(carbine, 100000.0)), "out of reach has no solution")
	_done()


func _test_bullets() -> void:
	_section("ballistic bullets and rules")
	var rules := DotWeaponBallisticsRules.new()
	_check(not rules.enabled, "ballistics default OFF")
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.max_range = 500.0
	b.tracer_interval = 2
	b.falloff_start = 0.0
	b.falloff_min = 0.5
	var bullets := DotWeaponBullets.new()
	bullets.rules = rules
	bullets.tick_rate = 60
	add_child(bullets)
	_check(bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b) == 0, "off: spawn refuses, weapon stays hitscan")
	_check(rules.set_cvar("sv_ballistics", "1") and rules.enabled, "sv_ballistics switches it on")
	_check(not rules.set_cvar("sv_nonsense", "1"), "unknown cvar refused")
	_check(rules.set_cvar("sv_ballistics_max_bullets", "3") and rules.max_bullets == 3.0, "cap is a cvar")
	var hitscan := DotWeaponBallistics.new()
	_check(bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), hitscan) == 0, "velocity 0 stays hitscan when on")
	var log := {"hits": [], "rewinds": [], "restores": 0, "tracers": 0}
	bullets.cast_fn = func(from: Vector3, to: Vector3, _o: int) -> Dictionary:
		if from.z > -100.0 and to.z <= -100.0:
			return {"position": Vector3(from.x, from.y, -100.0)}
		return {}
	bullets.rewind_fn = func(t: float) -> void: log.rewinds.append(t)
	bullets.restore_fn = func() -> void: log.restores += 1
	bullets.hit.connect(func(id: int, _o: int, _i: Dictionary, d: float, m: float, _b: DotWeaponBallistics) -> void: log.hits.append([id, d, m]))
	bullets.tracer.connect(func(_id: int, _f: Vector3, _t: Vector3) -> void: log.tracers += 1)
	var id1 := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b, 6.0)
	var id2 := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b, 0.0)
	var id3 := bullets.spawn(2, Vector3.ZERO, Vector3(0, 0, -1), b)
	_check(id1 > 0 and id2 > id1 and id3 > id2 and bullets.count() == 3, "three bullets in flight")
	_check(bullets.spawn(2, Vector3.ZERO, Vector3(0, 0, -1), b) == 0, "the cap holds")
	bullets.step(100.0)
	_check(log.hits.is_empty(), "600 m/s takes more than one tick to cross 100 m")
	for t in range(1, 12):
		bullets.step(100.0 + t)
	_check(log.hits.size() == 3 and bullets.count() == 0, "all three hit the wall and are gone", str(log.hits.size()))
	_check(log.hits[0][1] > 99.0 and log.hits[0][1] < 101.0, "at 100 m")
	_check(log.hits[0][2] < 1.0 and log.hits[0][2] > 0.5, "with the falloff multiplier", str(log.hits[0][2]))
	_check(log.rewinds.size() > 0 and is_equal_approx(log.rewinds[0], 94.0), "the lagged bullet rewound to now minus its lag", str(log.rewinds))
	_check(log.restores == log.rewinds.size(), "every rewind restored")
	_check(log.tracers > 0, "every second bullet of an owner is a tracer")
	rules.set_cvar("sv_ballistics_max_bullets", "512")
	rules.set_cvar("sv_ballistics_velocity", "2")
	var fast := bullets.spawn(1, Vector3.ZERO, Vector3(0, 0, -1), b)
	var before: int = log.hits.size()
	bullets.step(200.0)
	bullets.step(201.0)
	_check(log.hits.size() > before or bullets.count() == 1, "the velocity multiplier applies", str(fast))
	var expired := {"n": 0}
	bullets.expired.connect(func(_id: int) -> void: expired.n += 1)
	bullets.cast_fn = Callable()
	for t in range(0, 40):
		bullets.step(300.0 + t)
	_check(expired.n >= 1 and bullets.count() == 0, "past max range it expires")
	var many := 0
	rules.set_cvar("sv_ballistics_velocity", "1")
	for i in 400:
		many += 1 if bullets.spawn(i % 20, Vector3.ZERO, Vector3(0, 0, -1), b) > 0 else 0
	var t0 := Time.get_ticks_usec()
	bullets.step(400.0)
	var us := Time.get_ticks_usec() - t0
	_check(many == 400 and us < 100000, "400 bullets step in one node, cheaply", "%d us" % us)
	_done()


## The shot an arsenal makes, as text, with the given ballistics rules and muzzle velocity.
func _shot_text(rules: DotWeaponBallisticsRules, velocity: float) -> Array:
	var a := _arsenal()
	a.give(&"rifle")
	a.ballistics_rules = rules
	((a.catalogue.get_def(&"rifle") as DotWeaponDef).tuning as DotWeaponBallistics).muzzle_velocity = velocity
	var o := a.simulate_tick(_cmd(true), _ctx(10), null)
	var shot: DotShot = o.shots[0]
	var text := "%s|%s|%s|%s|%s|%s|%s|%s" % [shot.origin, shot.direction, shot.spread, shot.pellets, shot.damage, shot.max_range, o.recoil, shot.pellet_count]
	var deferred := shot.deferred
	_drop(a)
	return [text, deferred]


func _test_hitscan_unchanged() -> void:
	_section("hitscan is unchanged with ballistics off")
	var base := _shot_text(null, 0.0)
	var off := DotWeaponBallisticsRules.new()
	_check(_shot_text(off, 0.0) == base, "rules present but off: identical shot")
	_check(_shot_text(off, 800.0) == base, "rules off, weapon has a velocity: identical shot")
	var on := DotWeaponBallisticsRules.new()
	on.enabled = true
	_check(_shot_text(on, 0.0) == base, "rules on, no velocity: identical shot")
	var fast := _shot_text(on, 800.0)
	_check(fast[1] and not base[1], "rules on and a velocity: the shot is deferred to a bullet")
	_check(fast[0] == base[0], "and is otherwise the same shot")
	var recoil := DotWeaponRecoilRules.new()
	_check(recoil is DotWeaponCvarRules and recoil.cvar_name(&"enabled") == "sv_recoil" and recoil.cvar_name(&"scale") == "sv_recoil_scale", "recoil rules keep their cvar names on the shared base")
	_check(recoil.set_cvar("sv_recoil_scale", "2") and recoil.scale == 2.0, "and still set from cvars")
	_check(recoil.describe().has("scale"), "and describe")
	_done()


func _bridge_target(z: float) -> Node3D:
	var body := Node3D.new()
	body.position = Vector3(0.0, 0.0, z)
	var health := DotHealth.new()
	health.max_health = 100.0
	health.regen_per_second = 0.0
	body.add_child(health)
	var set_node := DotHitboxSet.new()
	set_node.bounds_offset = Vector3(0.0, 0.9, 0.0)
	set_node.bounds_radius = 1.4
	var chest := DotHitbox.new()
	chest.group = DotHitGroup.CHEST
	chest.shape = DotHitbox.Shape.CAPSULE
	chest.radius = 0.4
	chest.height = 1.6
	chest.position = Vector3(0.0, 1.0, 0.0)
	set_node.add_child(chest)
	body.add_child(set_node)
	add_child(body)
	return body


func _bridge_shot(tick: int, pellets: int, dir: Vector3 = Vector3.FORWARD) -> DotShot:
	var shot := DotShot.make(&"rifle", 1, tick, 0)
	shot.origin = Vector3(0.0, 1.0, 0.0)
	shot.direction = dir
	shot.pellet_count = pellets
	shot.fixed_pattern = true
	shot.damage = 20.0
	shot.max_range = 200.0
	shot.deferred = true
	shot.scatter()
	return shot


func _test_bullet_bridge() -> void:
	_section("bullet bridge against a real combat manager")
	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.with_floor(0.0)
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	manager.config.tick_rate = 64
	add_child(manager)
	var victim := _bridge_target(-30.0)
	var set_node: DotHitboxSet = null
	for c in victim.get_children():
		if c is DotHitboxSet:
			set_node = c
	set_node.register_with(manager, 2)
	var health: DotHealth = null
	for c in victim.get_children():
		if c is DotHealth:
			health = c
	manager.register_health(2, health)
	_check(manager.entity_id_of(victim) == 0 or manager.entity_id_of(victim) == 2, "entity_id_of is public")

	var rules := DotWeaponBallisticsRules.new()
	rules.enabled = true
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.bullet_gravity = 0.0
	b.drag = 0.0
	b.max_range = 200.0
	var bridge := DotWeaponBulletBridge.new()
	add_child(bridge)
	bridge.setup(manager, rules, 64)
	var hits: Array = []
	bridge.bullet_hit.connect(func(_id: int, d: DotDamage) -> void: hits.append(d))

	var shot := bridge.resolve_shot(_bridge_shot(100, 1), b, -1.0)
	_check(shot.deferred and bridge.bullets.count() == 1 and hits.is_empty(), "a deferred shot launches a bullet and does no damage yet")
	for t in range(1, 12):
		bridge.tick(100.0 + t)
	_check(hits.size() == 1 and bridge.bullets.count() == 0, "the bullet hits the target and is gone", str(hits.size()))
	_check(health.health == 80.0, "damage applied once", str(health.health))
	_check(hits[0].victim == 2 and hits[0].hit_group == DotHitGroup.CHEST and hits[0].distance > 28.0, "to the right victim, group and distance")

	hits.clear()
	var _miss := bridge.resolve_shot(_bridge_shot(110, 1, Vector3(0.5, 0.0, -1.0)), b, -1.0)
	for t in range(1, 40):
		bridge.tick(110.0 + t)
	_check(hits.is_empty() and health.health == 80.0 and bridge.bullets.count() == 0, "a bullet aimed away misses and expires")

	var _two := bridge.resolve_shot(_bridge_shot(120, 3), b, -1.0)
	_check(bridge.bullets.count() == 3, "three pellets, three bullets")
	for t in range(1, 12):
		bridge.tick(120.0 + t)
	_check(hits.size() >= 1 and hits.size() <= 3 and bridge.bullets.count() == 0, "pellets resolve", str(hits.size()))
	var expected := 80.0 - 20.0 * hits.size()
	_check(is_equal_approx(health.health, expected), "each hitting pellet damages once", "%s vs %s" % [health.health, expected])

	# Lag compensation: the target has since stepped aside; the shooter saw it in line at tick 100.
	health.health = 100.0
	hits.clear()
	victim.position.x = 5.0
	var rewinds: Array = []
	manager.rewind_fn = func(t: float) -> void:
		rewinds.append(t)
		victim.position.x = 0.0 if t < 112.0 else 5.0
	manager.restore_fn = func() -> int:
		victim.position.x = 5.0
		return 0
	var lagged := _bridge_shot(106, 1)
	var _l := bridge.resolve_shot(lagged, b, 100.0)
	for t in range(1, 12):
		bridge.tick(106.0 + t)
	_check(hits.size() == 1 and health.health == 80.0, "a lag-compensated bullet hits where the shooter saw the target", str(hits.size()))
	_check(not rewinds.is_empty() and victim.position.x == 5.0, "and the world is restored afterwards")
	hits.clear()
	health.health = 100.0
	manager.rewind_fn = Callable()
	var _n := bridge.resolve_shot(_bridge_shot(106, 1), b, -1.0)
	for t in range(1, 12):
		bridge.tick(106.0 + t)
	_check(hits.is_empty() and health.health == 100.0, "the same shot without lag compensation misses")

	rules.enabled = false
	health.health = 100.0
	victim.position.x = 0.0
	manager.restore_fn = Callable()
	var hitscan := _bridge_shot(130, 1)
	hitscan.deferred = false
	var flying := bridge.bullets.count()
	var _plain := bridge.resolve_shot(hitscan, b, -1.0)
	_check(bridge.bullets.count() == flying and health.health == 80.0, "switched off, the bridge is plain hitscan", str(health.health))
	_done()


func _test_ammo_hitzones() -> void:
	_section("ammo types and hit-zone armour")
	var types := DotWeaponAmmoTypes.new()
	var ap := DotWeaponAmmoType.from_flat(&"ap", {"damage": 1.5, "velocity": 0.5, "armour_pierce": 2.0})
	types.add(ap)
	types.add(DotWeaponAmmoType.from_flat(&"ball", {}))
	_check(ap.armour_pierce == 1.0 and types.ids() == [&"ap", &"ball"], "pierce clamps, ids sorted")
	_check(DotWeaponAmmoTypes.schema().size() == 5 and DotWeaponAmmoTypes.profile_schemas().has("ammo"), "ammo is a profile kind")
	_check(types.get_type(&"nope") == null, "an unknown round is null")
	var base := DotWeaponBallistics.new()
	base.muzzle_velocity = 600.0
	base.drag = 0.001
	_check(types.get_type(&"ball").apply_to(base) == base, "a neutral round flies the weapon's own tuning")
	var slow := ap.apply_to(base)
	_check(slow != base and slow.muzzle_velocity == 300.0 and base.muzzle_velocity == 600.0, "a round scales a copy, never the weapon")
	var zones := DotWeaponHitzones.from_flat({"head": 0.5, "chest": 0.4})
	_check(is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null), 0.5) and zones.multiplier(DotHitGroup.LEG, null) == 1.0, "armour only on listed zones")
	_check(is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null, 1.0), 1.0) and is_equal_approx(zones.multiplier(DotHitGroup.HEAD, null, 0.5), 0.75), "piercing ignores armour")
	zones.presence_fn = func(_e: Node) -> float: return 0.0
	_check(zones.multiplier(DotHitGroup.HEAD, null) == 1.0, "a victim with no armour on takes full damage")
	zones.presence_fn = Callable()

	var a := _arsenal()
	a.give(&"rifle")
	var rifle_id: StringName = a.current().def.id
	_check(a.ammo_of(rifle_id) == &"", "no round loaded by default")
	a.load_ammo(rifle_id, &"ap")
	_check(a.ammo_of(rifle_id) == &"ap", "load_ammo selects the round")
	var on := DotWeaponBallisticsRules.new()
	on.enabled = true
	a.ballistics_rules = on
	((a.catalogue.get_def(&"rifle") as DotWeaponDef).tuning as DotWeaponBallistics).muzzle_velocity = 800.0
	var o := a.simulate_tick(_cmd(true), _ctx(10), null)
	var fired: DotShot = o.shots[0]
	_check(fired.deferred and fired.get_meta(&"ammo", &"") == &"ap", "a simulated shot carries the loaded round")
	_drop(a)
	var off := _arsenal()
	off.give(&"rifle")
	off.load_ammo(&"rifle", &"ap")
	var o2 := off.simulate_tick(_cmd(true), _ctx(10), null)
	_check(not (o2.shots[0] as DotShot).has_meta(&"ammo"), "ballistics off: the shot is untouched by ammo")
	_drop(off)

	var manager := DotCombatManager.new()
	manager.register_service = false
	manager.trace = DotTraceFlat.with_floor(0.0)
	manager.rules = DotDamageRules.new()
	manager.config = DotCombatConfig.new()
	manager.config.tick_rate = 64
	add_child(manager)
	var victim := _bridge_target(-30.0)
	var set_node: DotHitboxSet = null
	var health: DotHealth = null
	for c in victim.get_children():
		if c is DotHitboxSet:
			set_node = c
		if c is DotHealth:
			health = c
	set_node.register_with(manager, 2)
	manager.register_health(2, health)
	var rules := DotWeaponBallisticsRules.new()
	rules.enabled = true
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 600.0
	b.bullet_gravity = 0.0
	b.drag = 0.0
	var bridge := DotWeaponBulletBridge.new()
	add_child(bridge)
	bridge.setup(manager, rules, 64)
	var fly := func(tick: int, round_id: StringName) -> int:
		var s := _bridge_shot(tick, 1)
		if round_id != &"":
			s.set_meta(&"ammo", round_id)
		var _r := bridge.resolve_shot(s, b, -1.0)
		var n := 0
		while bridge.bullets.count() > 0 and n < 60:
			n += 1
			bridge.tick(float(tick + n))
		return n
	var _plain: int = fly.call(100, &"")
	_check(health.health == 80.0, "no ammo or zones configured: unchanged damage", str(health.health))
	health.health = 100.0
	bridge.ammo_types = types
	bridge.hitzones = DotWeaponHitzones.from_flat({"chest": 0.5})
	var _n0: int = fly.call(200, &"")
	_check(is_equal_approx(health.health, 90.0), "chest armour halves the damage", str(health.health))
	health.health = 100.0
	var fast_ticks: int = fly.call(300, &"ball")
	_check(is_equal_approx(health.health, 90.0), "a neutral round changes nothing", str(health.health))
	health.health = 100.0
	var slow_ticks: int = fly.call(400, &"ap")
	_check(is_equal_approx(health.health, 100.0 - 20.0 * 1.5), "armour-piercing: damage x1.5, armour ignored", str(health.health))
	_check(slow_ticks > fast_ticks, "and the slower round takes longer to arrive", "%d vs %d" % [slow_ticks, fast_ticks])
	health.health = 100.0
	var _unknown: int = fly.call(500, &"mystery")
	_check(is_equal_approx(health.health, 90.0), "an unknown round id changes nothing", str(health.health))
	_done()
