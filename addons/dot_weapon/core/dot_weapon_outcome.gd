class_name DotWeaponOutcome
extends RefCounted

## What one use produced, before anything has been traced, spawned or drawn.
##
## [b]A behaviour returns one of these and applies nothing itself.[/b] It is the same
## invariant dot-combat draws between an arsenal and a manager, moved up one level: the
## thing that decides a use happened runs on the owning client and on the server, and
## the thing that decides what it hit runs only where the authority is. Collapsing them
## is the obvious simplification and it is a client that decides who dies.
##
## [b]The kind is a [StringName] rather than an enum[/b], because an enum is a list this
## addon would own and a game adding a nineteenth kind of weapon would have to edit it.
## Nothing here branches on the kind; it is carried so a HUD, a sound bank and a
## statistic can tell a swing from a shot without inspecting the arrays.

## Conventional kinds. A game may use its own; these are only the ones this addon ships
## a behaviour for.
const KIND_NONE := &"none"
const KIND_SHOT := &"shot"          ## Traced this instant. A gun.
const KIND_SPAWN := &"spawn"        ## Put something in the world. An arrow, a rocket.
const KIND_SWING := &"swing"        ## A short traced arc. Melee.
const KIND_BEAM := &"beam"          ## Continuous while held.
const KIND_THROW := &"throw"        ## Released something that was being held.

var kind: StringName = KIND_NONE

## Whether the use happened at all.
##
## False is not an error: a melee swing that reached nothing, a repair tool aimed at
## full health and a bow released below its minimum draw are all ordinary refusals. The
## arsenal charges no ammunition and starts no cooldown for one.
var used: bool = false

## Why it did not happen, for a console and a bug report. Never shown to a player raw.
var refusal: String = ""

## Things for dot-combat to resolve now, against a world rewound to this tick.
var shots: Array[DotShot] = []

## Things for the game to put into the world, which will hit something later.
var spawns: Array[DotWeaponSpawn] = []

## Anything else the use produced, for a game's own behaviours.
##
## A physics gun's grab, a repair tool's heal, a deployable being placed. Deliberately
## untyped and deliberately not interpreted here, because the alternative is this addon
## growing a field for every game that adopts it.
var events: Array[Dictionary] = []

## Ammunition actually consumed. Negative means "whatever the definition says".
##
## A behaviour overrides it where a use costs a variable amount: a charged shot that
## spends its whole magazine, a burst that fired only two of three before running dry.
var ammo_used: int = -1

## Ticks before the next use. Negative means "whatever the definition says".
##
## A behaviour overrides it for a weapon whose cadence depends on what it just did,
## which is most melee weapons and every charged one.
var cooldown_ticks: int = -1

## Pitch and yaw kick in degrees, for the game to apply to its own camera.
##
## [b]A value, not an action.[/b] It is computed here and applied by whoever owns the
## camera, which is what lets one behaviour serve a first-person rig, a third-person
## one, a bot with no camera at all and a headless suite. dot-fx's camera shake is the
## same shape for the same reason.
var recoil: Vector2 = Vector2.ZERO


static func nothing(reason: String = "") -> DotWeaponOutcome:
	var o := DotWeaponOutcome.new()
	o.kind = KIND_NONE
	o.used = false
	o.refusal = reason
	return o


static func of(p_kind: StringName) -> DotWeaponOutcome:
	var o := DotWeaponOutcome.new()
	o.kind = p_kind
	o.used = true
	return o


## Adds a shot and returns it, so a behaviour can fill it in place.
func add_shot(shot: DotShot) -> DotShot:
	shots.append(shot)
	return shot


func add_spawn(spawn: DotWeaponSpawn) -> DotWeaponSpawn:
	spawns.append(spawn)
	return spawn


func add_event(event: Dictionary) -> void:
	events.append(event)


## Total damage across every shot, once the manager has resolved them.
##
## Zero before resolution and zero for a use that only spawned something, because a
## spawn has not hit anything yet.
func total_damage() -> float:
	var sum := 0.0
	for shot in shots:
		sum += shot.total_damage()
	return sum


func is_empty() -> bool:
	return shots.is_empty() and spawns.is_empty() and events.is_empty()


func describe() -> Dictionary:
	return {
		"kind": String(kind),
		"used": used,
		"refusal": refusal,
		"shots": shots.size(),
		"spawns": spawns.size(),
		"events": events.size(),
		"ammo_used": ammo_used,
		"cooldown_ticks": cooldown_ticks,
	}


func _to_string() -> String:
	if not used:
		return "DotWeaponOutcome(%s, refused: %s)" % [String(kind), refusal]
	return "DotWeaponOutcome(%s, %d shots, %d spawns)" % [
		String(kind), shots.size(), spawns.size()
	]
