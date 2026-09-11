@tool
class_name DotWeaponDef
extends Resource

## One thing a player can hold, as a document rather than as a class.
##
## [b]This resource describes only what the arsenal's state machine needs to run:[/b]
## which slot it occupies, how long it takes to bring up and put away, what counts as a
## use, what a use costs, and how it is reloaded. It says nothing whatsoever about what
## a use [i]does[/i]. That belongs to the behaviour named in [member behaviour_path].
##
## [b]That line is the whole design.[/b] The obvious alternative is one fat resource
## carrying every field any weapon might want, and it is what this replaces: a
## definition with `pellets`, `spread_bloom`, `projectile_gravity` and `splash_radius`
## on it can describe nine kinds of gun and cannot describe a bow, because a bow's
## damage comes from how long it was drawn and there is no field for that. Adding one
## means editing the addon, and a game that has to edit the addon to add a weapon has a
## fork rather than a dependency. Here a bow is an entry in a table.
##
## [b]The behaviour is a path, never a `class_name`.[/b] A game delivered as a dot-cloud
## content pack is mounted at runtime and [b]a mounted pack's `class_name` globals are
## not registered in the host[/b], so a weapon named by class could only ever ship
## inside the build. This is the same rule dot-props names a prop's script by, and the
## same reason dot-fx's catalogue holds a `scene_path` rather than a [PackedScene].
##
## [b]It is a document, so a server can check the whole table at boot[/b], headless,
## with none of the content installed, which is the only moment anybody is watching.
## [method validate] loads nothing and draws nothing.

## What a press of the use button means.
##
## This is the arsenal's business rather than the behaviour's, because it decides
## [i]when[/i] `_use` is called rather than what it does. A bow and a railgun are both
## [constant CHARGE]; a beam and a physics gun are both [constant HOLD]; that they do
## entirely different things on release is the behaviour's half.
enum Fire {
	## One use per press. A pistol, a bolt-action, a thrown charge with no cook.
	SEMI,
	## Repeats while held, at [member use_interval_ticks].
	AUTO,
	## [member burst_count] uses per press, at [member burst_interval_ticks].
	BURST,
	## Press builds charge, release uses once. A bow, a railgun, a charged shot.
	##
	## The behaviour is handed the charge it accumulated and decides what that is worth.
	CHARGE,
	## Continuous while held. A beam, a flamethrower, a repair tool, a physics gun.
	##
	## `_use` is called every tick the button is down, and the behaviour is told how
	## long it has been down for.
	HOLD,
}

@export_group("Identity")

## Stable id. What a loadout names, what a console command types, what a HUD draws.
@export var id: StringName = &""

@export var display_name: String = ""

## One line for a menu or a pickup prompt. What it does, not how.
@export var description: String = ""

## Free-form labels. Menu grouping, ammo sharing, "primary"/"secondary", a mode's
## own rules about what may be carried.
##
## The whole of the categorisation system and deliberately no more than that, for
## [DotEffectDef]'s reason: a rule that names weapon ids directly is a rule that has to
## be edited every time a weapon is added.
@export var tags: Array[StringName] = []

@export_group("Behaviour")

## The behaviour script's path. Must extend [DotWeaponBehaviour].
##
## A path rather than a class, for the reason in the class note. Resolved once by
## [method DotWeaponCatalogue.instantiate], never by this resource.
@export_file("*.gd") var behaviour_path: String = ""

## Everything the behaviour's own script reads, and nothing this addon interprets.
##
## [b]Tuning lives here rather than in the script[/b] so one script serves many
## entries: a hunting bow and a war bow are one behaviour and two rows. Same argument
## as [DotPropDef.meta] and [DotFxDef]'s catalogue.
##
## Use [member tuning] instead where a game wants the values typed and in the
## inspector; the two are not exclusive.
@export var params: Dictionary = {}

## Typed tuning, for a behaviour that would rather be configured in the inspector than
## through [member params].
##
## Optional and untouched by this addon beyond being handed to the behaviour. A game
## subclasses [DotWeaponTuning] and gets range hints, groups and documentation on its
## own fields; [member params] stays available for a pack that cannot register a class.
@export var tuning: DotWeaponTuning = null

@export_group("Handling")

## Which slot this occupies. Two weapons in one slot cannot be carried together.
@export_range(1, 16, 1) var slot: int = 1

## Ticks to bring it up before it may be used.
##
## Ticks, like everything else in this family. A weapon whose deploy is measured in
## seconds is a weapon that deploys at two different speeds on a 64 Hz server and a
## 128 Hz one, which is two different games.
@export_range(0, 10000, 1) var deploy_ticks: int = 22

## Ticks to put it away before another may be brought up.
@export_range(0, 10000, 1) var holster_ticks: int = 13

@export_group("Using")

@export var fire_mode: Fire = Fire.SEMI

## Ticks between uses. Zero means once per tick.
@export_range(0, 100000, 1) var use_interval_ticks: int = 7

## Uses per press under [constant Fire.BURST].
@export_range(1, 64, 1) var burst_count: int = 3

## Ticks between the uses within one burst.
@export_range(0, 100000, 1) var burst_interval_ticks: int = 3

## Ticks to reach full charge under [constant Fire.CHARGE].
##
## The behaviour is handed a charge from 0 to 1 and decides what it is worth. Holding
## past full is not an error and the charge simply stays at 1, because a bow held at
## full draw is a bow being aimed.
@export_range(1, 100000, 1) var charge_ticks: int = 64

