extends SceneTree
# Screenshots and frame rates at Route 1's beats, in a real window.
#
#   Godot --path . --script res://tools/route1_shots.gd -- <output dir>
#
# The debug label and overlay are hidden; the hotbar and HP bar stay.

var s: Node
var p: Node
var out := "user://shots"


func _shot(name: String, pos: Vector3) -> void:
	p.global_position = pos
	p.reset_physics_interpolation()
	s.get_node("Camera3D")._focus = pos
	for i in 20:
		await process_frame
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_frames_drawn()
	while Time.get_ticks_msec() - t0 < 1000:
		await process_frame
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("%-16s fps %5.1f" % [name, fps])


func _flat(n: String, off := Vector3.ZERO) -> Vector3:
	var q: Vector3 = s.get_node(n).global_position + off
	return Vector3(q.x, 1.05, q.z)


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	if not OS.get_cmdline_user_args().is_empty():
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	load("res://player.gd").unlocked.clear()
	change_scene_to_file("res://demos/route1.tscn")
	await process_frame
	await process_frame
	root.get_node("DemoMenu")._show(false)
	s = current_scene
	s.get_node("HUD/Label").visible = false
	s.get_node("DebugDraw").visible = false
	p = s.get_node("Player")
	p.set_physics_process(false)
	var chest: Node3D = s.get_node("Chest")
	var front: Vector3 = chest.global_position - chest.global_transform.basis.z * 1.6
	await _shot("1_glade", p.global_position)
	await _shot("2_chest_closed", Vector3(front.x, 1.05, front.z))
	chest.open()
	p._select("shot")
	await _shot("3_chest_open", Vector3(front.x, 1.05, front.z))
	for n in ["MudBarkling1", "MudBarkling2"]:
		s.get_node(n).wake("shot")
	p.set_physics_process(true)
	await _shot("4_mud", _flat("Mud", Vector3(0, 0, 3)))
	p.set_physics_process(false)
	await _shot("5_nest", s.get_node("Stretch").global_transform * Vector3(0, 1.05, 12))
	await _shot("6_settlement", _flat("Exit"))
	quit()
