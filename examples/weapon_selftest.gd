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

const CHECKS := 316


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

	print("")
	print("%d sections entered, %d finished, %d passed, %d failed" % [
		_sections_entered, _sections_finished, _passed, _failed
	])

	for line in _failures:
		print("  FAIL  %s" % line)

	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the section counter catches it only when the error is before
	# the last line — an error in the final statement leaves both counters satisfied
	# with checks missing. dot-settings reported "8 sections, 63 passed, 0 failed" and
	# exited 0 with eight checks gone; see docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return

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


# --- Content packs ----------------------------------------------------------

const _PACK := "res://fixtures/workshop_pack"


func _provides(entries: Array) -> Dictionary:
	return {"schema": 1, "title": "Fixture arms", "kinds": ["weapon"], "entries": entries}


func _wentry(id: String, extra: Dictionary = {}) -> Dictionary:
	var d := {
		"kind": "weapon", "id": id, "name": id.capitalize(),
		"def": "weapons/%s.tres" % id, "category": "fixture",
		"thumbnail": "icons/%s.png" % id,
	}
	d.merge(extra, true)
	return d


func _test_content_follow() -> void:
	_section("delivered weapons")

	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var c := _catalogue()
	c.add(_catalogue_extra(), "toys")
	var base := c.size()

	var added: Array[String] = []
	var changes := [0]
	c.weapon_added.connect(func(l: DotWeaponListing) -> void: added.append(String(l.id)))
	c.listings_changed.connect(func() -> void: changes[0] += 1)

	# A pack mounted before the catalogue follows: order does not matter.
	index.add_pack({
		"content_id": "tmc/fixture-arms", "version": "1.0.0", "prefix": _PACK,
		"session": "solo", "source": "subscription",
		"provides": _provides([_wentry("flare_gun", {"tags": ["sidearm"]})]),
	})
	c.follow_content(index)
	_check(c.size() == base + 1, "a pack mounted before following is seen", str(c.size()))
	_check(added == ["flare_gun"], "and announced as added", str(added))
	_check(changes[0] >= 1, "with a listings_changed signal")
	_check(c.has(&"flare_gun") and c.get_def(&"flare_gun").slot == 2, "the def loads from the mount")
	var l := c.listing(&"flare_gun")
	_check(l != null and l.is_delivered() and l.display_name == "Flare Gun", "the listing carries the entry's name")
	_check(l.category == "fixture" and l.content_id == "tmc/fixture-arms", "category and pack")
	_check(l.icon_path == _PACK + "/icons/flare_gun.png", "the thumbnail is resolved onto the mount")
	_check(l.icon() == null, "a missing thumbnail is null, not an error")
	_check(l.source == &"subscription" and l.tags == PackedStringArray(["sidearm"]), "source and tags")
	_check(c.ids_in_slot(2) == ([&"flare_gun"] as Array[StringName]) or c.ids_in_slot(2).has(&"flare_gun"), "slot index includes it")
	_check(c.instantiate(&"flare_gun").ok, "and it instantiates a behaviour")

	# A pack mounted afterwards.
	index.add_pack({
		"content_id": "tmc/more-arms", "version": "2.0.0", "prefix": _PACK,
		"session": "solo", "source": "subscription",
		"provides": _provides([
			_wentry("ember_blade"),
			_wentry("rifle"),
			_wentry("wrong_id"),
			_wentry("not_there"),
			{"kind": "weapon", "id": "no_def", "name": "x"},
		]),
	})
	_check(added == ["flare_gun", "ember_blade"], "a later pack adds only its good rows", str(added))
	_check(c.get_def(&"rifle").display_name == "Rifle", "code wins an id clash")
	_check(not c.has(&"other_name") and not c.has(&"wrong_id"), "a def whose id differs from its entry is refused")
	_check(not c.has(&"not_there") and not c.has(&"no_def"), "missing and absent defs are refused")
	_check(c.validate().ok, "the code table still validates")
	_check(c.categories().has("fixture") and c.categories().has("toys"), "categories cover both sources")
	_check(c.listings("fixture").size() == 2, "listings filter by category")
	_check(c.listings()[0].is_delivered() == false, "code weapons list first")

	# Sessions.
	var other_changes: int = changes[0]
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(c.size() == base, "online, every solo weapon is gone", str(c.size()))
	_check(not c.has(&"flare_gun") and c.listing(&"ember_blade") == null, "queries agree")
	_check(changes[0] > other_changes, "the switch is announced")
	var n_added := added.size()
	index.set_session(DotContentIndex.SESSION_SOLO)
	_check(c.has(&"flare_gun") and c.has(&"ember_blade"), "back in solo they return")
	_check(added.size() == n_added + 2, "and are announced again")

	# Reuse by a server: tagged online as well.
	index.tag_pack(&"tmc/fixture-arms", "1.0.0", DotContentIndex.SESSION_ONLINE)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(c.has(&"flare_gun") and not c.has(&"ember_blade"), "a pack also tagged online shows online")
	index.set_session(DotContentIndex.SESSION_SOLO)

	var lines := c.describe_lines()
	_check(lines.size() >= base + 2 and "\n".join(lines).contains("tmc/fixture-arms"), "describe_lines names the pack")
	_check(c.describe()["delivered"] == 2, "describe counts delivered")

	c.unfollow_content()
	_check(c.size() == base and not c.has(&"flare_gun"), "unfollowing forgets delivered weapons")
	index.add_pack({
		"content_id": "tmc/late", "version": "1", "prefix": _PACK, "session": "solo",
		"provides": _provides([_wentry("flare_gun")]),
	})
	_check(not c.has(&"flare_gun"), "and stops listening")

	# Default: the shared index.
	var mine := DotContentIndex.new()
	DotRegistry.register(DotContentIndex.SERVICE, mine)
	var d := DotWeaponCatalogue.new().follow_content()
	_check(d.describe()["session"] == "solo", "follow_content() with no argument uses the registered index")
	d.unfollow_content()
	DotRegistry.unregister(DotContentIndex.SERVICE)
	_done()


