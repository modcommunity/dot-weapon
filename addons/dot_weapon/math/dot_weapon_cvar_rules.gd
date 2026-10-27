class_name DotWeaponCvarRules
extends RefCounted

## Base for a rules object whose numeric properties are server cvars (`<PREFIX>`, `<PREFIX>_<field>`),
## replicated to clients. A subclass sets [constant FIELDS] and [constant PREFIX] through [method fields]
## and [method prefix] and declares a variable per field.

signal changed

## property: [default, min, max, description]. Override.
func fields() -> Dictionary:
	return {}


## Cvar name prefix, e.g. `sv_ballistics`. Override.
func prefix() -> String:
	return "sv_rules"


func cvar_name(property: StringName) -> String:
	return prefix() if property == &"enabled" else "%s_%s" % [prefix(), property]


func set_cvar(cvar: String, value: String) -> bool:
	var text := value.strip_edges()
	if not text.is_valid_float():
		return false
	var all := fields()
	for property: StringName in all:
		if cvar_name(property) != cvar:
			continue
		var spec: Array = all[property]
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
	var all := fields()
	for property: StringName in all:
		var spec: Array = all[property]
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
	for property: StringName in fields():
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
	for property: StringName in fields():
		out[String(property)] = get(property)
	return out
