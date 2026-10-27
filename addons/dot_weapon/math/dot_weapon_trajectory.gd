class_name DotWeaponTrajectory
extends RefCounted

## Pure ballistic maths for [DotWeaponBallistics]: fixed sub-steps with a ray per step (no tunnelling),
## damage falloff, and the aim solver bots use. No nodes, no clock, no random stream, so server, client
## and replay agree. A game batches bullets in one node and calls [method fly] for each.

## Seconds per sub-step. Fixed, so the path does not depend on the frame rate.
const STEP := 1.0 / 120.0

## Gravity in m/s^2 (positive; applied downwards).
const GRAVITY := 9.8


## True when [param b] asks for a simulated bullet rather than a hitscan.
static func is_simulated(b: DotWeaponBallistics) -> bool:
	return b != null and b.muzzle_velocity > 0.0


## One sub-step: returns [new_pos, new_vel]. Semi-implicit Euler, drag applied to speed.
static func step(pos: Vector3, vel: Vector3, b: DotWeaponBallistics, dt: float = STEP) -> Array:
	vel += Vector3.DOWN * GRAVITY * b.bullet_gravity * dt
	var speed := vel.length()
	if speed > 0.0 and b.drag > 0.0:
		vel *= maxf(0.0, 1.0 - b.drag * speed * dt)
	return [pos + vel * dt, vel]


## Flies a bullet from [param origin] along [param dir] until it hits, runs out of range or lives past
## [param max_time]. [param cast] is `func(from: Vector3, to: Vector3) -> Dictionary` (empty = clear; a
## hit carries `position`), called once per sub-step over the whole segment so nothing is skipped.
## Returns `{hit, position, time, distance, speed, path_end}`.
static func fly(origin: Vector3, dir: Vector3, b: DotWeaponBallistics, cast: Callable, max_time: float = 10.0) -> Dictionary:
	var pos := origin
	var vel := dir.normalized() * b.muzzle_velocity
	var t := 0.0
	var dist := 0.0
	while t < max_time and dist < b.max_range:
		var st := step(pos, vel, b)
		var next: Vector3 = st[0]
		var h: Dictionary = cast.call(pos, next) if cast.is_valid() else {}
		if not h.is_empty():
			var at: Vector3 = h.get("position", next)
			return {"hit": h, "position": at, "time": t + STEP * pos.distance_to(at) / maxf(pos.distance_to(next), 0.0001),
				"distance": dist + pos.distance_to(at), "speed": (st[1] as Vector3).length(), "path_end": at}
		dist += pos.distance_to(next)
		pos = next
		vel = st[1]
		t += STEP
	return {"hit": {}, "position": pos, "time": t, "distance": dist, "speed": vel.length(), "path_end": pos}


## Vertical drop in metres below the bore line, flight time and remaining speed at horizontal
## [param range_m] for a bullet fired level.
static func drop_at(b: DotWeaponBallistics, range_m: float) -> Dictionary:
	var pos := Vector3.ZERO
	var vel := Vector3(0.0, 0.0, -b.muzzle_velocity)
	var t := 0.0
	while -pos.z < range_m and t < 30.0 and vel.length() > 1.0:
		var st := step(pos, vel, b)
		pos = st[0]
		vel = st[1]
		t += STEP
	return {"drop": -pos.y, "time": t, "speed": vel.length()}


## Damage multiplier at [param dist] metres: 1 up to falloff_start, then linear to falloff_min at max_range.
static func falloff(b: DotWeaponBallistics, dist: float) -> float:
	if b.falloff_min >= 1.0 or dist <= b.falloff_start or b.max_range <= b.falloff_start:
		return 1.0
	return lerpf(1.0, b.falloff_min, clampf((dist - b.falloff_start) / (b.max_range - b.falloff_start), 0.0, 1.0))


## Damage after passing [param thickness] metres of material that stops [param stopping] metres of
## penetration depth at full strength. Returns the multiplier, 0 when stopped.
static func through(b: DotWeaponBallistics, thickness: float, stopping: float = 1.0) -> float:
	if b.penetration <= 0.0:
		return 0.0
	var need := thickness * maxf(stopping, 0.0001)
	return 0.0 if need >= b.penetration else 1.0 - need / b.penetration


## Pitch in radians above the line to the target that lands the bullet on a target [param range_m]
## away horizontally and [param height] metres above the muzzle. NAN when out of reach.
static func solve_pitch(b: DotWeaponBallistics, range_m: float, height: float = 0.0) -> float:
	var lo := -0.5
	var hi := 0.8
	if _miss_height(b, hi, range_m, height) < 0.0:
		return NAN
	for i in 24:
		var mid := (lo + hi) * 0.5
		if _miss_height(b, mid, range_m, height) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5 - atan2(height, range_m)


## Aim point for a moving target: the position to aim the bore at (drop compensated) given the
## target's position and velocity. Iterates the flight time, which converges in a few passes.
static func lead(b: DotWeaponBallistics, muzzle: Vector3, target: Vector3, target_vel: Vector3) -> Vector3:
	var aim := target
	for i in 4:
		var flat := Vector2(aim.x - muzzle.x, aim.z - muzzle.z)
		var rng := flat.length()
		var h := aim.y - muzzle.y
		var pitch := solve_pitch(b, rng, h)
		if is_nan(pitch):
			return aim
		var line := atan2(h, rng)
		var t := float(drop_time(b, rng, line + pitch))
		aim = target + target_vel * t
	var flat2 := Vector2(aim.x - muzzle.x, aim.z - muzzle.z)
	var r := flat2.length()
	var hh := aim.y - muzzle.y
	var pp := solve_pitch(b, r, hh)
	if is_nan(pp):
		return aim
	# Raise the aim point so a bore pointed at it lands on the lead point.
	return Vector3(aim.x, muzzle.y + tan(atan2(hh, r) + pp) * r, aim.z)


## Flight time to horizontal [param range_m] when fired at [param pitch] radians.
static func drop_time(b: DotWeaponBallistics, range_m: float, pitch: float) -> float:
	var pos := Vector3.ZERO
	var vel := Vector3(0.0, sin(pitch), -cos(pitch)) * b.muzzle_velocity
	var t := 0.0
	while -pos.z < range_m and t < 30.0 and vel.length() > 1.0:
		var st := step(pos, vel, b)
		pos = st[0]
		vel = st[1]
		t += STEP
	return t


# Height of the bullet above the target when it reaches the target's range, fired at [param pitch]
# relative to the line to the target (negative = below).
static func _miss_height(b: DotWeaponBallistics, pitch: float, range_m: float, height: float) -> float:
	var angle := pitch
	var pos := Vector3.ZERO
	var vel := Vector3(0.0, sin(angle), -cos(angle)) * b.muzzle_velocity
	var t := 0.0
	while -pos.z < range_m and t < 30.0:
		var st := step(pos, vel, b)
		pos = st[0]
		vel = st[1]
		t += STEP
		if vel.length() < 1.0:
			break
	return pos.y - height if -pos.z >= range_m else -INF
