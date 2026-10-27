class_name DotWeaponBulletBridge
extends Node

## Flies simulated bullets for dot-combat: a drop-in for `combat.resolve_shot(shot, view_tick)`.
##
## With the rules off, or a weapon with no muzzle velocity, [method resolve_shot] is exactly
## `combat.resolve_shot`. With them on, the hitscan behaviour has marked the shot deferred, so dot-combat
## records only endpoints, and this launches one bullet per pellet. Rays, hitboxes, rewind and damage are
## dot-combat's own ([member DotCombatManager.trace], `rewind_fn`, `apply_damage`), so a game writes none.

signal bullet_hit(id: int, damage: DotDamage)

var combat: DotCombatManager = null
var bullets: DotWeaponBullets = null
var _shots: Dictionary = {}
var _ids_by_shot: Dictionary = {}


## [param rules] is the shared [DotWeaponBallisticsRules]; call once the manager is set up.
func setup(manager: DotCombatManager, rules: DotWeaponBallisticsRules, tick_rate: int = 64) -> void:
	combat = manager
	bullets = DotWeaponBullets.new()
	bullets.name = "Bullets"
	bullets.rules = rules
	bullets.tick_rate = tick_rate
	bullets.cast_fn = _cast
	bullets.rewind_fn = _rewind
	bullets.restore_fn = _restore
	bullets.hit.connect(_on_hit)
	bullets.expired.connect(func(id: int) -> void: _shots.erase(id))
	add_child(bullets)


## Resolve [param shot] fired by a weapon with [param tuning]. Returns the shot either way.
func resolve_shot(shot: DotShot, tuning: DotWeaponBallistics, view_tick: float = -1.0) -> DotShot:
	var res := combat.resolve_shot(shot, view_tick)
	if bullets == null or not shot.deferred or not DotWeaponBallisticsRules.simulates(bullets.rules, tuning):
		return res
	var lag := maxf(float(shot.tick) - view_tick, 0.0) if view_tick >= 0.0 else 0.0
	for dir in shot.pellets:
		var id := bullets.spawn(shot.attacker, shot.origin, dir, tuning, lag)
		if id > 0:
			_shots[id] = shot
	return res


## Advance every bullet; call once per server tick.
func tick(now_tick: float) -> void:
	if bullets != null:
		bullets.step(now_tick)


func _cast(from: Vector3, to: Vector3, owner_id: int) -> Dictionary:
	var offset := to - from
	var dist := offset.length()
	if dist <= 0.0:
		return {}
	var shooter := combat.hitboxes_of(owner_id)
	combat.trace.exclude = [shooter] if shooter != null else []
	var hit := combat.trace.ray(from, offset / dist, dist, combat.hitbox_sets())
	if not hit.ok():
		return {}
	return {"position": hit.point, "trace": hit}


func _rewind(tick_value: float) -> void:
	if combat.rewind_fn.is_valid():
		combat.rewind_fn.call(tick_value)


func _restore() -> void:
	if combat.restore_fn.is_valid():
		combat.restore_fn.call()


func _on_hit(id: int, owner_id: int, info: Dictionary, distance: float, mult: float, _tuning: DotWeaponBallistics) -> void:
	var shot: DotShot = _shots.get(id)
	_shots.erase(id)
	var hit: Variant = info.get("trace")
	if shot == null or hit == null or hit.blocked or hit.entity == null:
		return
	var victim := combat._entity_id_of(hit.entity)
	if victim == 0:
		return
	var type := shot.damage_type if shot.damage_type != null else combat.damage_type(&"")
	var damage := DotDamage.make(owner_id, victim, shot.damage * mult * combat.config.damage_scale, type)
	damage.hit_group = hit.group
	damage.limb = hit.limb
	damage.context["entity"] = hit.entity
	damage.point = hit.point
	damage.distance = distance
	damage.weapon_id = shot.weapon_id
	damage.tick = shot.tick
	if hit.hitbox != null:
		damage.scale_by(hit.hitbox.damage_scale, "hitbox")
	bullet_hit.emit(id, combat.apply_damage(damage))
