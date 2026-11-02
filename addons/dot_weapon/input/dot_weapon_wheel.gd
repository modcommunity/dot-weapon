class_name DotWeaponWheel
extends Resource

## Previous/next weapon from the mouse wheel or a gamepad: one shared walk over a ring of slots.

const CHANNEL := "weapon.wheel"

## Emitted with the ring entry to switch to (a slot number for an arsenal, an id for a tool ring).
signal chosen(target: Variant)

## InputMap actions; the defaults are dot-menu's rebindable rows, named by string so nothing is required.
@export var next_action: StringName = &"dot_menu_weapon_next"
@export var previous_action: StringName = &"dot_menu_weapon_previous"
## Raw pad buttons that also step (-1 turns one off). Skipped when the action is bound to them already.
@export var next_joy_button: int = JOY_BUTTON_RIGHT_SHOULDER
@export var previous_joy_button: int = JOY_BUTTON_LEFT_SHOULDER
## Wrap past either end; off stops at the first and last entry.
@export var wrap: bool = true

## `func() -> Array`: the entries in hand-order. Fewer than two means there is nothing to step to.
var ring_provider: Callable
## `func() -> Variant`: the entry in hand now. One not in the ring steps to the first.
var current_provider: Callable
## `func() -> bool`: true while the wheel must do nothing (dead, spectating, holding a prop).
var blocked: Callable


## A wheel over an arsenal's carried slots, in slot order.
static func from_arsenal(arsenal: Object) -> DotWeaponWheel:
	var w := DotWeaponWheel.new()
	w.ring_provider = func() -> Array: return arsenal.call("slots")
	w.current_provider = func() -> Variant: return arsenal.call("current_slot")
	return w


## -1, 0 or 1 for an event: previous, not a wheel event, next.
func step_for(event: InputEvent) -> int:
	if InputMap.has_action(next_action) and event.is_action_pressed(next_action):
		return 1
	if InputMap.has_action(previous_action) and event.is_action_pressed(previous_action):
		return -1
	if event is InputEventJoypadButton and event.pressed:
		if next_joy_button >= 0 and event.button_index == next_joy_button:
			return 1
		if previous_joy_button >= 0 and event.button_index == previous_joy_button:
			return -1
	return 0


## The entry [param step] places from the one in hand, or null when there is nowhere to go.
func target(step: int, from: Variant = null) -> Variant:
	if not ring_provider.is_valid():
		return null
	var ring: Array = ring_provider.call()
	if ring.size() < 2:
		return null
	if from == null:
		from = current_provider.call() if current_provider.is_valid() else null
	var at := ring.find(from)
	if at < 0:
		return ring[0]
	var to := at + step
	if not wrap and (to < 0 or to >= ring.size()):
		return null
	return ring[posmod(to, ring.size())]


## True when the event was a wheel step the wheel took (even with nowhere to go, so a caller
## does not also read it as a key). Emits [signal chosen] when there is somewhere to go.
func handle_event(event: InputEvent) -> bool:
	var step := step_for(event)
	if step == 0:
		return false
	if blocked.is_valid() and bool(blocked.call()):
		return false
	var to: Variant = target(step)
	if to != null:
		DotLog.debug(CHANNEL, "wheel step", {"step": step, "to": str(to)})
		chosen.emit(to)
	return true


func describe() -> Dictionary:
	return {
		"next_action": String(next_action),
		"previous_action": String(previous_action),
		"wrap": wrap,
		"ring": ring_provider.call() if ring_provider.is_valid() else [],
		"blocked": blocked.is_valid() and bool(blocked.call()),
	}
