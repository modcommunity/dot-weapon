@tool
class_name DotWeaponTuning
extends Resource

## What a behaviour reads, typed and in the inspector.
##
## [b]This exists because [member DotWeaponDef.params] is untyped.[/b] A dictionary is
## the right thing for a weapon delivered inside a content pack, which cannot register a
## `class_name` and so cannot ship a resource of its own. It is the wrong thing for a
## game's own arsenal, where an author wants ranges, groups, enum names and a doc string
## on every field, and wants a typo to be caught when the resource is saved rather than
## when the weapon is first fired.
##
## So both exist and neither is required. A behaviour reads whichever it was given, and
## the convention is that a field present in both wins from [member DotWeaponDef.tuning]
## because it is the more specific of the two.
##
## Subclass it, add `@export`s, and point a behaviour at it:
##
## [codeblock]
## @tool
## class_name MyBowTuning
## extends DotWeaponTuning
##
## @export_range(1.0, 300.0, 1.0) var draw_speed: float = 90.0
##
## func validate() -> DotResult:
##     if draw_speed <= 0.0:
##         return DotResult.fail(DotError.CODE_INVALID, "draw_speed must be positive.")
##     return DotResult.success(null)
## [/codeblock]

## Checked when the catalogue is validated, so a bad number is a boot failure on a
## headless server rather than a weapon that behaves oddly in front of players.
##
## The base accepts anything; override it.
func validate() -> DotResult:
	return DotResult.success(null)


## What a console command or a bug report dumps.
func describe() -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in get_property_list():
		if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var key := String(prop.get("name", ""))
		if key == "":
			continue
		out[key] = get(key)
	return out
