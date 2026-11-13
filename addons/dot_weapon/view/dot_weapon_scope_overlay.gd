@tool
extends Control

## What a player sees through a scope: the world through a circle, black around it, and a
## reticle. Draws itself, so it ships no texture and a game restyles it from these exports.
##
## [b]A Control a game places, not something the view model adds.[/b] The view model is a
## 3D node under the camera and knows nothing about the HUD's canvas layer, its scaling or
## what else is drawn over the world. The game puts one of these in its HUD, full-rect, and
## sets [member fraction] each frame from the view model's `aim_fraction()` whenever
## it `is_scoped()` — or from its own rule.

## How visible, 0 to 1 (this and the other drawn setters redraw only on a change: [method follow] sets them every frame). Faded rather than switched so the cut from the weapon to the scope
## is not a flash of black.
@export_range(0.0, 1.0, 0.01) var fraction: float = 0.0:
	set(value):
		var next: float = clampf(value, 0.0, 1.0)
		if next != fraction:
			fraction = next
			queue_redraw()

## The circle's diameter as a fraction of the screen's shorter side.
@export_range(0.2, 1.0, 0.01) var circle: float = 0.9

## The lens's size as a share of [member circle] while the scope comes up: it grows toward 1.
@export_range(0.05, 1.0, 0.01) var lens_scale: float = 1.0:
	set(value):
		var next: float = clampf(value, 0.05, 1.0)
		if next != lens_scale:
			lens_scale = next
			queue_redraw()

@export var surround_colour: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var reticle_colour: Color = Color(0.0, 0.0, 0.0, 0.9)
## A faint green cast over the glass; alpha 0 for clear glass.
@export var glass_tint: Color = Color(0.45, 0.85, 0.55, 0.06)
## The dark metal ring round the lens.
@export var rim_colour: Color = Color(0.03, 0.03, 0.035, 1.0)

## Reticle line width in pixels at a 1080-pixel-tall screen; scaled with the screen.
@export_range(0.5, 8.0, 0.5) var reticle_width: float = 1.5

## A soft dark edge inside the circle, as a fraction of its radius. 0 for a hard edge.
@export_range(0.0, 0.5, 0.01) var vignette: float = 0.16

## The rim's thickness as a fraction of the radius.
@export_range(0.0, 0.2, 0.005) var rim_width: float = 0.035

## Fine mil-style tick marks along the thin part of the crosshair.
@export var mil_ticks: bool = true

## How far the reticle drifts with the breath, as a fraction of the radius. 0 holds it still.
@export_range(0.0, 0.05, 0.001) var breath_sway: float = 0.012

## Colour fringing at the lens edge, in pixels at 1080 tall. 0 for none.
@export_range(0.0, 6.0, 0.25) var fringe: float = 1.5

## 1: the scope is a lens drawn at the middle of a normal screen, the world inside it enlarged by a second camera (see [method bind_camera]).
## 2: the scope fills the screen: the lens is the main camera's own zoomed view and everything outside the circle is black.
@export_range(1, 2, 1) var mode: int = 1:
	set(value):
		var next: int = clampi(value, 1, 2)
		if next != mode:
			mode = next
			queue_redraw()

## Mode 1: the lens's diameter as a fraction of the screen's shorter side.
@export_range(0.15, 0.9, 0.01) var lens_circle: float = 0.46

## How much of the picture is clear (0 solid, 1 not drawn), for a scope looked through on the move; [method follow] sets it.
@export_range(0.0, 1.0, 0.01) var clear: float = 0.0:
	set(value):
		var next: float = clampf(value, 0.0, 1.0)
		if next != clear:
			clear = next
			queue_redraw()

## Mode 1: the lens picture's side in pixels at most; it is also scaled down to the lens's size on screen.
@export_range(64, 2048, 1) var lens_pixels: int = 768

## Mode 1: how much the lens's field of view is of the camera's: 0.25 is a 4x zoom.
var lens_zoom: float = 1.0

var _breath: float = 0.0
var _source: Camera3D = null
var _hide_mask: int = 0
var _port: SubViewport = null
var _cam: Camera3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors AND offsets: `set_anchors_preset` alone keeps the zero offsets a new Control
	# has, so it fills nothing and the scope never draws (the first render had none).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Gives the lens (mode 1) the camera it looks through the same way as, and the render layers to leave out of its picture
