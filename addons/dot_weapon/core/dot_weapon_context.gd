class_name DotWeaponContext
extends RefCounted

## Everything a behaviour is told about one use, and nothing it could use to cheat.
##
## [b]A behaviour is handed a context rather than a player.[/b] It gets an origin and a
## direction, not a camera; a tick, not a clock; an entity id, not a node. That is what
## lets the same weapon run on the owning client predicting, on the server resolving,
## in a reconciliation replay, for a bot with no viewport and in a headless suite, all
## of which are the situations where a weapon that reached for `get_viewport()` stops
## working. It is dot-props' rule for tools, kept.
##
## [b]Every field is an input to a pure function.[/b] Two machines handed the same
## context must produce the same outcome, because one of them is predicting what the
## other will do. Nothing here is a wall clock and nothing here is drawn from a random
## stream; see [DotWeaponSpread] for why that matters more than it looks.

## The carrier, in the game's own id space. Matched against [member DotDamage.attacker].
var entity: int = 0

## The tick this use happens on. Authoritative on a server, claimed on a client.
var tick: int = 0

## Index of this use within the carrier's history, so two uses on the same tick differ.
##
## A weapon that can be used faster than the tick rate is why this exists, and it is an
## input to the spread hash rather than a counter anybody reads.
var index: int = 0

## Where the use starts. An eye position, a muzzle, a hand.
var origin: Vector3 = Vector3.ZERO

## Unit aim direction, before any spread the behaviour applies.
var direction: Vector3 = Vector3.FORWARD

## 0..1 for a [constant DotWeaponDef.Fire.CHARGE] weapon, 1 for everything else.
##
## A bow reads this and scales its arrow; a railgun reads it and scales its damage; a
## pistol ignores it and gets 1.
var charge: float = 1.0

## Ticks the use button has been held, for a [constant DotWeaponDef.Fire.HOLD] weapon.
##
## A flamethrower that ramps up, a repair tool that heals faster the longer it is on
## one target, a physics gun that has been holding something for a while.
var held_ticks: int = 0

## How the carrier is moving, for a behaviour that widens its spread when they are.
##
## Set by the game from whatever it already knows. Left at zero it simply has no
## effect, which is correct for a game with no movement penalty.
var speed: float = 0.0

## Whether the carrier is off the ground.
var airborne: bool = false

## Whether the carrier is crouched.
var crouched: bool = false

## Set on a use produced by a replay rather than by a fresh command.
##
## [b]A predicted client re-runs its inputs after every correction[/b], and a replayed
## use must not fire an effect, play a sound or bill a statistic a second time. The
## simulation still runs; only the things that are visible once must check this.
var replayed: bool = false

## True on the machine that decides. A behaviour must not apply anything when false.
var authority: bool = false

## Anything the game wants to hand through to its own behaviours.
##
## The escape hatch, and deliberately the last resort: a field here is one this addon
## cannot validate, cannot replicate and cannot reason about. Prefer a real field.
var extra: Dictionary = {}


static func make(
	p_entity: int,
	p_tick: int,
	p_origin: Vector3,
	p_direction: Vector3
) -> DotWeaponContext:
	var ctx := DotWeaponContext.new()
	ctx.entity = p_entity
	ctx.tick = p_tick
	ctx.origin = p_origin
	ctx.direction = p_direction.normalized()
	return ctx


func describe() -> Dictionary:
	return {
		"entity": entity,
		"tick": tick,
		"index": index,
		"charge": charge,
		"held_ticks": held_ticks,
		"replayed": replayed,
		"authority": authority,
	}


func _to_string() -> String:
	return "DotWeaponContext(entity %d, tick %d, index %d)" % [entity, tick, index]
