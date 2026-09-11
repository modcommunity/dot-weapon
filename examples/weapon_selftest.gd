extends Node

## dot-weapon's self-test. Headless, no network, no scene but this one.
##
## Two numbers are printed at the end and both matter: sections entered against
## sections that ran to their last line, and a total number of checks. A script error
## aborts the section it is in and the section counter is satisfied, because the
## section had already announced itself.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sections_entered: int = 0
var _sections_finished: int = 0

const RATE := 64


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-weapon self-test")
	print("")

	_test_definition()
	_test_catalogue()
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
	_test_snapshot()
	_test_loadout_bridge()
	_test_inventory_bridge()
	_test_net_sync()
	_test_extension_point()

	print("")
	print("%d sections entered, %d finished, %d passed, %d failed" % [
		_sections_entered, _sections_finished, _passed, _failed
	])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 or _sections_entered != _sections_finished else 0)


# --- Assertions -------------------------------------------------------------

func _section(name: String) -> void:
	_sections_entered += 1
	print("")
	print("-- %s" % name)


func _done() -> void:
	_sections_finished += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("   ok   %s" % what)
	else:
		_failed += 1
		_failures.append("%s%s" % [what, "  (%s)" % detail if detail != "" else ""])
		print("  FAIL  %s%s" % [what, "  (%s)" % detail if detail != "" else ""])
	return condition


func _close(got: float, want: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(got - want) <= epsilon, what, "got %.4f, want %.4f" % [got, want])


# --- Fixtures ---------------------------------------------------------------

const _HITSCAN := "res://addons/dot_weapon/behaviour/dot_weapon_hitscan.gd"
const _PROJECTILE := "res://addons/dot_weapon/behaviour/dot_weapon_projectile.gd"
const _MELEE := "res://addons/dot_weapon/behaviour/dot_weapon_melee.gd"
const _BEAM := "res://addons/dot_weapon/behaviour/dot_weapon_beam.gd"
const _THROWN := "res://addons/dot_weapon/behaviour/dot_weapon_thrown.gd"
const _ROD := "res://fixtures/lightning_rod.gd"


func _ballistics(damage: float) -> DotWeaponBallistics:
	var b := DotWeaponBallistics.new()
	b.damage = damage
	b.spread = 0.0
	b.spread_moving = 0.0
	b.spread_airborne = 0.0
	b.bloom = 0.0
	b.recoil_pitch = 0.5
	b.recoil_yaw = 0.2
	return b


func _rifle() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"rifle"
	d.display_name = "Rifle"
	d.behaviour_path = _HITSCAN
	d.slot = 1
	d.fire_mode = DotWeaponDef.Fire.AUTO
	d.use_interval_ticks = 6
	d.magazine = 30
	d.reserve = 90
	d.ammo_type = &"rifle_rounds"
	d.reload_ticks = 120
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.tuning = _ballistics(25.0)
	d.tags = [&"primary"] as Array[StringName]
	return d


func _pistol() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"pistol"
	d.behaviour_path = _HITSCAN
	d.slot = 2
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 8
	d.magazine = 12
	d.reserve = 36
	d.ammo_type = &"pistol_rounds"
	d.reload_ticks = 90
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.tuning = _ballistics(30.0)
	return d


func _bow() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"bow"
	d.behaviour_path = _PROJECTILE
	d.slot = 3
	d.fire_mode = DotWeaponDef.Fire.CHARGE
	d.charge_ticks = 64
	d.use_interval_ticks = 8
	d.ammo_type = &"arrows"
	d.reserve = 20
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(70.0)
	b.min_charge_damage = 0.2
	b.speed = 90.0
	b.min_speed = 25.0
	b.gravity_scale = 1.0
	d.tuning = b
	return d


func _knife() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"knife"
	d.behaviour_path = _MELEE
	d.slot = 4
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 20
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(55.0)
	b.max_range = 2.0
	d.tuning = b
	d.params = {&"arc_degrees": 40.0, &"rays": 5}
	return d


func _flamer() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"flamer"
	d.behaviour_path = _BEAM
	d.slot = 5
	d.fire_mode = DotWeaponDef.Fire.HOLD
	d.use_interval_ticks = 4
	d.ammo_type = &"fuel"
	d.reserve = 200
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(6.0)
	b.max_range = 12.0
	d.tuning = b
	d.params = {&"ramp_ticks": 16, &"ramp_from": 0.5}
	return d


