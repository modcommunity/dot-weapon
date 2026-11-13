extends "sections_rest.gd"

## Attachments as items: compatibility rules, attachment profiles, server requests, server/client parity, loadout rows, the menu.


func _test_attach() -> void:
	_test_attach_compat()
	_test_attach_profiles()
	_test_attach_request()
	_test_attach_parity()
	_test_attach_loadout()
	_test_attach_menu()


## The shared catalogue plus a slot-limited long scope that blocks the side rail and a laser for that rail.
func _attach_rules_catalogue() -> DotWeaponAttachments:
	var c := _attachment_catalogue()
	var long := _att("long_scope", &"optic", {}, {"params.ads_seconds": 0.2})
	long.fits_slots = [1] as Array[int]
	long.blocks = [&"side"] as Array[StringName]
	long.params_set = {DotWeaponAttachment.PARAM_ZOOM: 6.0}
	var laser := _att("laser", &"side", {"spread": 0.8})
	laser.excludes_tags = [&"no_laser"] as Array[StringName]
	laser.item_id = &"item_laser"
	for a: DotWeaponAttachment in [long, laser]:
		c.add(a)
	return c


func _attach_rifle() -> DotWeaponDef:
	var d := _modular_rifle()
	d.mounts.append(&"side")
	d.params = {"ads_seconds": 0.3}
	(d.tuning as DotWeaponBallistics).spread = 3.0
	(d.tuning as DotWeaponBallistics).pellets = 4
	return d


func _test_attach_compat() -> void:
	_section("attachment compatibility")
	var c := _attach_rules_catalogue()
	var rifle := _attach_rifle()
	var long := c.get_attachment(&"long_scope")
	var laser := c.get_attachment(&"laser")
	var sidearm := _attach_rifle()
	sidearm.id = &"carbine"
	sidearm.slot = 2
	_check(long.fits(rifle) and not long.fits(sidearm), "fits_slots limits an attachment to a weapon class by slot")
	var marked := _attach_rifle()
	marked.tags.append(&"no_laser")
	_check(laser.fits(rifle) and not laser.fits(marked), "an excluded tag refuses it whatever else fits")
	_check(c.for_item(&"item_laser") == laser and laser.item() == &"item_laser" and long.item() == &"long_scope", "an item id finds its attachment, defaulting to the id")

	var both := DotWeaponFitting.make(&"rifle")
	both.fit(&"optic", &"long_scope")
	both.fit(&"side", &"laser")
	_check(c.validate_fitting(rifle, both).code() == DotError.CODE_CONFLICT, "a blocked mount in use is a conflict")
	_check(c.conform(rifle, both).key() == "optic=long_scope", "conform keeps the first mount in text order and drops what it blocks", c.conform(rifle, both).key())
	var with_laser := DotWeaponFitting.make(&"rifle")
	with_laser.fit(&"side", &"laser")
	var swapped := c.toggle(rifle, with_laser, &"optic", &"long_scope")
	_check(swapped.ok and (swapped.value as DotWeaponFitting).key() == "optic=long_scope", "toggle takes off what the new one blocks")
	var off := c.toggle(rifle, swapped.value, &"optic", &"long_scope")
	_check(off.ok and (off.value as DotWeaponFitting).is_empty(), "toggling the fitted one takes it off")
	_check(c.toggle(rifle, with_laser, &"optic", &"dot_sight").code() == DotError.CODE_FORBIDDEN, "toggle refuses what does not fit")
	_check(with_laser.key() == "side=laser", "and never changes the fitting it was given")

	var fitted: DotWeaponDef = c.apply(rifle, swapped.value).value
	_check(is_equal_approx(float(fitted.params["ads_seconds"]), 0.5) and float(fitted.params[DotWeaponAttachment.PARAM_ZOOM]) == 6.0, "a params. field changes a numeric param, and params_set sets the zoom")
	_check(is_equal_approx(float(rifle.params["ads_seconds"]), 0.3), "on a copy")
	var plain := _attach_rifle()
	plain.params = {}
	var no_param := c.apply(plain, swapped.value)
	_check(no_param.ok and not (no_param.value as DotWeaponDef).params.has("ads_seconds"), "a weapon without the param is left alone")
	var delta := DotWeaponAttachments.stat_delta(rifle, fitted)
	_check(str(delta.keys()) == str(["params.ads_seconds", "params.optic_zoom"]), "stat_delta lists the numbers that changed", str(delta.keys()))
	_check(DotWeaponAttachMenu.stat_lines({"spread": [3.0, 2.4]}) == PackedStringArray(["spread -20%"]), "a stat line is a percent", str(DotWeaponAttachMenu.stat_lines({"spread": [3.0, 2.4]})))
	_done()


