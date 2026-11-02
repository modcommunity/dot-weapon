class_name DotWeaponUseKey
extends RefCounted

## One player's use key over a dropped weapon, the rules every game shares. Keep one per player and call
## [method step] every tick with the key state. Over a free slot or a different weapon the press acts at once
## (take, or replace and drop the old one). Over the weapon already in hand a tap takes its ammunition and a
## hold of [member DotWeaponDropRules.hold_time] replaces it fully; looking away or letting go cancels.

var hold := DotWeaponUseHold.new()
var _was_down: bool = false


## Server side. Returns true while the key is busy with a drop (so nothing else should act on it).
func step(drops: DotWeaponDrops, arsenal: Object, position: Vector3, direction: Vector3, taker_id: int,
		pressed: bool, delta: float, source: Object = null, taker_team: int = 0) -> bool:
	var edge := pressed and not _was_down
	_was_down = pressed
	var info := drops.prompt_for(arsenal, position, direction, source, taker_team) if drops.count() > 0 else {}
	hold.hold_time = drops.rules.resolve(source).hold_time
	if info.is_empty() or not bool(info.get("can_take", true)):
		hold.cancel()
		return false
	if info.get("mode", "") != "ammo":
		hold.cancel()
		if edge:
			var _taken := drops.use(arsenal, position, direction, taker_id, source, false)
		return pressed
	var event := hold.step(pressed, delta)
	if event != DotWeaponUseHold.Event.NONE:
		var _used := drops.use(arsenal, position, direction, taker_id, source, event == DotWeaponUseHold.Event.HOLD)
	return pressed or event != DotWeaponUseHold.Event.NONE


## Client side, for the progress ring: 0..1 while the key is held over the weapon in hand, else 0.
func client_progress(info: Dictionary, pressed: bool, delta: float, hold_time: float) -> float:
	hold.hold_time = hold_time
	var _e := hold.step(pressed, delta, not info.is_empty() and info.get("mode", "") == "ammo")
	return hold.progress
