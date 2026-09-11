class_name DotWeaponAmmo
extends RefCounted

## Reserve ammunition, pooled by name.
##
## [b]Pooled rather than per-weapon.[/b] Two weapons that declare the same
## [member DotWeaponDef.ammo_type] draw from one reserve, which is what lets a pistol
## and a carbine share a box of rounds, and what lets a quiver serve both bows. A game
## that wants a private reserve gives the weapon an ammo type nobody else uses, and
## gets the per-weapon behaviour back with no special case here.
##
## [b]Caps are per pool and set by whoever fills it[/b], because the ceiling is a mode's
## decision rather than a weapon's: the same rifle carries three magazines in one game
## and twelve in another.

var _pools: Dictionary = {}
var _caps: Dictionary = {}


## Rounds in a pool. An unknown pool is empty rather than an error, because a weapon
## whose ammunition nobody ever granted is a weapon with none.
func count(pool: StringName) -> int:
	return int(_pools.get(pool, 0))


func cap(pool: StringName) -> int:
	return int(_caps.get(pool, 0))


## Sets the ceiling. Zero means no ceiling. Lowering it clamps what is already there.
func set_cap(pool: StringName, value: int) -> void:
	_caps[pool] = maxi(0, value)
	if value > 0 and count(pool) > value:
		_pools[pool] = value


## Adds rounds, clamped to the cap. Returns how many were actually taken.
##
## The returned number is what a pickup needs: a box of 30 that only fitted 4 must
## leave 26 on the floor, and a caller that assumed it all went in creates ammunition.
func add(pool: StringName, amount: int) -> int:
	if pool == &"" or amount <= 0:
		return 0

	var have := count(pool)
	var ceiling := cap(pool)
	var room := amount if ceiling <= 0 else mini(amount, maxi(0, ceiling - have))

	if room <= 0:
		return 0

	_pools[pool] = have + room
	return room


## Takes rounds. Returns how many were actually available, which may be fewer.
func take(pool: StringName, amount: int) -> int:
	if pool == &"" or amount <= 0:
		return 0
	var have := count(pool)
	var got := mini(amount, have)
	_pools[pool] = have - got
	return got


func has(pool: StringName, amount: int) -> bool:
	return count(pool) >= amount


func set_count(pool: StringName, value: int) -> void:
	_pools[pool] = maxi(0, value)


func pools() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _pools.keys():
		out.append(key)
	out.sort()
	return out


func clear() -> void:
	_pools.clear()


func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in _pools.keys():
		out[String(key)] = int(_pools[key])
	return out


func restore(d: Dictionary) -> void:
	_pools.clear()
	for key: Variant in d.keys():
		_pools[StringName(str(key))] = int(d[key])


func describe() -> Dictionary:
	return snapshot()
