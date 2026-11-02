class_name DotWeaponDropKey
extends RefCounted

## One player's drop key: call [method step] every tick with the key state (server), [method client_progress] for a ring.
## With [member DotWeaponDropRules.key_hold] at 0 a press throws at once; above 0 the throw happens after that hold.
## One instance per role (a listen host needs two); call [method reset] on death, respawn, disconnect and weapon switch.

var hold := DotWeaponUseHold.new()
var _was_down: bool = false
var _held_id: StringName = &""
var _holding: bool = false


## Cancels any hold and forgets the key was down: call on death, respawn, disconnect and weapon switch.
func reset() -> void:
	hold.cancel()
	_was_down = false
	_holding = false
	_held_id = &""


## Server side. Returns the new drop id, or 0 when nothing was thrown this tick.
func step(drops: DotWeaponDrops, arsenal: Object, origin: Vector3, aim: Vector3, owner_id: int,
		pressed: bool, delta: float, source: Object = null, inherit: Vector3 = Vector3.ZERO) -> int:
	var edge := pressed and not _was_down
	_was_down = pressed
	var wait := drops.rules.resolve(source).key_hold
	if wait <= 0.0:
		hold.cancel()
		return drops.throw(arsenal, origin, aim, owner_id, source, inherit) if edge else 0
	var now := _current_id(arsenal)
	if pressed and not _holding:
		_holding = true
		_held_id = now
	elif _holding and now != _held_id:
		# The weapon changed mid-hold: the new one must not be thrown by a press meant for the old.
		hold.cancel()
		_holding = false
		_held_id = &""
		return 0
	if not pressed:
		_holding = false
	hold.hold_time = wait
	if hold.step(pressed, delta) == DotWeaponUseHold.Event.HOLD:
		return drops.throw(arsenal, origin, aim, owner_id, source, inherit)
	return 0


## Client side, for a progress ring: 0..1 while the key is held toward a throw, else 0. [param active] is whether a
## throw is possible now (armed, not dead, not disabled); false shows no ring. Use [method hold_time_for] for [param hold_time].
func client_progress(pressed: bool, delta: float, hold_time: float, active: bool = true) -> float:
	hold.hold_time = hold_time
	var _e := hold.step(pressed, delta, active and hold_time > 0.0)
	return hold.progress


## The hold the server uses for [param source] (a class def or null), so the ring matches per-class overrides.
static func hold_time_for(rules: DotWeaponDropRules, source: Object = null) -> float:
	return rules.resolve(source).key_hold


static func _current_id(arsenal: Object) -> StringName:
	if arsenal == null or not arsenal.has_method(&"current"):
		return &""
	var slot: Variant = arsenal.call(&"current")
	return slot.id() if slot != null else &""