func _test_attach_profiles() -> void:
	_section("attachment profiles")
	var root := ProjectSettings.globalize_path("res://fixtures/attachments")
	var profiles := DotWeaponAttachments.make_set("demo", "g", PackedStringArray([root]))
	var c := DotWeaponAttachments.new()
	var loaded := c.load_set(profiles)
	_check(loaded.ok and int(loaded.value) == 2, "load_set reads the attachment files", loaded.error.message if not loaded.ok else "")
	_check(DotWeaponAttachments.profile_schemas().has(DotWeaponAttachments.KIND), "attachment is a profile kind")
	var sup := c.get_attachment(&"suppressor")
	var scope := c.get_attachment(&"scope_4x")
	_check(sup != null and sup.mount == &"muzzle" and sup.item() == &"item_suppressor" and str(sup.excludes_tags) == str([&"shotgun"]) and sup.model.ends_with("suppressor.tscn"), "fields and lists come from the file")
	_check(scope != null and str(scope.fits_slots) == "[1]" and str(scope.blocks) == str([&"side"]), "slots and blocks too")
	var rifle := _attach_rifle()
	rifle.tags.append(&"rifle")
	var shotgun := _attach_rifle()
	shotgun.tags = [&"rifle", &"shotgun"] as Array[StringName]
	_check(sup != null and sup.fits(rifle) and not sup.fits(shotgun), "one suppressor fits by class tag and an excluded class refuses it")
	var f := DotWeaponFitting.make(&"rifle")
	f.fit(&"muzzle", &"suppressor")
	f.fit(&"optic", &"scope_4x")
	var res := c.apply(rifle, f)
	var d: DotWeaponDef = res.value if res.ok else null
	_check(d != null and bool(d.params[DotWeaponAttachment.PARAM_SUPPRESSED]) and d.params["muzzle_flash"] == "none" and d.has_tag(&"quiet"), "the suppressor sets its params and tag")
	_check(d != null and is_equal_approx(float(d.params["ads_seconds"]), 0.45) and float(d.params[DotWeaponAttachment.PARAM_ZOOM]) == 4.0, "the scope slows aiming and sets the zoom")
	_check(d != null and is_equal_approx((d.tuning as DotWeaponBallistics).damage, 22.5), "damage scales")
	var gun := Node3D.new()
	for m: String in ["muzzle", "optic", "side"]:
		var socket := Node3D.new()
		socket.name = DotWeaponAttachmentModels.SOCKET_PREFIX + m
		gun.add_child(socket)
	var count := func() -> int: return gun.get_child(0).get_child_count() + gun.get_child(1).get_child_count() + gun.get_child(2).get_child_count()
	_check(DotWeaponAttachmentModels.dress(gun, c, f) == 2 and count.call() == 2, "each fitted model goes on its mount node")
	_check(DotWeaponAttachmentModels.dress(gun, c, f) == 2 and count.call() == 2, "dressing again replaces, never stacks")
	_check(DotWeaponAttachmentModels.dress(gun, c, DotWeaponFitting.make(&"rifle")) == 0 and count.call() == 0, "an empty fitting takes them off")
	gun.free()
	_done()


