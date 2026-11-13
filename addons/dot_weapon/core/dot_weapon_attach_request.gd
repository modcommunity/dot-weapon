class_name DotWeaponAttachRequest
extends RefCounted

## A player's ask to put an attachment on, or take one off, a carried weapon.
##
## [b]Only the server applies one.[/b] A client sends [method to_wire]; the server reads it with
## [method from_wire], runs [method apply] against its own arsenal, and the fitting reaches every
## machine through net sync. So hit registration and lag compensation only ever see a server fitting.
##
## Failure codes: [code]CODE_INVALID[/code] malformed, empty slot or unknown attachment,
## [code]CODE_FORBIDDEN[/code] not owned or does not fit, [code]CODE_CONFLICT[/code] wrong mount
## or blocked, [code]CODE_STATE[/code] no attachment catalogue.

var slot: int = 0
var mount: StringName = &""
## Empty takes off whatever is on [member mount].
var id: StringName = &""


static func make(p_slot: int, p_mount: StringName, p_id: StringName = &"") -> DotWeaponAttachRequest:
	var r := DotWeaponAttachRequest.new()
	r.slot = p_slot
	r.mount = p_mount
	r.id = p_id
	return r


## A plain array an RPC carries: [slot, mount, id].
func to_wire() -> Array:
	return [slot, String(mount), String(id)]


## The inverse of [method to_wire]; strict about shape and types, since it came off the network.
static func from_wire(v: Variant) -> DotResult:
	if not (v is Array) or (v as Array).size() != 3:
		return DotResult.fail(DotError.CODE_INVALID, "An attach request is [slot, mount, id].")
	var a: Array = v
	if not (a[0] is int) or not (a[1] is String or a[1] is StringName) \
			or not (a[2] is String or a[2] is StringName) or String(a[1]) == "":
		return DotResult.fail(DotError.CODE_INVALID, "An attach request has the wrong types.")
	return DotResult.success(make(int(a[0]), StringName(a[1]), StringName(a[2])))


## Validates against [param arsenal] and fits it. [param owns] is `func(item_id: StringName) -> bool`
## (an inventory lookup); an invalid Callable lets everything through. Taking off needs no item.
func apply(arsenal: DotWeaponArsenal, owns: Callable = Callable()) -> DotResult:
	if arsenal == null or arsenal.attachments == null:
		return DotResult.fail(DotError.CODE_STATE, "No attachment catalogue to fit from.")
	if not arsenal.has_slot(slot):
		return DotResult.fail(DotError.CODE_INVALID, "Nothing in slot %d." % slot)
	var current := arsenal.fitting_at(slot)
	var cat := arsenal.attachments
	if id != &"" and current.attachment_on(mount) != id:
		var att := cat.get_attachment(id)
		if att == null:
			return DotResult.fail(DotError.CODE_INVALID, "There is no attachment %s." % String(id))
		if owns.is_valid() and not bool(owns.call(att.item())):
			return DotResult.fail(
				DotError.CODE_FORBIDDEN, "The player does not own %s." % String(att.item()), String(id)
			)
	var def := arsenal.catalogue.get_def(current.weapon_id)
	var res := cat.toggle(def, current, mount, id)
	if not res.ok:
		return res
	return arsenal.fit(slot, res.value)
