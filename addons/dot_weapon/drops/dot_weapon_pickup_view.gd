class_name DotWeaponPickupView
extends Node3D

## The prompt over a dropped weapon: its name, magazine and total ammunition, the key glyph, and a
## circle that fills while the key is held. Draws only; the game feeds it [method DotWeaponDrops.prompt_for].
## Text comes through [member translate] (a [code]Callable(key, fallback) -> String[/code]), so a locale
## addon can supply it without this one naming it.

const CIRCLE_SHADER := """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
uniform float progress = 0.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform vec4 back_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float ring = step(0.62, r) * step(r, 1.0);
	float a = atan(p.x, -p.y) / 6.28318530718;
	a = a < 0.0 ? a + 1.0 : a;
	float on = step(a, progress);
	ALBEDO = mix(back_color.rgb, fill_color.rgb, on);
	ALPHA = ring * mix(back_color.a, 1.0, on);
}
"""

## [code]translate.call(key, fallback) -> String[/code]; unset shows the English fallback.
var translate: Callable = Callable()
## Display name of a weapon id; unset shows the id.
var name_of: Callable = Callable()
## Text for the use key (follows the binding); the game sets it when the binding changes.
var key_text: String = "E"
## Metres above the weapon the panel floats.
var lift: float = 0.45

var _label: Label3D
var _circle: MeshInstance3D
var _material: ShaderMaterial
var _info: Dictionary = {}


func _ready() -> void:
	visible = false
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 36
	_label.outline_size = 10
	_label.render_priority = 10
	_label.outline_render_priority = 9
	add_child(_label)
	var shader := Shader.new()
	shader.code = CIRCLE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.render_priority = 11
	_circle = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_circle.mesh = quad
	_circle.material_override = _material
	_circle.visible = false
	add_child(_circle)


## Shows the prompt for [param info] ([method DotWeaponDrops.prompt_for]); empty hides it.
## [param fill] is the hold circle, 0..1.
func show_prompt(info: Dictionary, fill: float = 0.0) -> void:
	if info.is_empty():
		visible = false
		_info = {}
		return
	visible = true
	global_position = (info["at"] as Vector3) + Vector3.UP * lift
	if _label == null:
		return
	if info != _info:
		_info = info
		_label.text = text_for(info)
	_circle.visible = fill > 0.0
	_circle.position = Vector3(0.0, 0.0, 0.0)
	if fill > 0.0:
		_material.set_shader_parameter("progress", fill)
		_face_camera()


## The panel text: name, ammunition and what the key does.
func text_for(info: Dictionary) -> String:
	var id := StringName(info.get("weapon", &""))
	var shown: String = String(name_of.call(id)) if name_of.is_valid() else String(id).capitalize()
	var mag := int(info.get("magazine", 0))
	var reserve := int(info.get("reserve", 0))
	var action_key := "weapon.pickup.%s" % info.get("mode", "take")
	var fallback: String = {"take": "Take", "ammo": "Take ammo", "swap": "Hold to swap"}.get(info.get("mode", "take"), "Take")
	var action := _t(action_key, fallback)
	if not bool(info.get("can_take", true)):
		action = _t("weapon.pickup.cannot", "Cannot carry")
	return "%s\n%s %d / %d\n[%s] %s" % [shown, _t("weapon.pickup.magazine", "Ammo"), mag, mag + reserve, key_text, action]


func _t(key: String, fallback: String) -> String:
	return String(translate.call(key, fallback)) if translate.is_valid() else fallback


func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	_circle.global_transform = Transform3D(cam.global_transform.basis, global_position + Vector3.DOWN * 0.1)
