class_name DotWeaponSpreadRules
extends RefCounted

## Movement-dependent accuracy as replicated `sv_spread_*` cvars; multiplies a gun's own spread, so its numbers stay
## the base. Off by default. Server shot and client crosshair ask [method target_factor] of the same context.
## Wire with `bind_cvars` / `follow_cvars`, then `arsenal.spread_rules = rules` on both sides.

signal changed

## property: [default, min, max, description]
const FIELDS := {
	&"enabled": [0.0, 0.0, 1.0, "1 turns on movement-dependent weapon spread"],
	&"scale": [1.0, 0.0, 10.0, "Master multiplier on every weapon's spread, on or off (0 fires dead straight)"],
	&"mult_hip": [1.0, 0.0, 10.0, "Spread multiplier when not aiming down sights"],
	&"mult_aim": [0.5, 0.0, 10.0, "Spread multiplier while aiming down sights"],
	&"mult_stand": [1.0, 0.0, 10.0, "Spread multiplier standing still"],
	&"mult_walk": [1.15, 0.0, 10.0, "Spread multiplier walking (slower than sv_spread_run_speed)"],
	&"mult_run": [1.35, 0.0, 10.0, "Spread multiplier running"],
	&"mult_air": [1.5, 0.0, 10.0, "Spread multiplier in the air"],
	&"mult_sprint": [1.8, 0.0, 10.0, "Spread multiplier while sprinting"],
	&"mult_slide": [1.6, 0.0, 10.0, "Spread multiplier while sliding"],
	&"mult_crouch": [0.8, 0.0, 10.0, "Extra spread multiplier while crouched"],
	&"walk_speed": [0.5, 0.0, 50.0, "Speed (m/s) above which the player counts as walking"],
	&"run_speed": [4.5, 0.1, 50.0, "Speed (m/s) above which the player counts as running"],
	&"recovery": [6.0, 0.0, 1000.0, "How fast a widened spread settles, in multiplier units per second (0 settles at once)"],
	&"max_spread": [20.0, 0.0, 90.0, "Largest spread cone half-angle in degrees (0 is no cap)"],
}

## Counts edits to the fields below, however made (a cvar, a test, a direct set), so a holder of a copy of them
## (GameSpice Sim's native spread tick, see [DotWeaponHitscan]) refreshes it on a change without comparing every field. One
## element, not an int, so a walk over the numeric fields never sees it as a rule.
var revision := PackedInt64Array([0])

var enabled: bool = false:
	set(value):
		enabled = value
		revision[0] += 1
var scale: float = 1.0:
	set(value):
		scale = value
		revision[0] += 1
var mult_hip: float = 1.0:
	set(value):
		mult_hip = value
		revision[0] += 1
var mult_aim: float = 0.5:
	set(value):
		mult_aim = value
		revision[0] += 1
var mult_stand: float = 1.0:
	set(value):
		mult_stand = value
		revision[0] += 1
var mult_walk: float = 1.15:
	set(value):
		mult_walk = value
		revision[0] += 1
var mult_run: float = 1.35:
	set(value):
		mult_run = value
		revision[0] += 1
var mult_air: float = 1.5:
	set(value):
		mult_air = value
		revision[0] += 1
var mult_sprint: float = 1.8:
	set(value):
		mult_sprint = value
		revision[0] += 1
var mult_slide: float = 1.6:
	set(value):
		mult_slide = value
		revision[0] += 1
var mult_crouch: float = 0.8:
	set(value):
		mult_crouch = value
		revision[0] += 1
var walk_speed: float = 0.5:
	set(value):
		walk_speed = value
		revision[0] += 1
var run_speed: float = 4.5:
	set(value):
		run_speed = value
		revision[0] += 1
var recovery: float = 6.0:
	set(value):
		recovery = value
		revision[0] += 1
var max_spread: float = 20.0:
	set(value):
		max_spread = value
		revision[0] += 1


## The multiplier this context asks for right now, before recovery smooths it.
func target_factor(ctx: DotWeaponContext) -> float:
	if not enabled or ctx == null:
		return 1.0
	var f := mult_air if ctx.airborne else mult_stand
	if ctx.sliding:
		f = mult_slide
	elif ctx.sprinting and not ctx.airborne:
		f = mult_sprint
	elif not ctx.airborne:
		if ctx.speed >= run_speed:
			f = mult_run
		elif ctx.speed >= walk_speed:
			f = mult_walk
	if ctx.crouched:
		f *= mult_crouch
	return f * (mult_aim if ctx.aiming else mult_hip)


## One tick of settling at [param tick_rate]: how far a widened factor may fall.
func recovery_per_tick(tick_rate: int) -> float:
	return recovery / float(maxi(tick_rate, 1)) if recovery > 0.0 else 1000.0


## [param base] degrees under [param factor], capped.
func apply(base: float, factor: float) -> float:
	var out := base * factor
	return minf(out, max_spread) if max_spread > 0.0 else out


func cvar_name(property: StringName) -> String:
	return "sv_spread_" + String(property) if property != &"enabled" else "sv_spread"


func set_cvar(cvar: String, value: String) -> bool:
	var text := value.strip_edges()
	if not text.is_valid_float():
		return false
	for property: StringName in FIELDS:
		if cvar_name(property) != cvar:
			continue
		var spec: Array = FIELDS[property]
		var number := clampf(text.to_float(), float(spec[1]), float(spec[2]))
		var old: Variant = get(property)
		var next: Variant = number > 0.5 if property == &"enabled" else number
		if old != next:
			set(property, next)
			changed.emit()
		return true
	return false


func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for property: StringName in FIELDS:
		var spec: Array = FIELDS[property]
		var held: Variant = get(property)
		var shown := ("1" if held else "0") if property == &"enabled" else str(held)
		var cv: Variant = add.call(cvar_name(property), shown, String(spec[3]), flags)
		if not (cv is Object):
			continue
		var obj := cv as Object
		if obj.has_method(&"with_range"):
			obj.call(&"with_range", float(spec[1]), float(spec[2]))
		if obj.has_signal(&"changed"):
			obj.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: set_cvar(cvar_name(property), str(new_value)))
		if obj.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name(property), String(obj.call(&"get_string")))
		made.append(obj)
	return made


## Follows the server's values through a link with `replicated_cvar` / `replicated_cvar_changed`.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for property: StringName in FIELDS:
		var held := String(source.call(&"replicated_cvar", cvar_name(property), ""))
		if held != "":
			var _applied := set_cvar(cvar_name(property), held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)
	return true


func _on_replicated(cvar: String, value: String) -> void:
	var _applied := set_cvar(cvar, value)


func describe() -> Dictionary:
	var out := {}
	for property: StringName in FIELDS:
		out[String(property)] = get(property)
	return out
