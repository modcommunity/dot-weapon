class_name DotWeaponLoadoutBridge
extends RefCounted

## Fills an arsenal from what a player brought in.
##
## [b]Neither dot-loadout nor dot-inventory is a dependency, and neither is named
## here.[/b] A script that mentions a [code]class_name[/code] the project does not have
## fails to parse and takes every script referencing it down with it, so everything
## below is duck-typed: a resolved loadout is an array of dictionaries with an
## [code]arsenal_slot[/code] and an [code]item[/code] that has an [code]id[/code], and
## that is all this needs to know. dot-weapon installs and runs with dot-core and
## dot-combat alone.
##
## [b]dot-loadout deliberately stops at `[slot, item]` pairs[/b], with a note that a
## game maps items to weapons with its own table. This is that table, written once,
## because every game that adopted both wrote the same twenty lines.
##
## [codeblock]
## var resolved := loadouts.resolve(loadout)
## var res := DotWeaponLoadoutBridge.fill(arsenal, resolved)
## if not res.ok:
##     DotLog.warn(CHANNEL, "the loadout did not fill", {"why": res.error.message})
## [/codeblock]

## Clears an arsenal and gives it everything in a resolved loadout.
##
## [param resolved] is what `DotLoadoutManager.resolve()` returns. [param mapping] maps
## an item id to a weapon id for a game whose two id spaces differ; an empty mapping
## means they are the same, which is the case worth making easy.
##
## [b]A row that names no weapon is skipped, not an error.[/b] A loadout carries
## cosmetics, perks and consumables as well as weapons, and refusing a whole loadout
## because it contained a hat would make the two systems impossible to use together.
static func fill(
	arsenal: DotWeaponArsenal,
	resolved: Array,
	mapping: Dictionary = {}
) -> DotResult:
	if arsenal == null:
		return DotResult.fail(DotError.CODE_INVALID, "No arsenal to fill.")

	if not arsenal.is_ready():
		return DotResult.fail(
			DotError.CODE_STATE, "The arsenal has not been set up."
		)

	arsenal.clear()

	var given := 0
	var skipped: Array[String] = []
	var parts: Array[Dictionary] = []

	for row: Variant in resolved:
		if not (row is Dictionary):
			continue

		var entry: Dictionary = row
		var item: Variant = entry.get("item", null)

		if item == null:
			continue

		var item_id: StringName = StringName(str(item.get("id")))
		var weapon_id: StringName = StringName(
			str(mapping.get(item_id, item_id))
		)

		if not arsenal.catalogue.has(weapon_id):
			if arsenal.attachments != null and arsenal.attachments.for_item(item_id) != null:
				parts.append({"item": item_id, "slot": int(entry.get("arsenal_slot", 0))})
			else:
				skipped.append(String(item_id))
			continue

		var res := arsenal.give(weapon_id)
		if not res.ok:
			return res.wrap("Filling the arsenal from a loadout failed.")

		given += 1

	if given == 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The loadout named no weapon this arsenal knows. Skipped: %s"
			% (", ".join(skipped) if not skipped.is_empty() else "nothing"),
		)

	_fit_parts(arsenal, parts)
	return DotResult.success(given)


## Fits attachment rows after the weapons: on the row's `arsenal_slot`, or with none on the first
## carried weapon it fits. One that does not fit is dropped, never an error (a saved loadout from
## another version should degrade).
static func _fit_parts(arsenal: DotWeaponArsenal, parts: Array[Dictionary]) -> void:
	for part in parts:
		var att := arsenal.attachments.for_item(part["item"])
		var targets: Array[int] = arsenal.slots()
		if int(part["slot"]) > 0:
			targets = [int(part["slot"])]
		for slot in targets:
			if not arsenal.has_slot(slot):
				continue
			var fitting := arsenal.fitting_at(slot)
			var def := arsenal.catalogue.get_def(fitting.weapon_id)
			if fitting.attachment_on(att.mount) != &"" or not att.fits(def):
				continue
			var res := arsenal.attachments.toggle(def, fitting, att.mount, att.id)
			if res.ok and arsenal.fit(slot, res.value).ok:
				break


## The attachment rows to save for what is fitted now: `{arsenal_slot, item}` per attachment, by
## slot then mount, so a loadout keeps them through [method fill].
static func fitted_rows(arsenal: DotWeaponArsenal) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if arsenal == null or arsenal.attachments == null:
		return out
	for slot in arsenal.slots():
		var fitting := arsenal.fitting_at(slot)
		for m in fitting.mounts():
			var att := arsenal.attachments.get_attachment(fitting.attachment_on(m))
			if att != null:
				out.append({"arsenal_slot": slot, "item": String(att.item())})
	return out


## Whether an arsenal could be filled from a loadout, without changing anything.
##
## For a server checking a loadout on the join path: it answers the question before the
## player is in the world, where refusing is cheap.
static func check(
	catalogue: DotWeaponCatalogue,
	resolved: Array,
	mapping: Dictionary = {}
) -> DotResult:
	if catalogue == null:
		return DotResult.fail(DotError.CODE_INVALID, "No catalogue to check against.")

	var seen_slots: Dictionary = {}

	for row: Variant in resolved:
		if not (row is Dictionary):
			continue

		var item: Variant = (row as Dictionary).get("item", null)
		if item == null:
			continue

		var item_id: StringName = StringName(str(item.get("id")))
		var weapon_id: StringName = StringName(str(mapping.get(item_id, item_id)))

		if not catalogue.has(weapon_id):
			continue

		var def := catalogue.get_def(weapon_id)

		if seen_slots.has(def.slot):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"%s and %s both want slot %d." % [
					String(seen_slots[def.slot]), String(weapon_id), def.slot
				]
			)

		seen_slots[def.slot] = weapon_id

	return DotResult.success(seen_slots.keys().size())