## Whether a charge below [member min_charge] is refused rather than released weakly.
##
## Off suits a bow, where a light tap is a weak arrow. On suits a weapon that must not
## be spammed at minimum power.
@export var charge_requires_min: bool = false

## The charge below which a release is refused when [member charge_requires_min].
@export_range(0.0, 1.0, 0.01) var min_charge: float = 0.35

@export_group("Ammunition")

## The pool this draws from. Empty means it needs no ammunition at all.
##
## A name rather than a reference, so two weapons share a pool by agreeing on a string
## and a melee weapon, a physics gun and a repair tool simply leave it blank.
@export var ammo_type: StringName = &""

## Rounds in a full magazine. Zero means it feeds straight from the reserve.
@export_range(0, 10000, 1) var magazine: int = 0

## Rounds carried beyond the magazine when the arsenal is filled from defaults.
@export_range(0, 99999, 1) var reserve: int = 0

## The ceiling on the reserve. Zero means [member reserve] is also the cap.
@export_range(0, 99999, 1) var reserve_max: int = 0

## What one use costs. Zero means a use is free even though the weapon has a pool.
@export_range(0, 1000, 1) var cost_per_use: int = 1

## Never decrements the reserve. The magazine still empties and still reloads.
@export var infinite_reserve: bool = false

@export_group("Reloading")

## Ticks for a whole-magazine reload.
@export_range(0, 100000, 1) var reload_ticks: int = 141

## Reloads one round at a time, so it may be interrupted with a partial magazine.
@export var reload_per_round: bool = false

## Ticks before the first round arrives under [member reload_per_round].
@export_range(0, 100000, 1) var reload_start_ticks: int = 22

## Begins a reload by itself on an empty magazine.
@export var auto_reload: bool = true


# --- Queries ----------------------------------------------------------------

func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


## Whether it feeds from a magazine rather than straight from the reserve.
func uses_magazine() -> bool:
	return magazine > 0


## Whether it draws from an ammunition pool at all.
func uses_ammo() -> bool:
	return ammo_type != &"" and cost_per_use > 0


## The reserve ceiling, resolving the "zero means [member reserve]" default.
func reserve_cap() -> int:
	return reserve_max if reserve_max > 0 else reserve


## Whether the arsenal should accumulate a charge for this weapon.
func is_charged() -> bool:
	return fire_mode == Fire.CHARGE


## Whether a held button keeps producing uses.
func is_continuous() -> bool:
	return fire_mode == Fire.AUTO or fire_mode == Fire.HOLD


## Charge from 0 to 1 after [param ticks_held] ticks on the button.
func charge_at(ticks_held: int) -> float:
	if charge_ticks <= 0:
		return 1.0
	return clampf(float(ticks_held) / float(charge_ticks), 0.0, 1.0)


## One value from [member params], falling back when the key is absent.
##
## Behaviours read their tuning through this rather than indexing directly, so a row
## that omits a key gets the behaviour's own default instead of a null.
func param(key: StringName, fallback: Variant = null) -> Variant:
	return params.get(key, fallback)


func param_float(key: StringName, fallback: float = 0.0) -> float:
	var v: Variant = params.get(key, fallback)
	return float(v) if v is float or v is int else fallback


func param_int(key: StringName, fallback: int = 0) -> int:
	var v: Variant = params.get(key, fallback)
	return int(v) if v is float or v is int else fallback


func param_bool(key: StringName, fallback: bool = false) -> bool:
	var v: Variant = params.get(key, fallback)
	return bool(v) if v is bool else fallback


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


# --- Validation -------------------------------------------------------------

## Checks the document without loading the behaviour or touching the filesystem.
##
## [b]Deliberately does not load [member behaviour_path].[/b] A dedicated server
## validating a catalogue at boot may legitimately not have the script yet, because the
## content pack carrying it has not been mounted. Whether the path resolves is
## [method DotWeaponCatalogue.instantiate]'s question, asked when it matters.
func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A weapon needs an id.")

	var where := String(id)

	if behaviour_path == "":
		return DotResult.fail(
			DotError.CODE_INVALID, "A weapon needs a behaviour_path.", where
		)

	if not behaviour_path.ends_with(".gd"):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"behaviour_path must name a GDScript file, not %s." % behaviour_path,
			where
		)

	if slot < 1:
		return DotResult.fail(DotError.CODE_INVALID, "slot must be 1 or more.", where)

	if reserve_max > 0 and reserve > reserve_max:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"reserve %d is above reserve_max %d." % [reserve, reserve_max],
			where
		)

	if magazine == 0 and reload_ticks > 0 and reload_per_round:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"reload_per_round needs a magazine to put the rounds in.",
			where
		)

	if fire_mode == Fire.CHARGE and charge_ticks <= 0:
		return DotResult.fail(
			DotError.CODE_INVALID, "A charged weapon needs charge_ticks above zero.", where
		)

	if charge_requires_min and (min_charge <= 0.0 or min_charge > 1.0):
		return DotResult.fail(
			DotError.CODE_INVALID, "min_charge must be above 0 and at most 1.", where
		)

	if tuning != null:
		var res := tuning.validate()
		if not res.ok:
			return res.wrap("The tuning on %s is not valid." % where)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": name_or_id(),
		"slot": slot,
		"fire_mode": Fire.keys()[fire_mode],
		"behaviour": behaviour_path,
		"ammo": String(ammo_type),
		"magazine": magazine,
		"reserve": reserve,
		"tags": tags.map(func(t: StringName) -> String: return String(t)),
	}


func _to_string() -> String:
	return "DotWeaponDef(%s, slot %d, %s)" % [
		String(id), slot, Fire.keys()[fire_mode]
	]
