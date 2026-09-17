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

	return DotResult.success(given)


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
