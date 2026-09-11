class_name DotWeaponRecoil
extends RefCounted

## View kick, accumulated and recovered. A value a game adds to its own camera.
##
## [b]It owns no view.[/b] It is a pure accumulator, which is what keeps it predictable
## and lets a server reproduce a client's aim exactly. The same instance serves a
## first-person rig, a third-person one, a spectator camera and a headless suite.
##
## [b]It takes three floats rather than a weapon.[/b] The version this replaces took a
## `DotWeapon` and read `recoil_pitch`, `recoil_yaw` and `recoil_recovery` off it, which
## quietly made recoil a thing only that one resource could describe — a bow that kicks
## on release and a melee weapon that does not kick at all had no way in. A behaviour
## now computes its own kick from whatever it likes, including the charge it was held
## at, and hands over the numbers.
##
## [codeblock]
## # when a use produces one
## recoil.kick(outcome.recoil.x, outcome.recoil.y, 6.0)
## # every frame
## recoil.advance(delta)
## camera.rotation_degrees.x = base_pitch + recoil.offset().x
## camera.rotation_degrees.y = base_yaw + recoil.offset().y
## [/codeblock]

## Accumulated kick in degrees: x is pitch, up positive; y is yaw.
var _offset: Vector2 = Vector2.ZERO

## Which way the next sideways kick goes. Alternates, so a burst walks rather than
## drifting one way.
var _yaw_sign: float = 1.0

## Fraction of the accumulated kick shed per second, from the last kick applied.
var _recovery: float = 6.0

## Most pitch a burst may pile up, in degrees.
##
## Past it the view stops climbing, which is what every shooter does so a held trigger
## does not end at the ceiling.
var max_pitch: float = 30.0


## Adds one kick. [param pitch] climbs, [param yaw] alternates side to side.
func kick(pitch: float, yaw: float, recovery: float = -1.0) -> void:
	_offset.x = minf(_offset.x + pitch, max_pitch)
	_offset.y += yaw * _yaw_sign
	_yaw_sign = -_yaw_sign
	if recovery >= 0.0:
		_recovery = recovery


## Applies a whole outcome's kick.
func kick_outcome(outcome: DotWeaponOutcome, recovery: float = -1.0) -> void:
	if outcome == null or outcome.recoil == Vector2.ZERO:
		return
	kick(outcome.recoil.x, outcome.recoil.y, recovery)


## Sheds recoil.
##
## Frame-rate independent: two half-steps recover exactly what one whole step does,
## which a naive `offset -= rate * delta` does not.
func advance(delta: float) -> void:
	if delta <= 0.0 or _offset == Vector2.ZERO:
		return
	var keep := exp(-maxf(_recovery, 0.0) * delta)
	_offset *= keep
	if _offset.length() < 0.001:
		_offset = Vector2.ZERO


func offset() -> Vector2:
	return _offset


func reset() -> void:
	_offset = Vector2.ZERO
	_yaw_sign = 1.0


func describe() -> Dictionary:
	return {"pitch": _offset.x, "yaw": _offset.y, "recovery": _recovery}
