class_name DotWeaponDropRules
extends RefCounted

## How dropped weapons behave: whether a death or a key drops one, how long it lies, how many
## may lie on a map, how hard it is thrown. A player class can override any number through
## [method resolve]; [code]sv_weapon_drop*[/code] are the server-wide defaults.

const CHANNEL := "weapon.drop"

## Class-def property names that override a rule (a negative number, or INHERIT, keeps the rule).
const CLASS_KEYS := {
	"drop_allowed": "key_enabled", "drop_on_death": "on_death", "drop_lifetime": "lifetime",
	"drop_throw_force": "throw_force", "drop_throw_up": "throw_up", "drop_pickup_radius": "pickup_radius", "drop_use_radius": "use_radius",
}

signal changed

## A weapon may be dropped (key and death) at all.
var enabled: bool = true
## The dead player's weapon falls where they died.
var on_death: bool = true
## The drop key throws the weapon in hand.
var key_enabled: bool = true
## Seconds a weapon lies before it vanishes; 0 never.
var lifetime: float = 60.0
## Most dropped weapons on the map; the oldest goes first. 0 is unlimited.
var max_count: int = 32
## Metres per second along the aim.
var throw_force: float = 6.0
## Extra upward metres per second, so a throw arcs.
var throw_up: float = 2.0
## How close a player must be to take a weapon whose slot is empty.
var pickup_radius: float = 1.4
## Seconds after a drop before anybody may take it (so a throw is not caught again).
var pickup_delay: float = 0.7
## A weapon in reach with an empty slot is taken without a key (off: the use key takes it).
var auto_pickup: bool = false
## How far the use key reaches to a dropped weapon, metres.
var use_radius: float = 2.2
## The drop key also takes the weapon you are standing at, once your own is out of the slot.
var swap: bool = true

## Players may take weapons off the floor at all (mp_allow_pickup).
var allow_pickup: bool = true
## A weapon may only be taken by a player on the team of whoever dropped it (mp_pickup_team_only); free-for-all is never restricted.
var team_only: bool = false

const _SPECS := [
	["mp_allow_pickup", "allow_pickup", "bool", "1 lets players pick weapons up off the floor; 0 blocks every pickup"],
	["mp_pickup_team_only", "team_only", "bool", "1 lets a player take only a weapon dropped by their own team (no effect without teams); 0 takes any"],
	["sv_weapon_drop", "enabled", "bool", "1 lets weapons be dropped at all"],
	["sv_weapon_drop_death", "on_death", "bool", "1 drops a dead player's weapon"],
	["sv_weapon_drop_key", "key_enabled", "bool", "1 lets the drop key throw the weapon in hand"],
	["sv_weapon_drop_time", "lifetime", "float:0:3600", "Seconds a dropped weapon lies before it vanishes; 0 never"],
	["sv_weapon_drop_max", "max_count", "int:0:512", "Most dropped weapons on the map, oldest removed first; 0 unlimited"],
	["sv_weapon_drop_force", "throw_force", "float:0:40", "Throw speed along the aim"],
	["sv_weapon_drop_up", "throw_up", "float:0:20", "Extra upward throw speed"],
	["sv_weapon_drop_radius", "pickup_radius", "float:0.2:6", "Distance within which an empty slot takes a dropped weapon"],
	["sv_weapon_drop_delay", "pickup_delay", "float:0:10", "Seconds before a dropped weapon can be taken"],
	["sv_weapon_drop_auto", "auto_pickup", "bool", "1 takes a dropped weapon in reach without the use key"],
	["sv_weapon_drop_use_radius", "use_radius", "float:0.2:8", "How far the use key reaches to a dropped weapon"],
	["sv_weapon_drop_swap", "swap", "bool", "1 lets the drop key take the weapon underfoot after dropping"],
]


## A copy of these rules with [param source]'s drop_* properties laid over them; [param source] is
## a player class def (duck-typed, so this addon needs no dependency on it) or null.
func resolve(source: Object) -> DotWeaponDropRules:
	var out := DotWeaponDropRules.new()
	for spec in _SPECS:
		out.set(spec[1], get(spec[1]))
	if source == null:
		return out
	for key: String in CLASS_KEYS:
		var v: Variant = source.get(key)
		var field: String = CLASS_KEYS[key]
		if v == null or (v is bool):
			continue
		if float(v) < 0.0:
			continue
		if typeof(get(field)) == TYPE_BOOL:
			out.set(field, float(v) > 0.0)
		elif typeof(get(field)) == TYPE_INT:
			out.set(field, int(v))
		else:
			out.set(field, float(v))
	return out


func cvar_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in _SPECS:
		var kind: PackedStringArray = String(spec[2]).split(":")
		var value: Variant = get(spec[1])
		var d := {"name": spec[0], "description": spec[3],
			"value": ("1" if value else "0") if kind[0] == "bool" else str(value)}
		if kind.size() == 3:
			d["min"] = kind[1].to_float()
			d["max"] = kind[2].to_float()
		elif kind[0] == "bool":
			d["min"] = 0.0
			d["max"] = 1.0
		out.append(d)
	return out


## Sets one rule from a cvar's text. False when the name is not ours or the text is not a number.
func set_cvar(cvar_name: String, text: String) -> bool:
	for spec in _SPECS:
		if spec[0] != cvar_name:
			continue
		if not text.is_valid_float():
			DotLog.warn(CHANNEL, "cvar value not understood; left as it was", {"cvar": cvar_name, "value": text})
			return false
		var kind: PackedStringArray = String(spec[2]).split(":")
		var n := text.to_float()
		if kind[0] == "bool":
			set(spec[1], n != 0.0)
		elif kind[0] == "int":
			set(spec[1], clampi(int(n), int(kind[1]), int(kind[2])))
		else:
			set(spec[1], clampf(n, kind[1].to_float(), kind[2].to_float()))
		changed.emit()
		return true
	return false


## Registers the cvars through [param add] (a server module's add_cvar, shaped
## [code](name, default, description, flags) -> cvar[/code]) and follows them; pass the
## replicated flag so a client's [method follow] sees them too. Returns the cvars.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cv: Variant = add.call(spec["name"], String(spec["value"]), String(spec["description"]), flags)
		if not (cv is Object) or cv == null:
			continue
		var o := cv as Object
		if spec.has("min") and o.has_method(&"with_range"):
			o.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if o.has_signal(&"changed"):
			o.connect(&"changed", func(_old: String, new_value: String) -> void: var _ok := set_cvar(spec["name"], new_value))
		if o.has_method(&"get_string"):
			var _ok2 := set_cvar(spec["name"], String(o.call(&"get_string")))
		made.append(o)
	return made


## Keeps these rules on a server's values: [param source] is a client link with
## [code]replicated_cvar(name, fallback)[/code] and a [code]replicated_cvar_changed(name, value)[/code]
## signal. False when it cannot follow.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in _SPECS:
		var held := String(source.call(&"replicated_cvar", spec[0], ""))
		if held != "":
			var _applied := set_cvar(spec[0], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	if cvar_name.begins_with("sv_weapon_drop") or cvar_name == "mp_allow_pickup" or cvar_name == "mp_pickup_team_only":
		var _applied := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	var out := {}
	for spec in _SPECS:
		out[spec[1]] = get(spec[1])
	return out
