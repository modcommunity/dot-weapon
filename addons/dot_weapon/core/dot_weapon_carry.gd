class_name DotWeaponCarry
extends RefCounted

## What a carrier may carry: a weight limit, weapons per slot, backpacks, and the modifiers a game hangs
## on them. One instance is shared by every arsenal; none (the default) means no limit.
## Weights live on [member DotWeaponDef.weight]; a modifier is a named source set with [method set_modifier].

enum OverLimit {
	## Over the limit the carrier is slowed ([method speed_scale]); nothing is taken.
	SLOW,
	## Over the limit the arsenal drops weapons until it is under ([method DotWeaponArsenal.enforce_limit]).
	DROP,
}

signal changed

## Whether any of this applies. Off, every weight is 0 and the limit is infinite.
var enabled: bool = false:
	set(v):
		if enabled != v:
			enabled = v
			changed.emit()

## Carry capacity with no backpack and no modifier.
var base_limit: float = 30.0:
	set(v):
		base_limit = maxf(v, 0.0)
		changed.emit()

## Every weight is multiplied by this ("heavier gear" for the whole game).
var multiplier: float = 1.0:
	set(v):
		multiplier = maxf(v, 0.0)
		changed.emit()

## Weapons one slot may hold; 1 is the old one-per-slot rule. Pressing the slot's key again cycles.
var slot_capacity: int = 1:
	set(v):
		slot_capacity = clampi(v, 1, 16)
		changed.emit()

## What happens when the carrier is over the limit (a modifier ended, a limit dropped).
var over_limit: OverLimit = OverLimit.SLOW

## The slowest [method speed_scale] goes, however far over.
var slow_floor: float = 0.5

## Capacity added by backpack tier 1, 2, 3...; the tier above the last is the last. Empty: no backpacks.
var backpack_tiers: PackedFloat32Array = PackedFloat32Array([10.0, 20.0, 35.0])

## source -> {"weight": factor, "limit": factor, "add": units}
var _mods: Dictionary = {}


## Scales every weight by [param weight_factor] and the limit by [param limit_factor], and adds
## [param limit_add] units to it, for as long as [param source] stands. Setting a source again replaces it.
func set_modifier(source: StringName, weight_factor: float = 1.0, limit_factor: float = 1.0, limit_add: float = 0.0) -> void:
	var mod := {"weight": maxf(weight_factor, 0.0), "limit": maxf(limit_factor, 0.0), "add": limit_add}
	if _mods.get(source, {}) == mod:
		return
	_mods[source] = mod
	changed.emit()


func clear_modifier(source: StringName) -> void:
	if _mods.erase(source):
		changed.emit()


func clear_modifiers() -> void:
	if not _mods.is_empty():
		_mods.clear()
		changed.emit()


func modifiers() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _mods:
		out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The product of every modifier's weight factor, times [member multiplier].
func weight_factor() -> float:
	var out := multiplier
	for k: StringName in _mods:
		out *= float(_mods[k]["weight"])
	return out


## What [param def] weighs to a carrier now.
func weight_of(def: DotWeaponDef) -> float:
	if not enabled or def == null:
		return 0.0
	return def.weight * weight_factor()


## Capacity added by a backpack of [param tier] (0: none).
func backpack_bonus(tier: int) -> float:
	if tier <= 0 or backpack_tiers.is_empty():
		return 0.0
	return backpack_tiers[mini(tier, backpack_tiers.size()) - 1]


func max_backpack_tier() -> int:
	return backpack_tiers.size()


## What a carrier with a backpack of [param tier] may carry now; INF when off.
func limit_for(tier: int = 0) -> float:
	if not enabled:
		return INF
	var out := base_limit + backpack_bonus(tier)
	var added := 0.0
	for k: StringName in _mods:
		out *= float(_mods[k]["limit"])
		added += float(_mods[k]["add"])
	return maxf(out + added, 0.0)


## The speed multiplier for [param carried] against [param limit]: 1 at or under, falling with the
## excess share down to [member slow_floor].
func speed_scale(carried: float, limit: float) -> float:
	if not enabled or over_limit != OverLimit.SLOW or carried <= limit or carried <= 0.0:
		return 1.0
	var excess := (carried - limit) / maxf(carried, 0.001)
	return clampf(1.0 - excess, clampf(slow_floor, 0.05, 1.0), 1.0)


func describe() -> Dictionary:
	return {
		"enabled": enabled, "base_limit": base_limit, "multiplier": multiplier, "slot_capacity": slot_capacity,
		"over_limit": OverLimit.keys()[over_limit], "backpack_tiers": Array(backpack_tiers),
		"weight_factor": weight_factor(), "limit_now": limit_for(0) if enabled else -1.0,
		"modifiers": modifiers().map(func(k: StringName) -> String: return String(k)),
	}
