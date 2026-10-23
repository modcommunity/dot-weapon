class_name DotWeaponSpawnView
extends RefCounted

## A client's mirror of a [DotWeaponSpawner]: what lies where, and how long until the next one. It decides nothing.
##
## Feed it the server's [signal DotWeaponSpawner.changed] events through [method apply] and a joining client's [method DotWeaponSpawner.snapshot] through [method apply_snapshot]; draw from [signal appeared] and [signal vanished].

signal appeared(instance: int, site: StringName, item: StringName, kind: StringName, at: Vector3, rotation_y: float, data: Dictionary)
signal vanished(instance: int, taker: StringName)

## instance -> `{site, item, kind, at, rotation_y, data}`.
var items: Dictionary = {}
## site -> seconds until its next item, as of the last snapshot.
var waiting: Dictionary = {}
var round_number: int = 0


## Applies one event; an unknown one is ignored so an older client survives a newer server.
func apply(event: Array) -> void:
	if event.is_empty():
		return
	match StringName(event[0]):
		DotWeaponSpawner.EV_SPAWN:
			if event.size() < 8:
				return
			var inst := int(event[1])
			items[inst] = {"site": event[2], "item": event[3], "kind": event[4], "at": event[5], "rotation_y": float(event[6]), "data": event[7]}
			waiting.erase(event[2])
			appeared.emit(inst, event[2], event[3], event[4], event[5], float(event[6]), event[7])
		DotWeaponSpawner.EV_TAKE:
			if items.erase(int(event[1])):
				vanished.emit(int(event[1]), StringName(event[2]) if event.size() > 2 else &"")


## Replaces everything with the server's snapshot (vanishing what is no longer there).
func apply_snapshot(snap: Dictionary) -> void:
	round_number = int(snap.get("round", 0))
	var keep := {}
	for ev: Variant in snap.get("items", []):
		keep[int((ev as Array)[1])] = true
	for inst: int in items.keys():
		if not keep.has(inst):
			apply([DotWeaponSpawner.EV_TAKE, inst, &""])
	for ev: Variant in snap.get("items", []):
		if not items.has(int((ev as Array)[1])):
			apply(ev as Array)
	waiting.clear()
	for w: Variant in snap.get("waiting", []):
		waiting[(w as Array)[0]] = float((w as Array)[1])
