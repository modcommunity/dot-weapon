extends "selftest/sections_accuracy.gd"

## dot-weapon's self-test. Headless, no network, no scene but this one.

const CHECKS := 572


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-weapon self-test")
	print("")

	_test_no_nul_in_sources()
	_test_definition()
	_test_catalogue()
	_test_id_order()
	_test_content_follow()
	_test_behaviour_resolution()
	_test_carrying_and_switching()
	_test_equip_and_slot_requests()
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
	_test_recoil_view_and_cvars()
	_test_fire_modes()
	_test_muzzle()
	_test_ballistics()
	_test_bullets()
	_test_hitscan_unchanged()
	_test_bullet_bridge()
	_test_ammo_hitzones()
	_test_accuracy_classes()
	_test_accuracy_bloom()
	_test_accuracy_settle_flinch()
	_test_accuracy_scale_profile()
	_test_accuracy_recoil()
	_test_accuracy_prediction()
	_test_accuracy_distribution()

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


func _nul_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".uid"):
			var bytes := FileAccess.get_file_as_bytes(dir.path_join(f))
			# The escape in a string literal (the real cause once) makes the engine report a NUL parse error too.
			if bytes.has(0) or (not dir.begins_with("res://examples") and bytes.get_string_from_utf8().contains("\\u0000")):
				out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_nul_files(dir.path_join(d), out)


func _test_no_nul_in_sources() -> void:
	_section("sources hold no NUL byte")
	var bad: Array = []
	_nul_files("res://addons/dot_weapon", bad)
	_nul_files("res://examples", bad)
	_check(bad.is_empty(), "no .gd or .uid file contains a NUL (a release run fails on one)", str(bad))
	_done()


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


	_check(a.take(1).ok, "a weapon can be taken away")
	_check(not a.carries(&"rifle"), "and is gone")
	_check(a.current_slot() == 2, "and the hand falls back to another slot")

	_drop(a)
	_drop(b)
	_drop(c)
	_done()


func _test_equip_and_slot_requests() -> void:
	_section("equip and slot requests")

	var slow := _catalogue()
	slow.get_def(&"rifle").holster_ticks = 10
	slow.get_def(&"pistol").deploy_ticks = 20

	# A hand-out holds a slot at once, even while disabled (a round's freeze), where select refuses.
	var eq := _arsenal()
	eq.give(&"rifle")
	eq.give(&"pistol")
	eq.disabled = true
	_check(not eq.select(2, 5), "select refuses while disabled")
	_check(eq.equip(2) and eq.current_slot() == 2 and not eq.is_switching(), "equip holds the slot at once while disabled")
	_check(not eq.equip(9), "equip refuses a slot not carried")

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

	_drop(eq)
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
