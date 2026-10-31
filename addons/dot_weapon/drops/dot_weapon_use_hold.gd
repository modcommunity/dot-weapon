class_name DotWeaponUseHold
extends RefCounted

## Tells a tap of the use key from a hold. Feed it the key state every frame: a release before
## [member hold_time] is a tap, reaching it is a hold (once), and letting go early cancels the fill.
## [member progress] drives the filling circle.

enum Event { NONE, TAP, HOLD }

var hold_time: float = 0.6
## 0..1, how full the circle is.
var progress: float = 0.0

var _down: float = -1.0
var _fired: bool = false


## [param pressed] is whether the key is down now; [param active] false (nothing to use) cancels.
func step(pressed: bool, delta: float, active: bool = true) -> Event:
	if not active:
		cancel()
		return Event.NONE
	if pressed:
		if _down < 0.0:
			_down = 0.0
			_fired = false
		_down += delta
		progress = clampf(_down / maxf(hold_time, 0.01), 0.0, 1.0)
		if _down >= hold_time and not _fired:
			_fired = true
			return Event.HOLD
		return Event.NONE
	var was_down := _down >= 0.0
	var tapped := was_down and not _fired
	cancel()
	return Event.TAP if tapped else Event.NONE


## Drops the press without an event.
func cancel() -> void:
	_down = -1.0
	_fired = false
	progress = 0.0


func is_holding() -> bool:
	return _down >= 0.0 and not _fired