func _catalogue_extra() -> DotWeaponDef:
	var d := _pistol()
	d.id = &"toy_blaster"
	return d


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

	# A charge fills in the same time, and so does what a behaviour reads per tick.
	var bow: DotWeaponDef = cat.get_def(&"bow")
	_close(at128.charge_for(bow, 64), 0.5, "half a second of draw is half a charge at 128 Hz")
	_close(at64.charge_for(bow, 64), 1.0, "and a full one at 64")
	var behaviour := at128.slot_at(1).behaviour
	_close(behaviour.scaled_per_tick(0.15), 0.075, "bloom recovers half as much per tick at 128 Hz", 0.00001)

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

	for a: Node in [at64, at128, raw, r64, r128, s64, s128, g64, g128, server, client]:
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


# --- Attachments ------------------------------------------------------------

func _att(
	id: String, mount: StringName, scale: Dictionary = {}, add: Dictionary = {}
) -> DotWeaponAttachment:
	var a := DotWeaponAttachment.new()
	a.id = StringName(id)
	a.mount = mount
	a.scale = scale
	a.add = add
	return a


## A rifle with three mounts, and a catalogue of attachments for it.
func _modular_rifle() -> DotWeaponDef:
	var d := _rifle()
	d.mounts = [&"optic", &"muzzle", &"magazine"] as Array[StringName]
	return d


func _attachment_catalogue() -> DotWeaponAttachments:
	var c := DotWeaponAttachments.new()
	var suppressor := _att("suppressor", &"muzzle", {"spread": 0.5, "damage": 0.9})
	suppressor.tags_added = [&"quiet"] as Array[StringName]
	var brake := _att("brake", &"muzzle", {"recoil_pitch": 0.5})
	var scope := _att("scope", &"optic", {}, {"spread": -0.1})
	scope.params_set = {"zoom": 4.0}
	scope.fits_tags = [&"primary"] as Array[StringName]
	var pistol_dot := _att("dot_sight", &"optic")
	pistol_dot.fits_weapons = [&"pistol"] as Array[StringName]
	var drum := _att("drum", &"magazine", {"magazine": 2.0}, {"reload_ticks": 30})
	var tiny := _att("tiny_mag", &"magazine", {"magazine": 0.01})
	for a in [suppressor, brake, scope, pistol_dot, drum, tiny]:
		var res := c.add(a)
		if not res.ok:
			push_error(res.error.message)
	return c