func _test_attach_request() -> void:
	_section("attach requests")
	var cat := DotWeaponCatalogue.new()
	cat.add(_attach_rifle())
	var a := _arsenal(cat)
	a.give(&"rifle")
	_check(DotWeaponAttachRequest.make(1, &"muzzle", &"suppressor").apply(a).code() == DotError.CODE_STATE, "no catalogue: state")
	a.attachments = _attach_rules_catalogue()
	_check(not DotWeaponAttachRequest.from_wire([1, "muzzle"]).ok and not DotWeaponAttachRequest.from_wire(["1", "muzzle", ""]).ok and not DotWeaponAttachRequest.from_wire([1, "", "x"]).ok, "a malformed wire request is refused")
	var parsed := DotWeaponAttachRequest.from_wire(DotWeaponAttachRequest.make(1, &"side", &"laser").to_wire())
	_check(parsed.ok and (parsed.value as DotWeaponAttachRequest).id == &"laser", "a request round-trips the wire")
	var none_owned := func(_item: StringName) -> bool: return false
	var owned := func(item: StringName) -> bool: return item == &"item_laser"
	_check((parsed.value as DotWeaponAttachRequest).apply(a, none_owned).code() == DotError.CODE_FORBIDDEN, "an attachment the player does not own is refused")
	_check(DotWeaponAttachRequest.make(1, &"optic", &"dot_sight").apply(a).code() == DotError.CODE_FORBIDDEN, "one that does not fit is refused")
	_check(DotWeaponAttachRequest.make(1, &"optic", &"nothing").apply(a).code() == DotError.CODE_INVALID, "an unknown one is invalid")
	_check(DotWeaponAttachRequest.make(4, &"optic", &"scope").apply(a).code() == DotError.CODE_INVALID, "an empty slot is invalid")
	_check(a.fitting_at(1).is_empty(), "and nothing was fitted by a refusal")
	_check((parsed.value as DotWeaponAttachRequest).apply(a, owned).ok and a.fitting_at(1).key() == "side=laser", "an owned one is fitted")
	_check(DotWeaponAttachRequest.make(1, &"side").apply(a, none_owned).ok and a.fitting_at(1).is_empty(), "taking off needs no item")
	_drop(a)
	_done()


func _attach_shot_text(o: DotWeaponOutcome) -> String:
	var parts := PackedStringArray()
	for shot in o.shots:
		parts.append("%s|%s|%s|%s|%s" % [shot.direction, shot.spread, shot.pellets, shot.damage, shot.pellet_count])
	return "%s/%s" % [";".join(parts), o.recoil]


## The server fits from a request; a client gets it through net sync and must hold the same numbers and fire the same pellets.
func _test_attach_parity() -> void:
	_section("attachments: server and client agree")
	var cat := DotWeaponCatalogue.new()
	cat.add(_attach_rifle())
	var server := _arsenal(cat)
	var client := _arsenal(cat)
	var plain := _arsenal(cat)
	for arsenal: DotWeaponArsenal in [server, client, plain]:
		arsenal.attachments = _attach_rules_catalogue()
		arsenal.give(&"rifle")
	for req: DotWeaponAttachRequest in [DotWeaponAttachRequest.make(1, &"muzzle", &"suppressor"), DotWeaponAttachRequest.make(1, &"side", &"laser")]:
		var parsed := DotWeaponAttachRequest.from_wire(req.to_wire())
		(parsed.value as DotWeaponAttachRequest).apply(server)
	var wire := _FakeFitted.new()
	DotWeaponNetSync.pull(server, wire)
	DotWeaponNetSync.push(wire, client)
	wire.free()
	_check(client.fitting_at(1).key() == server.fitting_at(1).key() and server.fitting_at(1).key() == "muzzle=suppressor,side=laser", "net sync gives the client the server's fitting", client.fitting_at(1).key())
	_check(DotWeaponAttachments.stat_delta(server.current_def(), client.current_def()).is_empty(), "every number of the applied def matches")
	var changed := DotWeaponAttachments.stat_delta(plain.current_def(), server.current_def())
	_check(changed.has("spread") and changed.has("damage"), "and differs from the unfitted one", str(changed.keys()))
	var fired_s := _drive(server, 900, 30, true, 5)
	var fired_c := _drive(client, 900, 30, true, 5)
	var fired_p := _drive(plain, 900, 30, true, 5)
	var same := fired_s.size() == fired_c.size() and fired_s.size() > 0
	var differs := fired_s.size() != fired_p.size()
	for i in range(mini(fired_s.size(), mini(fired_c.size(), fired_p.size()))):
		same = same and _attach_shot_text(fired_s[i]) == _attach_shot_text(fired_c[i])
		differs = differs or _attach_shot_text(fired_s[i]) != _attach_shot_text(fired_p[i])
	_check(same, "both fire exactly the same shots")
	_check(differs, "and the attachment changed them: the behaviour fires the fitted def")
	_drop(server)
	_drop(client)
	_drop(plain)
	_done()


