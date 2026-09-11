class_name DotWeaponBehaviour
extends RefCounted

## The base every weapon extends. Guns, bows, melee, thrown, beams, and whatever a game
## writes that none of those describe.
##
## [b]Nothing in this addon should ever require a fork.[/b] A game adds a weapon by
## writing a script that extends this, pointing a [DotWeaponDef] at its path, and adding
## the row to a catalogue. It does not subclass the arsenal, it does not edit an enum
## here, and it does not need this addon to have anticipated it.
##
## [codeblock]
## extends "res://addons/dot_weapon/behaviour/dot_weapon_behaviour.gd"
##
## func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
##     var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SPAWN)
##     var arrow := DotWeaponSpawn.make(&"arrow", ctx.origin, ctx.direction * lerpf(
##         20.0, def.param_float(&"max_speed", 90.0), ctx.charge
##     ), ctx.entity)
##     arrow.damage = lerpf(12.0, 60.0, ctx.charge)
##     arrow.gravity_scale = 1.0
##     out.add_spawn(arrow)
##     return out
## [/codeblock]
##
## [b]Four rules, and they are the ones that break quietly rather than loudly.[/b]
##
## [b]1. Be a pure function of the context.[/b] A predicted weapon is simulated at least
## twice — once on the firing client, once on the server — and once more for every
## reconciliation replay after a correction. A behaviour that reads a wall clock, a
## node, an input device or a random stream produces a different answer on each of those
## runs, nothing errors, and the symptom is "hit registration feels bad". Use
## [DotWeaponSpread] for anything that needs to scatter.
##
## [b]2. Apply nothing.[/b] Return a [DotWeaponOutcome]; let dot-combat resolve the
## shots and let the game spawn the spawns. A behaviour that reached into a [DotHealth]
## would be a client deciding who dies.
##
## [b]3. Keep state in [member state], not in a member.[/b] The arsenal serialises
## [member state] across the wire and rolls it back on a correction. A field written
## directly on the behaviour survives neither.
##
## [b]4. Check [member DotWeaponContext.replayed] before anything visible.[/b] The
## simulation must re-run; a sound, an effect and a statistic must not.

## The row this behaviour was built for. Never null after [method setup].
var def: DotWeaponDef = null

## The arsenal carrying it, for a behaviour that needs to ask about ammunition or the
## other weapons. Null in a unit test that drives the behaviour directly.
var arsenal: Object = null

## Per-weapon state that survives a holster and travels on the wire.
##
## [b]Put every mutable thing here.[/b] The arsenal copies this dictionary into its
## snapshot, sends it, and restores it on a correction, which is what makes a bow's
## draw and a beam's heat survive the same reconciliation a magazine count does. A
## behaviour that keeps its charge in a plain member loses it on the first correction
## and nothing reports that it did.
var state: Dictionary = {}


# --- Called by the arsenal --------------------------------------------------

## Binds the behaviour to its row. Called once, before any other method.
func setup(p_def: DotWeaponDef, p_arsenal: Object = null) -> void:
	def = p_def
	arsenal = p_arsenal
	_setup()


## Brought up and now usable.
func deploy(ctx: DotWeaponContext) -> void:
	_deploy(ctx)


## Put away. Anything being held is let go of here.
##
## [b]Always called before a switch completes[/b], including one caused by death, by a
## correction or by a loadout change, so a behaviour holding something has exactly one
## place to release it.
func holster(ctx: DotWeaponContext) -> void:
	_holster(ctx)


## Whether a use may happen at all, beyond the ammunition and cadence the arsenal has
## already checked.
##
## A bow below its minimum draw, a repair tool aimed at nothing, a deployable with none
## left. Returning a failure means the arsenal charges nothing and starts no cooldown.
func can_use(ctx: DotWeaponContext) -> DotResult:
	return _can_use(ctx)


## The use itself.
func use(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var out := _use(ctx)
	return out if out != null else DotWeaponOutcome.nothing("The behaviour returned null.")


## One simulation tick while this weapon is deployed, used or not.
##
## Where a charge builds, a beam heats, a cooldown that is not the arsenal's own runs
## down, and a held object is dragged along.
func tick(ctx: DotWeaponContext) -> void:
	_tick(ctx)


## The use button was released.
##
## Called for every fire mode, not only [constant DotWeaponDef.Fire.CHARGE], because a
## beam that has to stop and a thrown charge that has to leave the hand are the same
## event.
func release(ctx: DotWeaponContext) -> DotWeaponOutcome:
	var out := _release(ctx)
	return out if out != null else DotWeaponOutcome.nothing("")


## A reload finished. A behaviour that tracks its own loaded state syncs it here.
func reloaded(rounds: int) -> void:
	_reloaded(rounds)


# --- Subclass interface -----------------------------------------------------
#
# Override these. Every one has a default that does nothing, so a behaviour that only
# shoots overrides exactly one.

func _setup() -> void:
	pass


func _deploy(_ctx: DotWeaponContext) -> void:
	pass


func _holster(_ctx: DotWeaponContext) -> void:
	pass


func _can_use(_ctx: DotWeaponContext) -> DotResult:
	return DotResult.success(null)


func _use(_ctx: DotWeaponContext) -> DotWeaponOutcome:
	return DotWeaponOutcome.nothing("This weapon does nothing when used.")


func _tick(_ctx: DotWeaponContext) -> void:
	pass


func _release(_ctx: DotWeaponContext) -> DotWeaponOutcome:
	return DotWeaponOutcome.nothing("")


func _reloaded(_rounds: int) -> void:
	pass


# --- Helpers for subclasses -------------------------------------------------

## Reads a tuning field from [member DotWeaponDef.tuning] if it has one, then from
## [member DotWeaponDef.params], then the fallback.
##
## The precedence is the typed resource first because it is the more specific of the
## two; see [DotWeaponTuning].
func tune(key: StringName, fallback: Variant = null) -> Variant:
	if def == null:
		return fallback

	if def.tuning != null:
		var name := String(key)
		if name in def.tuning:
			var v: Variant = def.tuning.get(name)
			if v != null:
				return v

	return def.params.get(key, fallback)


func tune_float(key: StringName, fallback: float = 0.0) -> float:
	var v: Variant = tune(key, fallback)
	return float(v) if v is float or v is int else fallback


func tune_int(key: StringName, fallback: int = 0) -> int:
	var v: Variant = tune(key, fallback)
	return int(v) if v is float or v is int else fallback


func tune_bool(key: StringName, fallback: bool = false) -> bool:
	var v: Variant = tune(key, fallback)
	return bool(v) if v is bool else fallback


## What a console command or a bug report dumps for this weapon.
##
## Override it to add the behaviour's own state; call the base and merge.
func describe() -> Dictionary:
	return {
		"weapon": String(def.id) if def != null else "",
		"behaviour": get_script().resource_path if get_script() != null else "",
		"state": state.duplicate(),
	}


func _to_string() -> String:
	return "DotWeaponBehaviour(%s)" % (String(def.id) if def != null else "unbound")