func _grenade() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"grenade"
	d.behaviour_path = _THROWN
	d.slot = 6
	d.fire_mode = DotWeaponDef.Fire.CHARGE
	d.charge_ticks = 192
	d.use_interval_ticks = 30
	d.ammo_type = &"grenades"
	d.reserve = 2
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0

	var b := _ballistics(0.0)
	b.speed = 18.0
	b.min_speed = 18.0
	b.splash_radius = 5.0
	b.splash_damage = 110.0
	d.tuning = b
	d.params = {&"fuse_ticks": 192}
	return d


func _rod() -> DotWeaponDef:
	var d := DotWeaponDef.new()
	d.id = &"rod"
	d.behaviour_path = _ROD
	d.slot = 7
	d.fire_mode = DotWeaponDef.Fire.SEMI
	d.use_interval_ticks = 5
	d.ammo_type = &"charges"
	d.reserve = 9
	d.magazine = 0
	d.deploy_ticks = 0
	d.holster_ticks = 0
	d.params = {&"damage": 18.0, &"max_chain": 3, &"charges": 3, &"max_range": 40.0}
	return d


func _catalogue() -> DotWeaponCatalogue:
	var c := DotWeaponCatalogue.new()
	c.add(_rifle()).add(_pistol()).add(_bow()).add(_knife())
	c.add(_flamer()).add(_grenade()).add(_rod())
	return c


func _arsenal(catalogue: DotWeaponCatalogue = null) -> DotWeaponArsenal:
	var a := DotWeaponArsenal.new()
	a.catalogue = catalogue if catalogue != null else _catalogue()
	a.tick_rate = RATE
	a.authority = true
	add_child(a)
	var res := a.setup()
	if not res.ok:
		push_error(res.error.message)
	return a


func _ctx(tick: int, entity: int = 1) -> DotWeaponContext:
	return DotWeaponContext.make(entity, tick, Vector3(0.0, 1.6, 0.0), Vector3.FORWARD)


func _cmd(attack: bool = false, slot: int = 0) -> DotWeaponCommand:
	var c := DotWeaponCommand.new()
	c.set_button(DotWeaponCommand.BUTTON_ATTACK, attack)
	c.slot = slot
	return c


## Runs an arsenal for a span of ticks, holding the given buttons, collecting outcomes.
func _drive(
	arsenal: DotWeaponArsenal,
	from_tick: int,
	ticks: int,
	attack: bool,
	entity: int = 1
) -> Array[DotWeaponOutcome]:
	var out: Array[DotWeaponOutcome] = []
	var previous: DotWeaponCommand = null

	for i in range(ticks):
		var cmd := _cmd(attack)
		var result := arsenal.simulate_tick(cmd, _ctx(from_tick + i, entity), previous)
		if result.used:
			out.append(result)
		previous = cmd

	return out


func _drop(node: Node) -> void:
	remove_child(node)
	node.queue_free()


# --- Sections ---------------------------------------------------------------

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


func _test_extension_point() -> void:
	_section("a weapon the addon knows nothing about")

	# The point of the whole design: this weapon chains to several targets, costs more
	# the further it chains, sets its own cadence, refuses to fire indoors and keeps a
	# charge counter. None of those ideas exist anywhere in dot-weapon, and adding it
	# edited no file in the addon.
	var a := _arsenal()
	a.give(&"rod")
	a.select(7, 0)
	_drive(a, 0, 1, false)

	var ctx := _ctx(100)
	ctx.extra = {"targets": [2, 3, 4, 5], "indoors": false}
	var cmd := _cmd(true)
	var out := a.simulate_tick(cmd, ctx, null)

	_check(out.used, "a game's own behaviour runs")
	_check(out.kind == &"chain_lightning", "with a kind this addon never declared")
	_check(out.shots.size() == 3, "producing as many shots as it chained", str(out.shots.size()))
	_check(
		out.shots[0].damage > out.shots[1].damage,
		"falling off down the chain, which is a rule no field on a definition has"
	)
	_check(
		out.ammo_used == 3,
		"charging its own variable cost rather than the definition's",
		str(out.ammo_used)
	)
	_check(
		a.ammo().count(&"charges") == 6,
		"and the arsenal honoured it",
		str(a.ammo().count(&"charges"))
	)
	_check(out.events.size() == 1, "and its own event came through")

	# Its own refusal rule is honoured, and costs nothing.
	var before := a.ammo().count(&"charges")
	var indoors := _ctx(200)
	indoors.extra = {"targets": [2], "indoors": true}
	var refused := a.simulate_tick(_cmd(true), indoors, null)
	_check(not refused.used, "a behaviour's own refusal is honoured")
	_check(
		a.ammo().count(&"charges") == before,
		"and a refused use costs no ammunition"
	)
	_check(
		refused.refusal.contains("sky"),
		"with the behaviour's own reason, for a console and a bug report",
		refused.refusal
	)

	_drop(a)
	_done()
