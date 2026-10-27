class_name DotWeaponTracers
extends MeshInstance3D

## Draws bullet tracers from [signal DotWeaponBullets.tracer] as camera-facing ribbons in one mesh,
## rebuilt each frame (no node per tracer; fine for the browser). Clients only: hits stay server authority.

var width: float = 0.05
var life: float = 0.12
var color: Color = Color(1.0, 0.85, 0.45)
## Most segments kept; older ones drop first.
var max_segments: int = 256

var _segments: Array = []
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = m


## Connect to a [DotWeaponBullets].
func follow(bullets: DotWeaponBullets) -> void:
	bullets.tracer.connect(add)


## One tracer segment from [param from] to [param to].
func add(_id: int, from: Vector3, to: Vector3) -> void:
	_segments.append([from, to, life])
	if _segments.size() > max_segments:
		_segments.pop_front()


func count() -> int:
	return _segments.size()


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	var i := _segments.size() - 1
	while i >= 0:
		_segments[i][2] -= delta
		if _segments[i][2] <= 0.0:
			_segments.remove_at(i)
		i -= 1
	if _segments.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3.ZERO
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg: Array in _segments:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var side := (b - a).cross(eye - (a + b) * 0.5)
		if side.length_squared() < 0.000001:
			continue
		side = side.normalized() * width * 0.5
		var fade := clampf(float(seg[2]) / life, 0.0, 1.0)
		_mesh.surface_set_color(Color(color.r, color.g, color.b, fade))
		_mesh.surface_add_vertex(a - side)
		_mesh.surface_add_vertex(a + side)
		_mesh.surface_add_vertex(b + side)
		_mesh.surface_add_vertex(a - side)
		_mesh.surface_add_vertex(b + side)
		_mesh.surface_add_vertex(b - side)
	_mesh.surface_end()
