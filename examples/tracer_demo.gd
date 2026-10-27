extends Node3D

## Fires a burst of simulated bullets across a ground plane and renders one frame:
## `godot --path . res://examples/tracer_demo.tscn -- --shot out.png`. See tools/screenshot.sh.


func _ready() -> void:
	var rules := DotWeaponBallisticsRules.new()
	rules.enabled = true
	var b := DotWeaponBallistics.new()
	b.muzzle_velocity = 300.0
	b.max_range = 150.0
	b.tracer_interval = 1
	var bullets := DotWeaponBullets.new()
	bullets.rules = rules
	add_child(bullets)
	var tracers := DotWeaponTracers.new()
	tracers.life = 5.0
	tracers.width = 0.12
	add_child(tracers)
	tracers.follow(bullets)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-7, 2.0, 5)
	cam.look_at(Vector3(4, 1.0, -30))
	for i in 6:
		var dir := Vector3(-0.1 + i * 0.1, 0.02 + i * 0.015, -1.0)
		var id := bullets.spawn(1 + i, Vector3(0, 1.4, 0), dir, b)
		if id == 0:
			print("spawn refused")
	for t in 25:
		bullets.step(float(t))
	var args := OS.get_cmdline_user_args()
	var path := ""
	if args.has("--shot") and args.find("--shot") + 1 < args.size():
		path = args[args.find("--shot") + 1]
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if path != "":
		get_viewport().get_texture().get_image().save_png(path)
	print("tracers drawn: %d" % tracers.count())
	get_tree().quit()
