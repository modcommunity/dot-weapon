class_name DotWeaponBullets
extends Node

## Every simulated bullet in one node (no node per bullet), stepped once per game tick. Server
## authority: [signal hit] is what applies damage; clients only draw [signal tracer] segments.
##
## Lag compensation matches dot-combat: [member rewind_fn] puts targets where the shooter saw them at a
## tick, [member restore_fn] undoes it. A bullet remembers how many ticks behind its shooter was, so each
## sub-step is cast against the world as of `now - lag`, and the world is restored before returning.

## Bullet [param id] hit [param info] (the cast result) after [param distance] metres.
## [param damage_mult] is the falloff multiplier at that distance.
signal hit(id: int, owner_id: int, info: Dictionary, distance: float, damage_mult: float, tuning: DotWeaponBallistics)
## A tracer bullet moved from [param from] to [param to] this tick.
signal tracer(id: int, from: Vector3, to: Vector3)
## Emitted just before the world is rewound for [param owner_id]'s bullet, so a game can leave the shooter where they are.
signal rewinding(owner_id: int)
## A bullet ended without hitting anything.
signal expired(id: int)

## `func(from: Vector3, to: Vector3, owner_id: int) -> Dictionary`, empty for clear.
var cast_fn: Callable = Callable()
## `func(tick: float)` and `func()`, as dot-combat's.
var rewind_fn: Callable = Callable()
var restore_fn: Callable = Callable()
var rules: DotWeaponBallisticsRules = null
var tick_rate: int = 64

var _next_id: int = 1
var _ids: PackedInt32Array = []
var _owners: PackedInt32Array = []
var _lags: PackedFloat32Array = []
var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _dist: PackedFloat32Array = []
var _tuning: Array = []
var _tracer: PackedByteArray = []
var _shots: Dictionary = {}
var _scaled: Dictionary = {}


func count() -> int:
	return _ids.size()


## Starts a bullet; returns its id, or 0 when rules are off, the weapon is hitscan, or the cap is hit.
func spawn(owner_id: int, origin: Vector3, dir: Vector3, b: DotWeaponBallistics, lag_ticks: float = 0.0) -> int:
	if not DotWeaponBallisticsRules.simulates(rules, b) or _ids.size() >= int(rules.max_bullets):
		return 0
	var key := b.get_instance_id()
	if not _scaled.has(key):
		_scaled[key] = rules.scaled(b)
		if not rules.changed.is_connected(_drop_cache):
			rules.changed.connect(_drop_cache)
	var eff: DotWeaponBallistics = _scaled[key]
	var id := _next_id
	_next_id += 1
	_ids.append(id)
	_owners.append(owner_id)
	_lags.append(lag_ticks)
	_pos.append(origin)
	_vel.append(dir.normalized() * eff.muzzle_velocity)
	_dist.append(0.0)
	_tuning.append(eff)
	var n := int(_shots.get(owner_id, 0)) + 1
	_shots[owner_id] = n
	_tracer.append(1 if eff.tracer_interval > 0 and n % eff.tracer_interval == 0 else 0)
	return id


## Advances every bullet by one game tick at [param now_tick]. Call from the physics tick on the server.
func step(now_tick: float) -> void:
	var subs := maxi(1, roundi(1.0 / (float(tick_rate) * DotWeaponTrajectory.STEP)))
	var i := _ids.size() - 1
	while i >= 0:
		if _fly_tick(i, now_tick, subs):
			_remove(i)
		i -= 1


func _fly_tick(i: int, now_tick: float, subs: int) -> bool:
	var b: DotWeaponBallistics = _tuning[i]
	var start := _pos[i]
	var rewound := false
	if _lags[i] > 0.0 and rewind_fn.is_valid() and restore_fn.is_valid():
		rewinding.emit(_owners[i])
		rewind_fn.call(now_tick - _lags[i])
		rewound = true
	var done := false
	for _s in subs:
		var st := DotWeaponTrajectory.step(_pos[i], _vel[i], b)
		var next: Vector3 = st[0]
		var h: Dictionary = cast_fn.call(_pos[i], next, _owners[i]) if cast_fn.is_valid() else {}
		if not h.is_empty():
			var at: Vector3 = h.get("position", next)
			_dist[i] += _pos[i].distance_to(at)
			_pos[i] = at
			hit.emit(_ids[i], _owners[i], h, _dist[i], DotWeaponTrajectory.falloff(b, _dist[i]), b)
			done = true
			break
		_dist[i] += _pos[i].distance_to(next)
		_pos[i] = next
		_vel[i] = st[1]
		if _dist[i] >= b.max_range or _vel[i].length() < 5.0:
			expired.emit(_ids[i])
			done = true
			break
	if rewound:
		restore_fn.call()
	if _tracer[i] == 1:
		tracer.emit(_ids[i], start, _pos[i])
	return done


func _drop_cache() -> void:
	_scaled.clear()


func _remove(i: int) -> void:
	_ids.remove_at(i)
	_owners.remove_at(i)
	_lags.remove_at(i)
	_pos.remove_at(i)
	_vel.remove_at(i)
	_dist.remove_at(i)
	_tuning.remove_at(i)
	_tracer.remove_at(i)


func describe() -> Dictionary:
	return {"bullets": _ids.size(), "enabled": rules != null and rules.enabled}