func _test_attach_loadout() -> void:
	_section("attachments through a loadout")
	var cat := DotWeaponCatalogue.new()
	cat.add(_attach_rifle())
	var a := _arsenal(cat)
	a.attachments = _attach_rules_catalogue()
	var rows: Array = [
		{"arsenal_slot": 1, "item": {"id": "rifle"}},
		{"arsenal_slot": 1, "item": {"id": "suppressor"}},
		{"arsenal_slot": 0, "item": {"id": "item_laser"}},
		{"arsenal_slot": 1, "item": {"id": "dot_sight"}},
		{"arsenal_slot": 1, "item": {"id": "hat"}},
	]
	var res := DotWeaponLoadoutBridge.fill(a, rows)
	_check(res.ok and int(res.value) == 1, "fill gives the weapon and counts only weapons")
	_check(a.fitting_at(1).key() == "muzzle=suppressor,side=laser", "attachment rows are fitted, slotless ones on the first weapon they fit, unfitting ones dropped", a.fitting_at(1).key())
	var saved := DotWeaponLoadoutBridge.fitted_rows(a)
	_check(str(saved) == str([{"arsenal_slot": 1, "item": "suppressor"}, {"arsenal_slot": 1, "item": "item_laser"}]), "fitted_rows names the items to save", str(saved))
	var again: Array = [{"arsenal_slot": 1, "item": {"id": "rifle"}}]
	for row in saved:
		again.append({"arsenal_slot": row["arsenal_slot"], "item": {"id": row["item"]}})
	var b := _arsenal(cat)
	b.attachments = a.attachments
	DotWeaponLoadoutBridge.fill(b, again)
	_check(b.fitting_at(1).key() == a.fitting_at(1).key(), "and a loadout saved from them fits the same again")
	_drop(a)
	_drop(b)
	_done()


func _test_attach_menu() -> void:
	_section("attach menu")
	DotWeaponAttachMenu.ensure_action()
	_check(InputMap.has_action(DotWeaponAttachMenu.ACTION) and not InputMap.action_get_events(DotWeaponAttachMenu.ACTION).is_empty(), "ensure_action binds a default key and pad button")
	var c := _attach_rules_catalogue()
	var rifle := _attach_rifle()
	var menu := DotWeaponAttachMenu.new()
	add_child(menu)
	var f := DotWeaponFitting.make(&"rifle")
	f.fit(&"muzzle", &"suppressor")
	menu.open(c, rifle, f)
	var asked: Array = []
	menu.requested.connect(func(m: StringName, id: StringName) -> void: asked.append([m, id]))
	var buttons: Array[Button] = []
	for n in menu.find_children("*", "Button", true, false):
		buttons.append(n as Button)
	## Rows: magazine (none, drum, tiny_mag), muzzle (none, brake, suppressor), optic (none, long_scope, scope), side (none, laser).
	_check(buttons.size() == 11, "a button per choice plus none on every mount", str(buttons.size()))
	_check(buttons.all(func(b: Button) -> bool: return b.custom_minimum_size.y >= 64.0 and b.focus_mode == Control.FOCUS_ALL), "every button is touch-sized and focusable for a pad")
	var pressed := PackedStringArray()
	for b in buttons:
		if b.button_pressed:
			pressed.append(b.text)
	_check(pressed == PackedStringArray(["None", "suppressor", "None", "None"]), "the fitted one shows pressed, and None on the empty mounts", str(pressed))
	_check(menu.lines_for(&"side", &"laser") == PackedStringArray(["spread -20%"]), "a choice shows what it changes", str(menu.lines_for(&"side", &"laser")))
	buttons[buttons.size() - 1].pressed.emit()
	_check(str(asked) == str([[&"side", &"laser"]]), "pressing asks for it rather than fitting it", str(asked))
	var after := menu.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).button_pressed)
	_check(after.size() == 4 and after.all(func(b: Node) -> bool: return (b as Button).text != "laser"), "and the pressed states still follow the fitting, not the click", str(after.size()))
	menu.queue_free()
	_done()
