extends "sections_net.gd"

## Content-pack, attachment, player-bridge and profile sections of the suite.

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


func _follow_sessions(index: DotContentIndex, c: DotWeaponCatalogue, base: int, added: Array[String], changes: Array) -> void:
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

	_follow_sessions(index, c, base, added, changes)

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


func _attachments_refusals(c: DotWeaponAttachments, rifle: DotWeaponDef, f: DotWeaponFitting) -> void:
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


func _attachments_value_type(c: DotWeaponAttachments, rifle: DotWeaponDef, f: DotWeaponFitting, choices: Dictionary) -> void:
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


func _attachments_arsenal(c: DotWeaponAttachments, rifle: DotWeaponDef, f: DotWeaponFitting, mixed: DotWeaponFitting) -> void:
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

	_attachments_refusals(c, rifle, f)
	_attachments_value_type(c, rifle, f, choices)
	var mixed := DotWeaponFitting.make(&"rifle")
	mixed.fit(&"muzzle", &"suppressor")
	mixed.fit(&"optic", &"dot_sight")
	mixed.fit(&"side", &"brake")
	_attachments_arsenal(c, rifle, f, mixed)
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

	# The point of the design: this weapon chains to several targets, costs more the further it chains, sets its own
	# cadence, refuses to fire indoors and keeps a charge counter, and none of those ideas exist in dot-weapon;
	# adding it edited no file in the addon.
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


func _test_overlay() -> void:
	_section("weapon profile overlay")
	var root := OS.get_user_data_dir().path_join("overlay_profiles")
	DirAccess.make_dir_recursive_absolute(root.path_join("addons/ov/weapon/gun/upgrades"))
	_profile_write(root.path_join("addons/ov/weapon/gun/gun.yml"), "magazine: 30.0\nextra:\n  tuning:\n    damage: 42\n    nope: 1\n  params:\n    bash: 9\n")
	_profile_write(root.path_join("addons/ov/weapon/gun/upgrades/big.yml"), "cost: 7\nadd:\n  magazine: 5\nmul:\n  tuning.damage: 2.0\n")
	_profile_write(root.path_join("addons/ov/weapon/ghost.yml"), "slot: 4\n")
	var gun := DotWeaponDef.new()
	gun.id = &"gun"
	gun.magazine = 12
	gun.slot = 1
	gun.tuning = DotWeaponBallistics.new()
	gun.params = {&"bash": 3.0, &"keep": 1}
	var other := DotWeaponDef.new()
	other.id = &"other"
	other.slot = 1
	var defs: Array[DotWeaponDef] = [gun, other]
	var set := DotWeaponProfiles.overlay_set("ov", "", "", PackedStringArray([root]))
	var errors := DotWeaponProfiles.tune(defs, set)
	_check(errors.is_empty(), "tune reports no load failure")
	_check(gun.magazine == 30 and typeof(gun.magazine) == TYPE_INT, "a float in a file keeps the builder's int type")
	_check(gun.slot == 1, "a key the file does not set keeps the builder's value")
	_check(is_equal_approx((gun.tuning as DotWeaponBallistics).damage, 42.0), "extra: tuning: sets a tuning number")
	_check(is_equal_approx(float(gun.params[&"bash"]), 9.0) and gun.params[&"keep"] == 1, "extra: params: sets one param and leaves the rest")
	_check(other.slot == 1, "a weapon without a file is untouched; a file with no weapon is ignored")
	var flat := DotWeaponProfiles.flat_of(gun)
	_check(flat["magazine"] == 30 and flat["tuning.damage"] == 42.0 and flat["params.bash"] == 9.0, "flat_of reads common, tuning and params keys")
	var again := DotWeaponProfiles.upgraded(gun, ["big"], set)
	var up: DotWeaponDef = again.value["def"] if again.ok else null
	_check(again.ok and again.value["cost"] == 7 and up.magazine == 35 and is_equal_approx((up.tuning as DotWeaponBallistics).damage, 84.0), "upgraded applies add and mul to a copy")
	_check(gun.magazine == 30, "the original definition is not changed by an upgrade")
	var yml := DotWeaponProfiles.to_yaml(gun, "Demo")
	_check(yml.contains("magazine: 30") and yml.contains("  tuning:\n") and yml.contains("    damage: 42"), "to_yaml writes the numbers back")
	_check(DotWeaponProfiles.profile_path("ov", "gun", root) == root.path_join("addons/ov/weapon/gun/gun.yml"), "profile_path finds the folder form")
	set.clear_cache()
	_done()


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
	_check(DotWeaponProfiles.profile_schemas()["weapon"]["children"].has("upgrades"), "profile_schemas names weapon with its upgrades child")
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

	_profile_write(root.path_join("addons/other/weapon/zz_rifle.yml"), "name: \"Rifle\"\nextra:\n  damage: 30.0\n")
	var group := DotWeaponProfileGroup.make("g", PackedStringArray([root]))
	var _a := group.add_pack("demo")
	var _b := group.add_pack("other")
	_check(Array(group.list_ids()) == ["bad", "knife", "pistol", "zz_rifle"], "a group lists every pack's weapons under the one kind")
	_check(group.profile_for("zz_rifle") == "zz_rifle" and group.profile_for("pk_x_pistol") == "pistol" and group.profile_for("nope") == "", "a definition id finds its profile by suffix")
	var rt := DotProfileRuntime.new()
	rt.add_set(group)
	rt.permit = func(_actor: Variant, _flag: String) -> bool: return true
	var done := rt.handle_request("a", DotProfileRuntime.make_request("set", "weapon", "zz_rifle", "extra.damage", 55.0))
	_check(done.ok, "one runtime edits a weapon of either pack", "" if done.ok else done.error.message)
	var theirs := DotWeaponProfiles.make_set("other", "g", PackedStringArray([root]), group.runtime)
	_check(float(theirs.load_profile("zz_rifle").value.get_extra("damage")) == 55.0, "a pack's own set handed the layer reads the edit")
	var plain := DotWeaponProfiles.make_set("other", "g", PackedStringArray([root]))
	_check(float(plain.load_profile("zz_rifle").value.get_extra("damage")) == 30.0, "while a set without it keeps the file")
	_check(not rt.handle_request("a", DotProfileRuntime.make_request("set", "weapon", "ghost", "slot", 2)).ok, "an id no pack has is refused")
	var from := DotWeaponDef.new()
	from.display_name = "New"
	var into := DotWeaponDef.new()
	DotWeaponProfiles.refresh_def(into, from)
	_check(into.display_name == "New", "refresh_def copies a rebuilt definition onto the one holders have")
	rt.handle_request("a", DotProfileRuntime.make_request("reset", "weapon", "zz_rifle"))
	_check(group.runtime.is_empty(), "a reset empties the shared layer")
	group.clear_cache()
	theirs.clear_cache()
	plain.clear_cache()
	set.clear_cache()
	ups.clear_cache()
	_done()
