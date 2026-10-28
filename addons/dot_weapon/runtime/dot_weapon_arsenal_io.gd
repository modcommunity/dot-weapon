extends RefCounted
## Snapshot, restore and reporting for [DotWeaponArsenal], kept apart so the state machine stays small.

## Everything that has to travel and everything a rollback has to restore.
##
## [b]The behaviours' own state is in here[/b], because a snapshot that carried the
## magazine and not the bow's draw reconciles a correction by silently un-drawing it.
static func snapshot(a: Node) -> Dictionary:
	var carried: Dictionary = {}
	for key: int in a._slots.keys():
		carried[key] = (a._slots[key] as DotWeaponSlot).snapshot()

	var stowed: Dictionary = {}
	for key: int in a._shelf.keys():
		var rows: Array = []
		for w: DotWeaponSlot in a._shelf[key]:
			rows.append(w.snapshot())
		if not rows.is_empty():
			stowed[key] = rows

	return {
		"slots": carried,
		"shelf": stowed,
		"pack": a.backpack_tier,
		"ammo": a._ammo.snapshot(),
		"current": a._current,
		"previous": a._previous,
		"next_use": a._next_use_tick,
		"switch_to": a._switch_to,
		"switch_done": a._switch_done_tick,
		"holstering": a._holstering,
		"reloading": a._reloading,
		"reload_done": a._reload_done_tick,
		"burst_left": a._burst_left,
		"charge_started": a._charge_started,
		"held": a._held_ticks,
		"use_index": a._use_index,
	}


## Restores a snapshot, rebuilding any weapon this carrier is not currently holding.
static func restore(a: Node, d: Dictionary) -> DotResult:
	if not a._ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	var carried: Dictionary = d.get("slots", {})
	var wanted: Dictionary = {}

	for key: Variant in carried.keys():
		var index := int(key)
		var row: Dictionary = carried[key]
		var id := StringName(str(row.get("id", "")))
		wanted[index] = true

		var existing: DotWeaponSlot = a._slots.get(index, null)

		if existing == null or existing.id() != id:
			var made: DotResult = a.catalogue.instantiate(id, a)
			if not made.ok:
				return made
			var def: DotWeaponDef = a.catalogue.get_def(id)
			existing = DotWeaponSlot.make(def, made.value)
			a._slots[index] = existing

		var wanted_fit: Variant = row.get("fit", null)
		var want_key := ""
		var want: DotWeaponFitting = null
		if wanted_fit is Dictionary:
			var parsed := DotWeaponFitting.from_dictionary(wanted_fit as Dictionary)
			if not parsed.ok:
				return parsed
			want = parsed.value
			want_key = want.key()
		var have_key := existing.fitting.key() if existing.fitting != null else ""
		if want_key != have_key:
			if want != null and a.attachments == null:
				return DotResult.fail(
					DotError.CODE_STATE, "The snapshot has a fitting and this arsenal has no attachments."
				)
			var fitted: DotResult = a._apply_fitting(existing, want if want != null else DotWeaponFitting.make(id))
			if not fitted.ok:
				return fitted

		existing.restore(row)

	for key: int in a._slots.keys().duplicate():
		if not wanted.has(key):
			a._slots.erase(key)

	var shelved := _restore_shelf(a, d)
	if not shelved.ok:
		return shelved
	a.backpack_tier = int(d.get("pack", 0))
	_restore_scalars(a, d)

	return DotResult.success(null)


static func _restore_shelf(a: Node, d: Dictionary) -> DotResult:
	var rebuilt: Dictionary = {}
	var stowed: Dictionary = d.get("shelf", {})
	for key: Variant in stowed.keys():
		var list: Array = []
		var old: Array = a._shelf.get(int(key), [])
		for row: Dictionary in stowed[key]:
			var sid := StringName(str(row.get("id", "")))
			var piece: DotWeaponSlot = null
			for o: DotWeaponSlot in old:
				if o.id() == sid:
					piece = o
					break
			if piece == null:
				var made2: DotResult = a.catalogue.instantiate(sid, a)
				if not made2.ok:
					return made2
				piece = DotWeaponSlot.make(a.catalogue.get_def(sid), made2.value)
			piece.restore(row)
			list.append(piece)
		rebuilt[int(key)] = list

	a._shelf = rebuilt
	return DotResult.success(null)


static func _restore_scalars(a: Node, d: Dictionary) -> void:
	a._ammo.restore(d.get("ammo", {}))
	a._current = int(d.get("current", 0))
	a._previous = int(d.get("previous", 0))
	a._next_use_tick = int(d.get("next_use", 0))
	a._switch_to = int(d.get("switch_to", 0))
	a._switch_done_tick = int(d.get("switch_done", -1))
	a._holstering = bool(d.get("holstering", false))
	a._reloading = bool(d.get("reloading", false))
	a._reload_done_tick = int(d.get("reload_done", -1))
	a._burst_left = int(d.get("burst_left", 0))
	a._charge_started = int(d.get("charge_started", -1))
	a._held_ticks = int(d.get("held", 0))
	a._use_index = int(d.get("use_index", 0))


static func describe(a: Node) -> Dictionary:
	var slot: DotWeaponSlot = a.current()
	return {
		"ready": a._ready_for_use,
		"tick_rate": a.tick_rate,
		"current": a._current,
		"weapon": String(slot.id()) if slot != null else "",
		"magazine": slot.magazine if slot != null else 0,
		"switching": a.is_switching(),
		"reloading": a._reloading,
		"carried": a._slots.keys().size(),
		"ammo": a._ammo.describe(),
	}


static func describe_lines(a: Node) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("arsenal: %d carried, slot %d%s" % [
		a._slots.keys().size(), a._current, " (switching)" if a.is_switching() else ""
	])

	for s in a.slots():
		var slot: DotWeaponSlot = a._slots[s]
		var mark := ">" if s == a._current else " "
		out.append("%s %d %-18s mag %d/%d" % [
			mark, s, String(slot.id()), slot.magazine, slot.def.magazine
		])

	for pool in a._ammo.pools():
		out.append("  reserve %-12s %d" % [String(pool), a._ammo.count(pool)])

	return out
