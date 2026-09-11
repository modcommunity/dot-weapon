class_name DotWeaponInventoryBridge
extends RefCounted

## Keeps an arsenal's reserve ammunition and a bag's contents agreeing with each other.
##
## [b]Duck-typed throughout, for the reason [DotWeaponLoadoutBridge] gives[/b]:
## dot-inventory is not a dependency and is not named here.
##
## [b]The bag is the truth and the arsenal is a view of it.[/b] The opposite direction
## is the one that creates ammunition: a player who drops a magazine, reloads, and picks
## it back up has more rounds than they started with, because two systems each thought
## they owned the count. So rounds are counted in the bag, read into the pools before a
## use, and written back after one, and the arsenal never invents any.

## Reads every stack in [param items] into the arsenal's pools.
##
## [param items] is any array of things with an [code]id[/code] and a
## [code]count[/code]. [param pools] maps an item id to an ammunition pool name; an
## item with no entry is not ammunition and is skipped.
static func load_ammo(
	arsenal: DotWeaponArsenal,
	items: Array,
	pools: Dictionary
) -> int:
	if arsenal == null:
		return 0

	var totals: Dictionary = {}

	for entry: Variant in items:
		if entry == null:
			continue

		var item_id: StringName = StringName(str(entry.get("id")))

		if not pools.has(item_id):
			continue

		var pool: StringName = StringName(str(pools[item_id]))
		var count := int(entry.get("count"))
		totals[pool] = int(totals.get(pool, 0)) + maxi(0, count)

	# Set rather than add. Adding turns every refresh into a duplication bug, and this
	# is called on a schedule rather than once.
	for pool: StringName in totals.keys():
		arsenal.ammo().set_count(pool, int(totals[pool]))

	return totals.keys().size()


## What the bag should now contain, given what the arsenal has spent.
##
## Returns a dictionary of pool name to the count the bag should hold, for a caller to
## apply through dot-inventory's own operations — which is the only thing allowed to
## change a container, because it is the thing that validates a change.
static func ammo_counts(arsenal: DotWeaponArsenal) -> Dictionary:
	if arsenal == null:
		return {}

	var out: Dictionary = {}

	for pool in arsenal.ammo().pools():
		out[pool] = arsenal.ammo().count(pool)

	return out


## Every weapon the arsenal is carrying, as `[slot, weapon id]` rows.
##
## For a bag that shows what is in hand alongside what is stowed.
static func carried(arsenal: DotWeaponArsenal) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if arsenal == null:
		return out

	for slot_index in arsenal.slots():
		var slot := arsenal.slot_at(slot_index)
		if slot == null:
			continue
		out.append({
			"slot": slot_index,
			"id": slot.id(),
			"magazine": slot.magazine,
			"in_hand": slot_index == arsenal.current_slot(),
		})

	return out