func _test_attachments() -> void:
	_section("attachments")

	var c := _attachment_catalogue()
	var rifle := _modular_rifle()
	var fits_scope := c.get_attachment(&"scope").fits(rifle)
	_check(fits_scope, "an optic fits a weapon that has the mount and the tag")
	_check(not c.get_attachment(&"dot_sight").fits(rifle), "a list of weapon ids refuses another weapon")
	_check(not c.get_attachment(&"scope").fits(_pistol()), "a weapon without the mount refuses it")
	var untagged := _modular_rifle()
	untagged.tags = [] as Array[StringName]
	_check(not c.get_attachment(&"scope").fits(untagged), "a tag list refuses a weapon without the tag")
	_check(c.get_attachment(&"drum").fits(untagged), "empty fit lists fit any weapon with the mount")

	_check(not c.add(_att("brake", &"muzzle")).ok, "a duplicate id is refused")
	_check(c.add(_att("brake", &"muzzle")).code() == DotError.CODE_CONFLICT, "as a conflict")
	_check(not c.add(_att("", &"muzzle")).ok, "an attachment without an id is refused")
	_check(not c.add(_att("zero", &"muzzle", {"damage": 0.0})).ok, "a zero multiplier is refused")
	_check(not c.add(_att("inf", &"muzzle", {}, {"damage": INF})).ok, "an infinite addition is refused")
	_check(not c.add(_att("nomount", &"")).ok, "an empty mount is refused")

	_check(
		c.ids() == [&"brake", &"dot_sight", &"drum", &"scope", &"suppressor", &"tiny_mag"],
		"ids are in text order"
	)
	var choices := c.choices_for(rifle)
	_check(choices.size() == 3, "choices cover every mount of the weapon")
	_check(choices[&"muzzle"] == [&"brake", &"suppressor"], "in text order", str(choices[&"muzzle"]))
	_check(choices[&"optic"] == [&"scope"], "and only what fits")

	# apply returns a copy and never touches the shared definition or its tuning.
	var base_spread := (rifle.tuning as DotWeaponBallistics).spread
	var base_recoil := (rifle.tuning as DotWeaponBallistics).recoil_pitch
	var base_damage := (rifle.tuning as DotWeaponBallistics).damage
	var f := DotWeaponFitting.make(&"rifle")
	f.fit(&"muzzle", &"suppressor")
	f.fit(&"magazine", &"drum")
	f.fit(&"optic", &"scope")
	var applied := c.apply(rifle, f)
	_check(applied.ok, "a legal fitting applies")
	var out: DotWeaponDef = applied.value
	_check(out != rifle and out.tuning != rifle.tuning, "to a copy, tuning included")
	_check(out.magazine == 60 and out.reload_ticks == rifle.reload_ticks + 30, "int fields scale and add")
	_close((out.tuning as DotWeaponBallistics).damage, base_damage * 0.9, "tuning fields resolve after the def")
	_close((out.tuning as DotWeaponBallistics).spread, 0.0 * 0.5 - 0.1, "scaling comes before adding")
	_check(
		(rifle.tuning as DotWeaponBallistics).spread == base_spread
		and (rifle.tuning as DotWeaponBallistics).recoil_pitch == base_recoil
		and (rifle.tuning as DotWeaponBallistics).damage == base_damage
		and rifle.magazine == 30 and not rifle.tags.has(&"quiet") and not rifle.params.has("zoom"),
		"the base definition and its tuning are untouched"
	)
	_check(out.tags.has(&"quiet") and out.tags.count(&"quiet") == 1, "tags are added once")
	_check(is_equal_approx(float(out.params.get("zoom", 0.0)), 4.0), "params are merged")
	_check(c.apply(rifle, DotWeaponFitting.make(&"rifle")).value == rifle, "an empty fitting returns the def itself")

	var typo := DotWeaponAttachments.new()
	typo.add(_att("typo", &"muzzle", {"dammage": 0.5}))
	var tf := DotWeaponFitting.make(&"rifle")
	tf.fit(&"muzzle", &"typo")
	var rifle2 := _modular_rifle()
	var bad := typo.apply(rifle2, tf)
	_check(not bad.ok and bad.code() == DotError.CODE_INVALID, "an unknown field is refused, not skipped")
	var notnum := DotWeaponAttachments.new()
	notnum.add(_att("name", &"muzzle", {"display_name": 2.0}))
	var nf := DotWeaponFitting.make(&"rifle")
	nf.fit(&"muzzle", &"name")
	_check(not notnum.apply(rifle2, nf).ok, "so is a field that is not a number")

	var tm := DotWeaponFitting.make(&"rifle")
	tm.fit(&"magazine", &"tiny_mag")
	var floor_def: DotWeaponDef = c.apply(rifle, tm).value
	_check(floor_def.magazine == 1, "a magazine that held rounds keeps at least one", str(floor_def.magazine))

	# Refusals, by code.
	var unknown := DotWeaponFitting.make(&"rifle")
	unknown.fit(&"muzzle", &"nothing")
	_check(c.validate_fitting(rifle, unknown).code() == DotError.CODE_INVALID, "an unknown id: invalid")
	var wrong_mount := DotWeaponFitting.make(&"rifle")
	wrong_mount.fit(&"optic", &"suppressor")
	_check(c.validate_fitting(rifle, wrong_mount).code() == DotError.CODE_CONFLICT, "the wrong mount: conflict")
	var no_fit := DotWeaponFitting.make(&"rifle")
	no_fit.fit(&"optic", &"dot_sight")
	_check(c.validate_fitting(rifle, no_fit).code() == DotError.CODE_FORBIDDEN, "does not fit: forbidden")
	var other := DotWeaponFitting.make(&"pistol")
	_check(c.validate_fitting(rifle, other).code() == DotError.CODE_STATE, "another weapon's fitting: state")
	_check(c.validate_fitting(rifle, f).ok, "and a legal one passes")

	var mixed := DotWeaponFitting.make(&"rifle")
	mixed.fit(&"muzzle", &"suppressor")
	mixed.fit(&"optic", &"dot_sight")
	mixed.fit(&"side", &"brake")
	var kept := c.conform(rifle, mixed)
	_check(kept.key() == "muzzle=suppressor", "conform drops what is illegal and keeps the rest", kept.key())

	# Fitting value type.
	_check(f.key() == "magazine=drum,muzzle=suppressor,optic=scope", "a key is in mount text order", f.key())
	_check(f.mounts() == [&"magazine", &"muzzle", &"optic"] and f.ids() == [&"drum", &"scope", &"suppressor"], "mounts and ids are sorted by text")
	var round_trip := DotWeaponFitting.from_dictionary(f.to_dictionary())
	_check(round_trip.ok and (round_trip.value as DotWeaponFitting).key() == f.key(), "a fitting round-trips a dictionary")
	_check(not DotWeaponFitting.from_dictionary({"weapon": "rifle", "mounts": {"muzzle": 5}}).ok, "a non-string id is refused, not coerced")
	var copy := f.duplicate_fitting()
	copy.remove(&"muzzle")
	_check(f.attachment_on(&"muzzle") == &"suppressor" and copy.attachment_on(&"muzzle") == &"", "a duplicate is independent")

	# Every combination of the three mounts survives the wire encoding.
	var combos := 0
	var wrong := 0
	var optics: Array = [&""] + choices[&"optic"]
	var muzzles: Array = [&""] + choices[&"muzzle"]
	var mags: Array = [&""] + choices[&"magazine"]
	for o: StringName in optics:
		for m: StringName in muzzles:
			for g: StringName in mags:
				var combo := DotWeaponFitting.make(&"rifle")
				for pair in [[&"optic", o], [&"muzzle", m], [&"magazine", g]]:
					if pair[1] != &"":
						combo.fit(pair[0], pair[1])
				combos += 1
				var code := c.encode(rifle, combo)
				if c.decode(rifle, code).key() != combo.key() or code >= (1 << c.code_bits(rifle)):
					wrong += 1
	_check(combos == 2 * 3 * 3 and wrong == 0, "every combination round-trips through encode and decode", "%d wrong of %d" % [wrong, combos])
	_check(c.code_bits(rifle) == 1 + 2 + 2, "with just enough bits per mount", str(c.code_bits(rifle)))
	_check(c.decode(rifle, 0).is_empty() and c.decode(rifle, 3).is_empty(), "code 0 and an index past the choices decode as none")

	# The arsenal.
	var cat := DotWeaponCatalogue.new()
	cat.add(_modular_rifle())
	var a := _arsenal(cat)
	_check(not a.fit(1, f).ok and a.fit(1, f).code() == DotError.CODE_STATE, "an arsenal with no attachments cannot fit")
	a.attachments = c
	_check(a.give(&"rifle").ok, "an arsenal carries the rifle")
	_check(a.fitting_at(1).is_empty() and a.fitting_at(7).is_empty(), "fresh, nothing is fitted, and fitting_at is never null")
	_check(not a.fit(5, f).ok, "an empty slot cannot be fitted")
	var before := a.current().magazine
	_check(before == 30, "the magazine starts full")
	_check(a.fit(1, f).ok, "fit succeeds")
	_check(a.current_def().magazine == 60 and a.slot_at(1).def != cat.get_def(&"rifle"), "the slot uses the applied def")
	_check(cat.get_def(&"rifle").magazine == 30, "the catalogue's is untouched")
	_check(a.fitting_at(1).key() == f.key(), "fitting_at reports it")
	f.remove(&"optic")
	_check(a.fitting_at(1).key() != f.key(), "the arsenal stored a copy")

	var shrink := DotWeaponFitting.make(&"rifle")
	shrink.fit(&"magazine", &"tiny_mag")
	a.slot_at(1).magazine = 30
	a.fit(1, shrink)
	_check(a.slot_at(1).magazine == 1, "a magazine above the new capacity is clamped", str(a.slot_at(1).magazine))

	# Snapshot and restore on another machine.
	a.fit(1, c.conform(rifle, mixed))
	var snap := a.snapshot()
	_check(snap["slots"][1].has("fit"), "the snapshot carries the fitting")
	var b := _arsenal(cat)
	var no_att := b.restore(snap)
	_check(not no_att.ok and no_att.code() == DotError.CODE_STATE, "restoring a fitting without a catalogue is a state error")
	b.attachments = c
	_check(b.restore(snap).ok, "with one it restores")
	_check(b.fitting_at(1).key() == "muzzle=suppressor", "and keeps the fitting", b.fitting_at(1).key())
	_check(b.current_def().has_tag(&"quiet"), "so the second arsenal uses the applied def")
	a.fit(1, DotWeaponFitting.make(&"rifle"))
	_check(a.current_def() == cat.get_def(&"rifle"), "an empty fitting restores the base def")
	_check(not a.snapshot()["slots"][1].has("fit"), "and the snapshot carries nothing")
	b.restore(a.snapshot())
	_check(b.fitting_at(1).is_empty() and b.current_def() == cat.get_def(&"rifle"), "restoring that unfits the second arsenal")

	_drop(a)
	_drop(b)
	_done()


