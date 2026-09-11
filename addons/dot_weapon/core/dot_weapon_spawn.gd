class_name DotWeaponSpawn
extends RefCounted

## Something a use put into the world: an arrow, a rocket, a grenade, a thrown knife.
##
## [b]This addon spawns nothing.[/b] It describes what should exist and hands the
## description to the game, which owns the scene, the node and the physics. That is the
## same division dot-fx draws between a catalogue and a scene, and it is what lets a
## dedicated server with none of the content installed still run the weapon: a server
## that only needs to know an arrow is travelling at 90 m/s from here does not need the
## arrow's mesh.
##
## [b]It is deliberately not a [DotShot].[/b] A shot is resolved the instant it is made,
## against a world rewound to the tick it was fired on. A spawn is an entity with a
## lifetime that will hit something several ticks from now, and lag compensation has
## nothing to say about it, because by then everybody has agreed where everybody is.

## What to spawn, in the game's own id space. Usually the weapon's id or a projectile id.
var id: StringName = &""

var origin: Vector3 = Vector3.ZERO

## Metres per second, already including any charge scaling the behaviour applied.
var velocity: Vector3 = Vector3.ZERO

## Collision radius. Zero means the game decides.
var radius: float = 0.1

## Ticks before it expires on its own, whatever it thinks it is doing.
##
## [b]A hard ceiling, not a hint.[/b] A projectile that forgets to free itself is a leak
## that looks like a slow memory problem in the game rather than a bug in one weapon.
var life_ticks: int = 384

## Gravity multiplier. 0 is a rocket, 1 is an arrow, higher is a lobbed grenade.
var gravity_scale: float = 0.0

## What it does on contact. The game applies it; this addon never does.
var damage: float = 0.0

var damage_type: DotDamageType = null

## Radius of the splash on contact. Zero means it only damages what it touched.
var splash_radius: float = 0.0

var splash_damage: float = 0.0

## Ticks it waits before it goes off by itself. Zero means it needs contact.
##
## A cooked grenade is a spawn with a fuse; an arrow is a spawn without one.
var fuse_ticks: int = 0

## The carrier, so the game can bill the damage to somebody.
var owner_entity: int = 0

## The tick it was created on.
var tick: int = 0

## Anything the game's own projectile script reads.
var meta: Dictionary = {}


static func make(
	p_id: StringName,
	p_origin: Vector3,
	p_velocity: Vector3,
	p_owner: int
) -> DotWeaponSpawn:
	var s := DotWeaponSpawn.new()
	s.id = p_id
	s.origin = p_origin
	s.velocity = p_velocity
	s.owner_entity = p_owner
	return s


func speed() -> float:
	return velocity.length()


func describe() -> Dictionary:
	return {
		"id": String(id),
		"origin": origin,
		"speed": speed(),
		"life_ticks": life_ticks,
		"damage": damage,
		"fuse_ticks": fuse_ticks,
		"owner": owner_entity,
	}


func _to_string() -> String:
	return "DotWeaponSpawn(%s, %.1f m/s)" % [String(id), speed()]
