class_name DotWeaponBallisticsRules
extends DotWeaponCvarRules

## Global ballistics switch and multipliers as `sv_ballistics*` cvars. Off by default: every weapon then
## stays hitscan whatever its `muzzle_velocity`, so no game changes behaviour until it opts in.
##
## [codeblock]
## rules.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED)  # server
## rules.follow_cvars(link)                                                       # client
## bullets.rules = rules
## [/codeblock]

const FIELD_SPECS := {
	&"enabled": [0.0, 0.0, 1.0, "1 turns on simulated bullets (velocity, drop, drag)"],
	&"velocity": [1.0, 0.1, 10.0, "Multiplier on every weapon's muzzle velocity"],
	&"drop": [1.0, 0.0, 10.0, "Multiplier on bullet drop"],
	&"drag": [1.0, 0.0, 10.0, "Multiplier on drag"],
	&"reach": [1.0, 0.1, 10.0, "Multiplier on every weapon's max range"],
	&"max_bullets": [512.0, 1.0, 4096.0, "Most bullets in flight at once"],
}

var enabled: bool = false
var velocity: float = 1.0
var drop: float = 1.0
var drag: float = 1.0
var reach: float = 1.0
var max_bullets: float = 512.0


func fields() -> Dictionary:
	return FIELD_SPECS


func prefix() -> String:
	return "sv_ballistics"


## True when [param b] flies as a simulated bullet under these rules (null rules = off).
static func simulates(rules: DotWeaponBallisticsRules, b: DotWeaponBallistics) -> bool:
	return rules != null and rules.enabled and DotWeaponTrajectory.is_simulated(b)


## A copy of [param b] with the multipliers applied.
func scaled(b: DotWeaponBallistics) -> DotWeaponBallistics:
	var out := b.duplicate() as DotWeaponBallistics
	out.muzzle_velocity *= velocity
	out.bullet_gravity *= drop
	out.drag *= drag
	out.max_range *= reach
	return out
