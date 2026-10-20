class_name DotWeaponAttachments
extends RefCounted

## The attachment catalogue: every attachment a game offers, and the rules for what may go
## on which weapon.
##
## [b]Both machines must hold the same catalogue[/b], like the weapon catalogue. What
## travels is ids (or the packed [method encode] index into [method choices_for]), so two
## catalogues that differ decode the same bits into different attachments.
##
## Failure codes of [method validate_fitting], to branch on: [code]CODE_INVALID[/code] unknown
## attachment id, [code]CODE_CONFLICT[/code] the attachment or the mount is not that weapon's,
## [code]CODE_FORBIDDEN[/code] the attachment does not fit this weapon, [code]CODE_STATE[/code]
## the fitting is for another weapon.

var _by_id: Dictionary = {}  ## StringName -> DotWeaponAttachment


func add(att: DotWeaponAttachment) -> DotResult:
	if att == null:
		return DotResult.fail(DotError.CODE_INVALID, "No attachment given.")
	var res := att.validate()
	if not res.ok:
		return res
	if _by_id.has(att.id):
		return DotResult.fail(
			DotError.CODE_CONFLICT, "Attachment %s is already in the catalogue." % String(att.id),
			String(att.id)
		)
	_by_id[att.id] = att
	return DotResult.success(att)


func get_attachment(id: StringName) -> DotWeaponAttachment:
	return _by_id.get(id, null)


## Every id, in text order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _by_id.keys():
		out.append(key)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Mount -> text-ordered ids that fit, for every mount of [param def] (possibly empty lists).
func choices_for(def: DotWeaponDef) -> Dictionary:
	var out: Dictionary = {}
	for m in def.mounts:
		out[m] = [] as Array[StringName]
	for id in ids():
		var att: DotWeaponAttachment = _by_id[id]
		if att.fits(def):
			(out[att.mount] as Array[StringName]).append(id)
	return out


func validate_fitting(def: DotWeaponDef, fitting: DotWeaponFitting) -> DotResult:
	if fitting.weapon_id != def.id:
		return DotResult.fail(
			DotError.CODE_STATE,
			"The fitting is for %s, not %s." % [String(fitting.weapon_id), String(def.id)]
		)
	for m in fitting.mounts():
		var id := fitting.attachment_on(m)
		var att: DotWeaponAttachment = _by_id.get(id, null)
		if att == null:
			return DotResult.fail(
				DotError.CODE_INVALID, "There is no attachment %s." % String(id), String(id)
			)
		if att.mount != m or not def.mounts.has(m):
			return DotResult.fail(
				DotError.CODE_CONFLICT,
				"%s cannot go on mount %s of %s." % [String(id), String(m), String(def.id)],
				String(id)
			)
		if not att.fits(def):
			return DotResult.fail(
				DotError.CODE_FORBIDDEN,
				"%s does not fit %s." % [String(id), String(def.id)], String(id)
			)
	return DotResult.success(fitting)


## A copy of [param fitting] with everything illegal dropped. Never fails: a replicated code
## or a saved loadout from another version should degrade, not refuse.
func conform(def: DotWeaponDef, fitting: DotWeaponFitting) -> DotWeaponFitting:
	var out := DotWeaponFitting.make(def.id)
	for m in fitting.mounts():
		var id := fitting.attachment_on(m)
		var att: DotWeaponAttachment = _by_id.get(id, null)
		if att != null and att.mount == m and att.fits(def):
			out.fit(m, id)
	return out


## The definition with [param fitting] applied: a NEW definition, so the shared one and its
## tuning are never mutated (thirty players, one rifle). An empty fitting returns [param def]
## itself. Attachments apply in mount text order so every machine gets the same numbers.
func apply(def: DotWeaponDef, fitting: DotWeaponFitting) -> DotResult:
	var res := validate_fitting(def, fitting)
	if not res.ok:
		return res
	if fitting.is_empty():
		return DotResult.success(def)
	var copy := def.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as DotWeaponDef
	for m in fitting.mounts():
		var applied := (_by_id[fitting.attachment_on(m)] as DotWeaponAttachment).apply_to(copy)
		if not applied.ok:
			return applied
	return DotResult.success(copy)


# --- Replication ------------------------------------------------------------

## Bits one mount needs: enough for 0 (none) to the number of choices.
static func _bits_for(choices: int) -> int:
	var bits := 0
	while (1 << bits) < choices + 1:
		bits += 1
	return bits


func _sorted_mounts(def: DotWeaponDef) -> Array[StringName]:
	var out: Array[StringName] = def.mounts.duplicate()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Bits [method encode] uses for [param def]. Compare with [constant DotWeaponNetSync.FITTED_BITS].
func code_bits(def: DotWeaponDef) -> int:
	var choices := choices_for(def)
	var total := 0
	for m in _sorted_mounts(def):
		total += _bits_for((choices[m] as Array).size())
	return total


## The fitting as one integer: per mount of [member DotWeaponDef.mounts] in text order, the
## 1-based index in [method choices_for] (0 = none), each in just enough bits, first mount in
## the low bits. Anything that does not fit is encoded as none.
func encode(def: DotWeaponDef, fitting: DotWeaponFitting) -> int:
	var choices := choices_for(def)
	var code := 0
	var shift := 0
	for m in _sorted_mounts(def):
		var list: Array = choices[m]
		var bits := _bits_for(list.size())
		var index := list.find(fitting.attachment_on(m)) + 1
		code |= index << shift
		shift += bits
	return code


## The inverse of [method encode]. An index past the choices decodes as none.
func decode(def: DotWeaponDef, code: int) -> DotWeaponFitting:
	var choices := choices_for(def)
	var out := DotWeaponFitting.make(def.id)
	var shift := 0
	for m in _sorted_mounts(def):
		var list: Array = choices[m]
		var bits := _bits_for(list.size())
		var index := (code >> shift) & ((1 << bits) - 1)
		shift += bits
		if index >= 1 and index <= list.size():
			out.fit(m, list[index - 1])
	return out


func describe() -> Dictionary:
	return {"attachments": ids().map(func(i: StringName) -> String: return String(i))}