class _FakeFitted extends Object:
	var net_slot: int = 0
	var net_magazine: int = 0
	var net_reserve: int = 0
	var net_fitted: int = 0


func _test_attachments_wire() -> void:
	_section("attachments on the wire")

	var c := _attachment_catalogue()
	var cat := DotWeaponCatalogue.new()
	cat.add(_modular_rifle())
	var shooter := _arsenal(cat)
	shooter.attachments = c
	shooter.give(&"rifle")
	var f := DotWeaponFitting.make(&"rifle")
	f.fit(&"muzzle", &"suppressor")
	f.fit(&"optic", &"scope")
	shooter.fit(1, f)

	_check(DotWeaponNetSync.specs().size() == 3, "specs() is unchanged")
	var fs := DotWeaponNetSync.fitting_specs()
	_check(fs.size() == 1 and fs[0]["property"] == &"net_fitted" and not bool(fs[0]["owner_only"]), "fitting_specs is one public property")
	_check(int(fs[0]["bits"]) == DotWeaponNetSync.FITTED_BITS and DotWeaponNetSync.fitting_bits() == 16, "of 16 bits")

	var fake := _FakeFitted.new()
	DotWeaponNetSync.pull(shooter, fake)
	_check(fake.net_fitted != 0, "pull writes the code")

	var watcher := _arsenal(cat)
	watcher.attachments = c
	watcher.give(&"rifle")
	DotWeaponNetSync.push(fake, watcher)
	_check(watcher.fitting_at(1).key() == f.key(), "push gives a watcher the same fitting", watcher.fitting_at(1).key())
	_check(watcher.current_def().has_tag(&"quiet"), "which it uses")

	shooter.fit(1, DotWeaponFitting.make(&"rifle"))
	DotWeaponNetSync.pull(shooter, fake)
	_check(fake.net_fitted == 0, "an unfitted weapon pulls zero")
	DotWeaponNetSync.push(fake, watcher)
	_check(watcher.fitting_at(1).is_empty(), "and the watcher unfits")

	var plain := _FakeNet.new()
	shooter.fit(1, f)
	DotWeaponNetSync.pull(shooter, plain)
	_check(plain.net_magazine == shooter.current().magazine, "an object without net_fitted is still pulled")
	var untouched := _arsenal(cat)
	untouched.attachments = c
	untouched.give(&"rifle")
	DotWeaponNetSync.push(plain, untouched)
	_check(untouched.fitting_at(1).is_empty(), "and its push leaves the fitting alone")

	var no_cat := _arsenal(cat)
	no_cat.give(&"rifle")
	DotWeaponNetSync.push(fake, no_cat)
	_check(no_cat.fitting_at(1).is_empty(), "an arsenal with no attachment catalogue ignores the code")

	fake.free()
	plain.free()
	_drop(shooter)
	_drop(watcher)
	_drop(untouched)
	_drop(no_cat)
	_done()


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


