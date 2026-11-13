class_name DotWeaponAttachMenu
extends PanelContainer

## The attach/detach menu: one row per mount of the weapon in hand, a button per attachment that fits
## and one to take it off, with what each changes. Built in code, so a game only themes it.
##
## [b]It changes nothing itself.[/b] A press emits [signal requested]; the game sends a
## [DotWeaponAttachRequest] to the server and calls [method show_fitting] with what comes back.
## Pad: focus moves with ui_up/down/left/right, ui_accept presses; number keys pick a mount row.
## Touch: every button is at least [member min_button_size].

## Asks for [param id] on [param mount]; an empty id takes it off.
signal requested(mount: StringName, id: StringName)
## The menu wants to close (ui_cancel or the open action again).
signal closed

## The InputMap action that opens it; [method ensure_action] binds a default when a game has none.
const ACTION := &"dot_menu_weapon_attach"

@export var min_button_size := Vector2(128, 64)

var _catalogue: DotWeaponAttachments
var _base: DotWeaponDef
var _fitting: DotWeaponFitting
var _rows: Array[HBoxContainer] = []
var _detail: Label


## Adds [constant ACTION] on T and the pad's Back button, unless the game already defines it.
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	InputMap.action_add_event(ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_BACK
	InputMap.action_add_event(ACTION, pad)


## Fills the menu for [param base] (the catalogue definition, unfitted) and its [param fitting].
func open(catalogue: DotWeaponAttachments, base: DotWeaponDef, fitting: DotWeaponFitting) -> void:
	_catalogue = catalogue
	_base = base
	show_fitting(fitting)
	show()
	focus_first()


## Rebuilds the rows for [param fitting]: the server's answer, or the replicated one.
func show_fitting(fitting: DotWeaponFitting) -> void:
	_fitting = fitting
	var had := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var keep: Variant = had.get_meta(&"choice") if had != null and had.has_meta(&"choice") else null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = _base.display_name if _base.display_name != "" else String(_base.id)
	box.add_child(title)
	var choices := _catalogue.choices_for(_base)
	var mounts: Array[StringName] = []
	for m: StringName in choices.keys():
		mounts.append(m)
	mounts.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for i in mounts.size():
		var head := Label.new()
		head.text = "[%d] %s" % [i + 1, String(mounts[i]).capitalize()]
		box.add_child(head)
		var row := HBoxContainer.new()
		box.add_child(row)
		_rows.append(row)
		row.add_child(_button(mounts[i], &""))
		for id: StringName in choices[mounts[i]]:
			row.add_child(_button(mounts[i], id))
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)
	if keep != null:
		for row in _rows:
			for b in row.get_children():
				if b.get_meta(&"choice") == keep:
					(b as Button).grab_focus()


func focus_first() -> void:
	focus_row(0)


## Focuses the fitted choice of row [param index] (or its first button).
func focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	for b in _rows[index].get_children():
		if (b as Button).button_pressed:
			(b as Button).grab_focus()
			return
	(_rows[index].get_child(0) as Button).grab_focus()


## The stat lines for [param id] on [param mount] against the current fitting ("recoil_pitch -15%").
func lines_for(mount: StringName, id: StringName) -> PackedStringArray:
	var res := _catalogue.toggle(_base, _fitting.duplicate_fitting(), mount, id)
	if id == &"" or not res.ok:
		return PackedStringArray()
	var now := _catalogue.apply(_base, _fitting)
	var then := _catalogue.apply(_base, res.value)
	if not now.ok or not then.ok:
		return PackedStringArray()
	return stat_lines(DotWeaponAttachments.stat_delta(now.value, then.value))


## Text for [method DotWeaponAttachments.stat_delta]: a percent where the old value is not zero.
static func stat_lines(delta: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for field: String in delta.keys():
		var pair: Array = delta[field]
		var name := field.trim_prefix(DotWeaponAttachment.PARAMS_PREFIX)
		var a := float(pair[0])
		var b := float(pair[1])
		if absf(a) > 0.000001:
			out.append("%s %+d%%" % [name, roundi((b - a) / absf(a) * 100.0)])
		else:
			out.append("%s %+.2f" % [name, b - a])
	return out


func _button(mount: StringName, id: StringName) -> Button:
	var b := Button.new()
	var att := _catalogue.get_attachment(id)
	b.text = "None" if att == null else (att.display_name if att.display_name != "" else String(id))
	b.custom_minimum_size = min_button_size
	b.set_meta(&"choice", [mount, id])
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.set_pressed_no_signal(_fitting.attachment_on(mount) == id)
	b.pressed.connect(_on_pressed.bind(mount, id))
	b.focus_entered.connect(_on_focus.bind(mount, id))
	b.mouse_entered.connect(_on_focus.bind(mount, id))
	return b


func _on_pressed(mount: StringName, id: StringName) -> void:
	requested.emit(mount, id)
	show_fitting(_fitting)  ## Pressed states follow the server, not the click.


func _on_focus(mount: StringName, id: StringName) -> void:
	var att := _catalogue.get_attachment(id)
	var text := "" if att == null else att.description
	var lines := lines_for(mount, id)
	_detail.text = (text + "\n" if text != "" else "") + ", ".join(lines)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or (InputMap.has_action(ACTION) and event.is_action_pressed(ACTION)):
		closed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var n := (event as InputEventKey).keycode - KEY_1
		if n >= 0 and n < mini(9, _rows.size()):
			focus_row(n)
			get_viewport().set_input_as_handled()
