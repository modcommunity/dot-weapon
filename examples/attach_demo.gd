extends Node3D

## Render check: a block rifle wearing the fixture suppressor and 4x scope, with the attach menu open beside it.
## `godot --path . res://examples/attach_demo.tscn -- --shot out.png`; see tools/screenshot.sh.


func _ready() -> void:
	var cat := DotWeaponAttachments.new()
	var root := ProjectSettings.globalize_path("res://fixtures/attachments")
	var loaded := cat.load_set(DotWeaponAttachments.make_set("demo", "g", PackedStringArray([root])))
	var rifle := DotWeaponDef.new()
	rifle.id = &"rifle"
	rifle.display_name = "Rifle"
	rifle.slot = 1
	rifle.tags = [&"rifle"] as Array[StringName]
	rifle.mounts = [&"muzzle", &"optic"] as Array[StringName]
	var fitting := DotWeaponFitting.make(&"rifle")
	fitting.fit(&"muzzle", &"suppressor")
	fitting.fit(&"optic", &"scope_4x")
	var gun := _block_rifle()
	add_child(gun)
	var placed := DotWeaponAttachmentModels.dress(gun, cat, fitting)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.9, 0.35, -0.2)
	cam.look_at(Vector3(0.15, 0.02, -0.25))
	var layer := CanvasLayer.new()
	add_child(layer)
	var menu := DotWeaponAttachMenu.new()
	layer.add_child(menu)
	menu.position = Vector2(24, 24)
	menu.open(cat, rifle, fitting)
	var args := OS.get_cmdline_user_args()
	var path := ""
	if args.has("--shot") and args.find("--shot") + 1 < args.size():
		path = args[args.find("--shot") + 1]
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if path != "":
		get_viewport().get_texture().get_image().save_png(path)
	print("attachments loaded: %s, models placed: %d" % [loaded.value if loaded.ok else loaded.error.message, placed])
	get_tree().quit(0 if loaded.ok and placed == 2 else 1)


## A receiver, stock and barrel from boxes, with a node per mount where attachment models go.
func _block_rifle() -> Node3D:
	var gun := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.25)
	for part: Array in [[Vector3(0.06, 0.08, 0.4), Vector3(0, 0, 0)], [Vector3(0.05, 0.1, 0.25), Vector3(0, -0.02, 0.32)], [Vector3(0.025, 0.025, 0.35), Vector3(0, 0.01, -0.37)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = part[1]
		mesh.material_override = mat
		gun.add_child(mesh)
	for socket: Array in [["muzzle", Vector3(0, 0.01, -0.545)], ["optic", Vector3(0, 0.04, -0.02)]]:
		var node := Node3D.new()
		node.name = DotWeaponAttachmentModels.SOCKET_PREFIX + String(socket[0])
		node.position = socket[1]
		gun.add_child(node)
	return gun