# --- The dot-player bridge --------------------------------------------------

## A stand-in for a dot-player node. This project does not depend on dot-player, so the
## bridge is duck-typed and so is the thing it is tested against — which is the honest
## test: if this passes, a real DotPlayer with the same methods passes.
class StubPlayer extends Node3D:
	var player_key: String = "ada"
	var stub_controller: Node = null

	func component(type_name: StringName) -> Object:
		if stub_controller == null:
			return null

		if String(type_name) == "DotPlayerController":
			return stub_controller

		return null

	func body() -> Node:
		return self


class StubController extends Node:
	var eye: Transform3D = Transform3D.IDENTITY
	var motion_data: Dictionary = {}

	func eye_transform() -> Transform3D:
		return eye

	func motion() -> Dictionary:
		return motion_data


func _test_player_bridge() -> void:
	_section("the dot-player bridge")

	var a := DotWeaponPlayerBridge.entity_of("ada")
	var b := DotWeaponPlayerBridge.entity_of("bob")
	_check(a >= 0 and b >= 0, "an entity number is never negative")
	_check(a != b, "and two keys give two numbers")
	_check(
		a == DotWeaponPlayerBridge.entity_of("ada"),
		"and one key always gives the same number — stable across machines and across "
		+ "a reconnect, which a counter would not be"
	)
	_check(DotWeaponPlayerBridge.entity_of("") >= 0, "an empty key still gives one")

	var empty := DotWeaponPlayerBridge.context_for(null, 7)
	_check(empty.tick == 7, "a context with no player still carries the tick")
	_check(empty.entity == 0, "and no entity")

	var player := StubPlayer.new()
	add_child(player)

	var bare := DotWeaponPlayerBridge.context_for(player, 3, 1, 0.5)
	_check(bare.entity == a, "a context takes the entity from the key")
	_check(bare.index == 1, "and the index")
	_check(_close(bare.charge, 0.5, "and the charge"), "")

	var controller := StubController.new()
	controller.eye = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1.65, 0))
	controller.motion_data = {"speed": 5.0, "on_floor": false, "crouched": true}
	player.stub_controller = controller
	player.add_child(controller)

	var ctx := DotWeaponPlayerBridge.context_for(player, 4)
	_check(
		_close(ctx.origin.y, 1.65, "the shot comes from the eye"),
		"a shot fired from a capsule's origin comes out of the player's knees"
	)
	_check(
		ctx.direction.x < -0.9,
		"and along the view, not the body's facing — a shot aimed along the body comes "
		+ "out sideways whenever the player is looking anywhere but straight ahead"
	)
	_check(_close(ctx.speed, 5.0, "the speed comes through"), "")
	_check(ctx.airborne, "and being airborne")
	_check(ctx.crouched, "and crouching")

	# The view model, with nowhere to hang it.
	var view_model := Node3D.new()
	_check(
		not DotWeaponPlayerBridge.attach_view_model(player, view_model),
		"attaching a view model to a player with no character answers false rather "
		+ "than failing — a server has no model and a 2D game has no bones"
	)
	_check(not DotWeaponPlayerBridge.attach_view_model(null, view_model), "and to nothing")
	view_model.free()

	# The class loadout, duck-typed against dot-player-class.
	var arsenal := _arsenal()
	var classless := RefCounted.new()
	_check(
		not DotWeaponPlayerBridge.give_class_loadout(arsenal, classless).ok,
		"a class that names no loadout is refused, as a state rather than a mistake"
	)
	_check(
		not DotWeaponPlayerBridge.give_class_loadout(null, classless).ok,
		"and so is no arsenal at all"
	)

	player.queue_free()
	_done()