## (the view model's, so the gun is not drawn into its own scope).
func bind_camera(camera: Camera3D, hide_layers: int = 0) -> void:
	_source = camera
	_hide_mask = hide_layers


## Whether the lens renders at all: not headless, a mode-1 scope that is showing, a camera to follow.
func lens_active() -> bool:
	return mode == 1 and fraction > 0.0 and clear < 1.0 and is_instance_valid(_source) \
		and DisplayServer.get_name() != "headless"


func _process(delta: float) -> void:
	_sync_lens()
	if fraction <= 0.0:
		return
	_breath += delta
	if breath_sway > 0.0:
		queue_redraw()


func _sync_lens() -> void:
	if not lens_active():
		if _port != null:
			_port.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _port == null:
		_port = SubViewport.new()
		_port.name = "Lens"
		_port.msaa_3d = Viewport.MSAA_DISABLED
		_port.transparent_bg = false
		_port.handle_input_locally = false
		_port.audio_listener_enable_3d = false
		_cam = Camera3D.new()
		_cam.name = "LensCamera"
		_port.add_child(_cam)
		add_child(_port)
	var side := clampi(int(minf(size.x, size.y) * lens_circle * fraction), 64, lens_pixels)
	if _port.size != Vector2i(side, side):
		_port.size = Vector2i(side, side)
	_port.world_3d = _source.get_world_3d()
	_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam.environment = _source.environment
	_cam.attributes = _source.attributes
	_cam.cull_mask = _source.cull_mask & ~_hide_mask
	_cam.near = _source.near
	_cam.far = _source.far
	_cam.fov = _source.fov * lens_zoom
	_cam.global_transform = _source.global_transform
	_cam.current = true


func _draw() -> void:
	if fraction <= 0.0 or clear >= 1.0:
		return
	if mode == 1:
		_draw_lens()
		return

	var size_px := size
	var centre := size_px * 0.5
	var radius := minf(size_px.x, size_px.y) * circle * 0.5 * lens_scale
	var surround := Color(surround_colour, surround_colour.a * fraction * (1.0 - clear))
	var unit := size_px.y / 1080.0

	# The surround as four rectangles and a ring of quads around the circle: Godot has no
	# "draw everything but a circle", and a polygon with a hole is not one call either.
	draw_rect(Rect2(0.0, 0.0, centre.x - radius, size_px.y), surround)
	draw_rect(Rect2(centre.x + radius, 0.0, size_px.x - centre.x - radius, size_px.y), surround)
	draw_rect(Rect2(centre.x - radius, 0.0, radius * 2.0, centre.y - radius), surround)
	draw_rect(Rect2(centre.x - radius, centre.y + radius, radius * 2.0, size_px.y - centre.y - radius), surround)
	_draw_corners(centre, radius, surround)

	if glass_tint.a > 0.0:
		draw_circle(centre, radius, Color(glass_tint, glass_tint.a * fraction), true, -1.0, true)

	if vignette > 0.0:
		_draw_edge_shadow(centre, radius, fraction)

	_draw_rim(centre, radius, unit)
	_draw_reticle(centre, radius, unit)


## Mode 1: the world through a lens in the middle of the screen, rim and reticle on it, nothing else darkened.
func _draw_lens() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * lens_circle * 0.5 * lens_scale
	var unit := size.y / 1080.0
	var alpha := fraction * (1.0 - clear)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var steps := 72
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		var dir := Vector2(cos(a), sin(a))
		points.append(centre + dir * radius)
		uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
	if _port != null and lens_active():
		draw_colored_polygon(points, Color(1.0, 1.0, 1.0, alpha), uvs, _port.get_texture())
	else:
		draw_colored_polygon(points, Color(0.02, 0.03, 0.03, 0.55 * alpha))
	if glass_tint.a > 0.0:
		draw_circle(centre, radius, Color(glass_tint, glass_tint.a * alpha), true, -1.0, true)
	if vignette > 0.0:
		_draw_edge_shadow(centre, radius, alpha)
	_draw_rim(centre, radius, unit)
	_draw_reticle(centre, radius, unit)


## Dark falloff just inside the rim: stacked thin arcs, darkest at the edge.
func _draw_edge_shadow(centre: Vector2, radius: float, strength: float) -> void:
	var steps := 16
	var band := radius * vignette / float(steps)
	for i in range(steps):
		var t := float(i) / float(steps)
		var inner := radius * (1.0 - vignette) + band * (float(i) + 0.5)
		var alpha := 0.55 * t * t * strength
		draw_arc(centre, inner, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, alpha), band + 1.0, true)


