class_name DotWeaponSlot
extends RefCounted

## One weapon a carrier is actually holding, and the state that belongs to it alone.
##
## [b]Separate from [DotWeaponDef] because a definition is shared and this is not.[/b]
## Thirty players carrying the same rifle share one definition and have thirty
## magazines. Writing a round count onto the definition is the bug where reloading
## reloads everybody's.

## The row this was built from. Never null.
var def: DotWeaponDef = null

## The behaviour instance, private to this carrier.
##
## One per slot rather than one per definition, because a behaviour holds state — a
## bow's draw, a beam's heat — and sharing an instance makes one player's bow charge
## when another draws.
var behaviour: DotWeaponBehaviour = null

## Rounds in the magazine. Meaningless when the weapon feeds from the reserve.
var magazine: int = 0

## Ticks of reloading already done, for a reload that survives a holster.
var reload_progress: int = 0

## Index into [method DotWeaponDef.allowed_fire_modes] the player selected on this gun.
var fire_mode_index: int = 0

## What is fitted, or null when nothing is. [member def] is already the applied copy.
var fitting: DotWeaponFitting = null


static func make(p_def: DotWeaponDef, p_behaviour: DotWeaponBehaviour) -> DotWeaponSlot:
	var s := DotWeaponSlot.new()
	s.def = p_def
	s.behaviour = p_behaviour
	s.magazine = p_def.magazine
	return s


func id() -> StringName:
	return def.id if def != null else &""


## The fire mode in effect: the selected one among the definition's allowed modes.
func fire_mode() -> DotWeaponDef.Fire:
	var modes := def.allowed_fire_modes()
	return modes[clampi(fire_mode_index, 0, modes.size() - 1)]


## Whether the magazine cannot pay for another use.
func magazine_empty() -> bool:
	if def == null or not def.uses_magazine():
		return false
	return magazine < def.cost_per_use


## Rounds this magazine still has room for.
func magazine_space() -> int:
	if def == null or not def.uses_magazine():
		return 0
	return maxi(0, def.magazine - magazine)


## Everything that has to survive the wire and a rollback.
##
## [b]The behaviour's state travels with it.[/b] A snapshot that carried the magazine
## and not the draw on the bow is one that reconciles a correction by silently
## un-drawing it, which reads to the player as the bow firing by itself.
func snapshot() -> Dictionary:
	var out := {
		"id": String(id()),
		"mag": magazine,
		"reload": reload_progress,
		"behaviour": behaviour.state.duplicate(true) if behaviour != null else {},
	}
	if fire_mode_index != 0:
		out["fm"] = fire_mode_index
	if fitting != null and not fitting.is_empty():
		out["fit"] = fitting.to_dictionary()
	return out


func restore(d: Dictionary) -> void:
	magazine = int(d.get("mag", magazine))
	reload_progress = int(d.get("reload", 0))
	fire_mode_index = int(d.get("fm", 0))
	if behaviour != null:
		var bs: Variant = d.get("behaviour", {})
		behaviour.state = (bs as Dictionary).duplicate(true) if bs is Dictionary else {}


func describe() -> Dictionary:
	return {
		"id": String(id()),
		"magazine": magazine,
		"capacity": def.magazine if def != null else 0,
		"fitting": fitting.key() if fitting != null else "",
	}