func _profile_write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_profiles() -> void:
	_section("weapon profiles")
	var root := OS.get_temp_dir().path_join("dw_prof_%d" % Time.get_ticks_usec())
	var w := root.path_join("addons/demo/weapon")
	_profile_write(w.path_join("pistol/pistol.yml"), "name: \"Pistol\"\nslot: 2\nfire_mode: \"auto\"\nmagazine: 12\ntags: [\"gun\"]\nmenu:\n  category: guns\n  sort: 2\nextra:\n  damage: 20.0\n")
	_profile_write(w.path_join("pistol/upgrades/scope.yml"), "cost: 50\nmul:\n  damage: 1.5\nadd:\n  magazine: 3\nset:\n  slot: 3\n")
	_profile_write(w.path_join("pistol/upgrades/ghost.yml"), "add:\n  nope: 1\n")
	_profile_write(w.path_join("pistol/upgrades/after.yml"), "requires: [\"scope\"]\ncost: 5\n")
	_profile_write(w.path_join("knife.yml"), "name: \"Knife\"\nmenu:\n  sort: 1\n  hidden: true\n")
	_profile_write(w.path_join("bad.yml"), "wobble: 1\n")
	var set := DotWeaponProfiles.make_set("demo", "g", PackedStringArray([root]))
	_check(Array(DotWeaponProfiles.list_ids(set)) == ["bad", "knife", "pistol"], "ids are listed from the files, folder form included")
	var res := DotWeaponProfiles.load_def(set, "pistol")
	var d: DotWeaponDef = res.value if res.ok else null
	_check(d != null and d.slot == 2 and d.fire_mode == DotWeaponDef.Fire.AUTO and d.magazine == 12 and d.has_tag(&"gun"), "a profile fills the common DotWeaponDef fields")
	_check(d != null and d.display_name == "Pistol" and is_equal_approx(float(d.params["damage"]), 20.0), "and its extra keys become params")
	_check(not DotWeaponProfiles.load_def(set, "bad").ok, "an unknown top-level key is refused")
	_check(Array(set.child_kinds("pistol")) == ["upgrades"] and Array(DotWeaponProfiles.list_upgrades(set, "pistol")) == ["after", "ghost", "scope"], "upgrades are listed")
	var menu := DotWeaponProfiles.menu_entries(set)
	_check(menu.size() == 1 and menu[0]["id"] == "pistol" and menu[0]["category"] == "guns", "the menu lists visible weapons with their menu: keys")
	_check(DotWeaponProfiles.menu_entries(set, true).size() == 2, "hidden ones on request")
	var base := DotWeaponProfiles.flat(set.load_profile("pistol").value)
	var ups := DotWeaponProfiles.upgrade_set(set, "pistol")
	var up := DotWeaponProfiles.apply_upgrades(base, ups, ["scope"])
	_check(up.ok and is_equal_approx(float(up.value["values"]["damage"]), 30.0) and up.value["values"]["magazine"] == 15 and up.value["values"]["slot"] == 3 and up.value["cost"] == 50, "set, mul and add apply and cost is summed")
	_check(is_equal_approx(float(base["damage"]), 20.0), "the base dictionary is not changed")
	_check(DotWeaponProfiles.apply_upgrades(base, ups, ["scope", "after"]).value["cost"] == 55, "a prerequisite met earlier in the list passes")
	_check(not DotWeaponProfiles.apply_upgrades(base, ups, ["after"]).ok, "a prerequisite missing fails")
	_check(not DotWeaponProfiles.apply_upgrades(base, ups, ["ghost"]).ok, "an upgrade naming no key fails")
	set.clear_cache()
	ups.clear_cache()
	_done()