## The metal ring, a thin lit line inside it and a red and blue fringe either side of the edge.
## The picture's opacity: faded in with the aim, out with the clear.
func _shown() -> float:
	return fraction * (1.0 - clear)


func _draw_rim(centre: Vector2, radius: float, unit: float) -> void:
	var rim := Color(rim_colour, rim_colour.a * _shown())
	var thick := maxf(2.0, radius * rim_width)
	draw_arc(centre, radius - thick * 0.5, 0.0, TAU, 128, rim, thick, true)
	draw_arc(centre, radius - thick - 1.0, 0.0, TAU, 128, Color(0.55, 0.6, 0.65, 0.18 * _shown()), maxf(1.0, unit), true)
	if fringe > 0.0:
		var shift := fringe * unit
		draw_arc(centre, radius - thick - shift, 0.0, TAU, 128, Color(1.0, 0.25, 0.2, 0.16 * _shown()), maxf(1.0, unit * 1.5), true)
		draw_arc(centre, radius - thick - 2.0 * shift, 0.0, TAU, 128, Color(0.2, 0.4, 1.0, 0.14 * _shown()), maxf(1.0, unit * 1.5), true)


## A duplex reticle: thin lines through the centre, heavy posts on the outer half left, right and
## below, a mil scale on the thin part. Override to draw another.
func _draw_reticle(centre: Vector2, radius: float, unit: float) -> void:
	var sway := Vector2(sin(_breath * 1.3), sin(_breath * 0.8 + 1.0) * 0.8 + sin(_breath * 2.9) * 0.15)
	var c := centre + sway * radius * breath_sway
	var reach := radius - maxf(2.0, radius * rim_width)
	var thin := maxf(1.0, reticle_width * unit)
	var line := Color(reticle_colour, reticle_colour.a * _shown())
	var post_from := reach * 0.38

	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var stop: float = reach * 0.38 if direction != Vector2.UP else reach
		draw_line(c + direction * 2.0 * unit, c + direction * stop, line, thin, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(c + direction * post_from, c + direction * reach, line, thin * 4.0)

	if mil_ticks:
		var step := reach * 0.045
		for i in range(1, 8):
			var long := i % 2 == 0
			var half := (reach * 0.018 if long else reach * 0.011)
			for sign_x in [-1.0, 1.0]:
				var along: float = step * float(i) * sign_x
				draw_line(c + Vector2(along, -half), c + Vector2(along, half), line, thin, true)
			var down: float = step * float(i)
			draw_line(c + Vector2(-half, down), c + Vector2(half, down), line, thin, true)
			draw_line(c + Vector2(-half, -down), c + Vector2(half, -down), line, thin, true)
	draw_circle(c, maxf(1.0, thin * 0.8), line)


## The black between the circle and its bounding square, as a fan per corner.
func _draw_corners(centre: Vector2, radius: float, colour: Color) -> void:
	var segments := 24

	for corner in range(4):
		var start := float(corner) * PI * 0.5
		var square := centre + Vector2(cos(start + PI * 0.25), sin(start + PI * 0.25)) * radius * sqrt(2.0)
		var points := PackedVector2Array([square])

		for i in range(segments + 1):
			var a := start + PI * 0.5 * float(i) / float(segments)
			points.append(centre + Vector2(cos(a), sin(a)) * radius)

		draw_colored_polygon(points, colour)


## Takes the scope's look from [param view] for this frame: nothing for a weapon without a scope.
## The view model is duck-typed: one without a `scope_mode` or `scope_clear()` (an older
## ZeeViewModel) keeps the lens look and no walk-clear.
func follow(view: Object) -> void:
	fraction = view.scope_fraction()
	lens_scale = view.scope_lens_scale()
	mode = view.scope_mode if "scope_mode" in view else mode
	clear = view.scope_clear() if view.has_method(&"scope_clear") else 0.0
	lens_zoom = view.aim_fov_scale()
	var style: Dictionary = view.scope_style()
	for key: Variant in style:
		if key is String and key in self:
			set(key, style[key])


func describe() -> Dictionary:
	return {"fraction": fraction, "circle": circle, "lens_scale": lens_scale, "mode": mode, "clear": clear}
