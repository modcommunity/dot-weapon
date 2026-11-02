class_name DotWeaponDropKey
extends RefCounted

## One player's drop key. Keep one per player and call [method step] every tick with the key state.
## With [member DotWeaponDropRules.key_hold] at 0 the press throws at once; above 0 the weapon is thrown when the key
## has been held that long, a shorter tap throws nothing and letting go cancels. The server decides; a client calls
## [method client_progress] with the same rule value to draw a ring.

var hold := DotWeaponUseHold.new()
var _was_down: bool = false


## Server side. Returns the new drop id, or 0 when nothing was thrown this tick.
func step(drops: DotWeaponDrops, arsenal: Object, origin: Vector3, aim: Vector3, owner_id: int,
		pressed: bool, delta: float, source: Object = null, inherit: Vector3 = Vector3.ZERO) -> int:
	var edge := pressed and not _was_down
	_was_down = pressed
	var wait := drops.rules.resolve(source).key_hold
	if wait <= 0.0:
		hold.cancel()
		return drops.throw(arsenal, origin, aim, owner_id, source, inherit) if edge else 0
	hold.hold_time = wait
	if hold.step(pressed, delta) == DotWeaponUseHold.Event.HOLD:
		return drops.throw(arsenal, origin, aim, owner_id, source, inherit)
	return 0


## Client side, for a progress ring: 0..1 while the key is held toward a throw, else 0 (always 0 when [param hold_time] is 0).
func client_progress(pressed: bool, delta: float, hold_time: float) -> float:
	hold.hold_time = hold_time
	var _e := hold.step(pressed, delta, hold_time > 0.0)
	return hold.progress
