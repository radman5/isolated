extends Node3D
# PROTOTYPE (style test, #14). Throwaway. One forest clearing patch of Route 1 and
# one armoured character, so the painterly stack (#12) can be judged under the
# follow cam and in a fixed shot, and measured in the web build.
#
# Everything is built in code: this is a look test, not a level, and no gameplay
# code is touched. The KayKit Knight stands in until the generated character from
# "Generate the style-test character" (#20) exists — swap CHARACTER for it and
# nothing else changes.
#
# Keys
#   1  painted ramp lighting      2  character outlines     3  grain + wobble
#   4  Kuwahara                   5  palette grade          C  follow cam / fixed shot
#   N  averaged normals on the outline (shows the split-normal cracks)
#   F  print the frame rate       R  restart

const CHARACTER := "res://assets/kaykit/characters/Knight.glb"
const NATURE := "res://assets/kenney_nature/models/%s.glb"
const RAMP_SHADER := preload("res://shaders/painted_ramp.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const POST_SHADER := preload("res://shaders/post_painterly.gdshader")

# The clearing: trees ring it, the dead giant tree and the waystone are the
# landmarks from the Route 1 decision (#8), and one mud patch sits in the middle.
const TREES := ["tree_default", "tree_tall", "tree_thin", "tree_oak", "tree_pineDefaultA"]
const SCATTER := ["plant_bush", "plant_bushLarge", "grass", "grass_large", "grass_leafs",
	"mushroom_redGroup", "log", "rock_smallA"]
const CLEARING_RADIUS := 7.0
const PATCH := 17.0

var _character: Node3D
var _anim: AnimationPlayer
var _cam_follow: Camera3D
var _cam_fixed: Camera3D
var _post: MeshInstance3D
var _env: Environment
var _ramp_mat := ShaderMaterial.new()
var _outline_mat := ShaderMaterial.new()
var _post_mat := ShaderMaterial.new()
var _hud: Label

var _lit := true
var _outlined := true
var _grain := true
var _kuwahara := true
var _graded := true
var _custom_normals := false
var _fixed_shot := false
var _t := 0.0
var _painted: Array[MeshInstance3D] = []
var _ground_mat: ShaderMaterial
var _mud_mat: ShaderMaterial


func _ready() -> void:
	randomize()
	_build_environment()
	_build_ground()
	_build_clearing()
	_build_character()
	_build_cameras()
	_build_post()
	_build_hud()
	_apply_toggles()
	_run_shots()


# --- world -------------------------------------------------------------------

func _build_environment() -> void:
	# Warm, bright ambient so shadows stay readable from above, and a muted grade.
	# The arena's cool grey ambient is the opposite of this earth palette.
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.36, 0.38, 0.31)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.42, 0.40, 0.36)
	_env.ambient_light_energy = 0.35
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.44, 0.46, 0.40)
	_env.fog_density = 0.02
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.72)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(PATCH * 2.0, PATCH * 2.0)
	ground.mesh = plane
	_ground_mat = _make_painted(Color(0.33, 0.40, 0.24))
	ground.material_override = _ground_mat
	add_child(ground)

	# One mud patch: Route 1's only trap, and a flat colour the Kuwahara can chew on.
	var mud := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.4
	disc.bottom_radius = 3.6
	disc.height = 0.06
	mud.mesh = disc
	mud.position = Vector3(2.6, 0.03, 1.4)
	_mud_mat = _make_painted(Color(0.27, 0.21, 0.15))
	mud.material_override = _mud_mat
	add_child(mud)


func _build_clearing() -> void:
	# A ring of trees around open ground, thickening outward, so the clearing reads
	# as a gap in the forest rather than a field with props on it.
	for i in 46:
		var ang := randf() * TAU
		var dist := CLEARING_RADIUS + randf() * (PATCH - CLEARING_RADIUS)
		_place(TREES[randi() % TREES.size()], Vector3(cos(ang) * dist, 0.0, sin(ang) * dist),
			randf_range(0.9, 1.6))
	for i in 34:
		var ang := randf() * TAU
		var dist := randf() * PATCH
		_place(SCATTER[randi() % SCATTER.size()], Vector3(cos(ang) * dist, 0.0, sin(ang) * dist),
			randf_range(0.8, 1.3))

	# The landmarks: a dead giant tree you navigate by, and the waystone rest point.
	var dead := _place("tree_blocks", Vector3(-7.5, 0.0, -8.0), 3.4)
	if dead:
		dead.rotation.y = 0.7
	_place("rock_largeC", Vector3(5.2, 0.0, -4.8), 1.1)
	var waystone := _place("stump_oldTall", Vector3(-3.4, 0.0, 3.2), 1.4)
	if waystone:
		waystone.rotation.y = -0.4


func _place(model: String, pos: Vector3, scale_factor: float) -> Node3D:
	var path := NATURE % model
	if not ResourceLoader.exists(path):
		return null
	var node: Node3D = load(path).instantiate()
	node.position = pos
	node.scale = Vector3.ONE * scale_factor
	node.rotation.y = randf() * TAU
	add_child(node)
	_paint_branch(node)
	return node


# Every world mesh gets the painted ramp material, keeping the imported texture as
# its albedo. Outlines are characters only (the research is explicit: inking the
# whole world is a different game).
func _paint_branch(node: Node) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if not mi.mesh:
			continue
		# Per surface, not per mesh: the Kenney models carry their colour as a plain
		# albedo_color on each of several surfaces (leaves and trunk), with no
		# texture at all, while KayKit characters are one surface with an atlas.
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var tint := _palette(src)
			var tex: Texture2D = src.albedo_texture if src else null
			mi.set_surface_override_material(s, _make_painted(tint, tex))
		_painted.append(mi)


# Kenney's kit is bright and minty; the brief is a muted earth palette. Until the
# painted textures exist, remap the pack's material names onto stand-in colours so
# the style test judges our palette, not Kenney's.
const PALETTE := {
	"leafsGreen": Color(0.33, 0.42, 0.26),
	"leafsDark": Color(0.25, 0.33, 0.22),
	"grass": Color(0.38, 0.44, 0.27),
	"woodBarkDark": Color(0.30, 0.24, 0.19),
	"woodBark": Color(0.36, 0.29, 0.22),
	"woodInner": Color(0.52, 0.43, 0.32),
	"dirtDark": Color(0.30, 0.24, 0.18),
	"dirt": Color(0.38, 0.31, 0.23),
	"colorRed": Color(0.52, 0.24, 0.20),
	"water": Color(0.36, 0.42, 0.44),
}


static func _palette(src: BaseMaterial3D) -> Color:
	if not src:
		return Color.WHITE
	for key in PALETTE:
		if src.resource_name == key:
			return PALETTE[key]
	return src.albedo_color


func _make_painted(tint: Color, tex: Texture2D = null) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RAMP_SHADER
	mat.set_shader_parameter("ramp", _ramp_texture())
	# The tint uniform carries a source_color hint, so Godot does the sRGB to
	# linear conversion on the way in. Converting here as well would double it.
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("albedo_tex", tex if tex else _white_texture())
	return mat


static var _ramp_cache: GradientTexture1D
static var _white_cache: ImageTexture


# The artist ramp: warm mid-shadow to a slightly desaturated lit colour. This one
# gradient is where most of the "painted" read comes from.
static func _ramp_texture() -> GradientTexture1D:
	if _ramp_cache:
		return _ramp_cache
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0.24, 0.20, 0.23),
		Color(0.44, 0.38, 0.34),
		Color(0.78, 0.72, 0.60),
		Color(0.95, 0.90, 0.78),
	])
	_ramp_cache = GradientTexture1D.new()
	_ramp_cache.gradient = g
	_ramp_cache.width = 64
	return _ramp_cache


static func _white_texture() -> ImageTexture:
	if _white_cache:
		return _white_cache
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	_white_cache = ImageTexture.create_from_image(img)
	return _white_cache


# --- character ---------------------------------------------------------------

func _build_character() -> void:
	_character = load(CHARACTER).instantiate()
	_character.scale = Vector3.ONE * 0.9
	add_child(_character)
	_paint_branch(_character)

	var lib_scene: Node = load("res://assets/kaykit/animations/Rig_Medium_MovementBasic.glb").instantiate()
	var src: AnimationPlayer = lib_scene.find_children("*", "AnimationPlayer", true, false)[0]
	var lib: AnimationLibrary = src.get_animation_library(&"").duplicate(true)
	lib_scene.free()
	for name in lib.get_animation_list():
		if String(name).begins_with("Walking") or String(name).begins_with("Idle"):
			lib.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	_anim = AnimationPlayer.new()
	_character.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library(&"move", lib)
	for candidate in ["move/Walking_A", "move/Walking_B", "move/Idle"]:
		if _anim.has_animation(candidate):
			_anim.play(candidate)
			break

	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("width", 1.8)
	_outline_mat.set_shader_parameter("line_color", Color(0.16, 0.10, 0.07))
	_outline_mat.set_shader_parameter("use_custom_normal", false)
	for mesh in _character.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _outline_mat


# --- cameras and post --------------------------------------------------------

func _build_cameras() -> void:
	# Follow cam at the game's own angle (follow_camera.gd: 12.5 m, 50 degrees).
	_cam_follow = Camera3D.new()
	_cam_follow.current = true
	add_child(_cam_follow)

	# The fixed shot: lower and wider, the kind of hand-placed angle decided for
	# set-piece spaces in the camera ticket (#4).
	_cam_fixed = Camera3D.new()
	_cam_fixed.position = Vector3(11.0, 5.4, 11.5)
	_cam_fixed.look_at_from_position(_cam_fixed.position, Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_cam_fixed.fov = 52.0
	add_child(_cam_fixed)


func _build_post() -> void:
	# Full-screen spatial quad: runs at scaling_3d_scale, unlike a canvas ColorRect.
	_post_mat.shader = POST_SHADER
	_post = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	_post.mesh = quad
	_post.material_override = _post_mat
	_post.extra_cull_margin = 16384.0
	_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_post)
	get_viewport().scaling_3d_scale = 0.6


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 10)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	_hud.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)


# --- driving -----------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	# A slow lap of the clearing, so the look is judged in motion: Kuwahara
	# shimmer and outline crawl only show while moving.
	var r := 5.0
	var pos := Vector3(cos(_t * 0.28) * r, 0.0, sin(_t * 0.28) * r)
	var next := Vector3(cos((_t + 0.1) * 0.28) * r, 0.0, sin((_t + 0.1) * 0.28) * r)
	_character.position = pos
	_character.look_at(next, Vector3.UP)
	_character.rotate_y(PI)  # KayKit faces +Z, this game's forward is -Z

	var target := pos + Vector3(0.0, 1.0, 0.0)
	var pitch := deg_to_rad(50.0)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * 12.5
	_cam_follow.position = target + offset
	_cam_follow.look_at(target, Vector3.UP)

	_hud.text = "%d fps | 1 ramp:%s  2 outline:%s  3 grain:%s  4 kuwahara:%s  5 grade:%s  N normals:%s  C %s" % [
		Engine.get_frames_per_second(), _on(_lit), _on(_outlined), _on(_grain),
		_on(_kuwahara), _on(_graded), _on(_custom_normals),
		"fixed" if _fixed_shot else "follow"]


static func _on(v: bool) -> String:
	return "on" if v else "off"


# --shots <dir>: walk the layer combinations, save a PNG of each, and quit. This is
# how the ticket gets its before/after images without anyone sitting at the keyboard.
const SHOT_PLAN := [
	["flat", false, false, false, false, false],
	["ramp", true, false, false, false, true],
	["ramp_outline", true, true, false, false, true],
	["ramp_outline_grain", true, true, true, false, true],
	["full", true, true, true, true, true],
	["full_fixedshot", true, true, true, true, true],
]
var _shot_dir := ""


# One pass over the plan, awaiting a drawn frame before each grab: get_image()
# on an unfocused window blocks forever without it.
func _run_shots() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	_shot_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# The DemoMenu autoload opens over every demo and pauses the tree, so nothing
	# moves and the shot is of a frozen scene behind a menu.
	var menu := get_node_or_null("/root/DemoMenu")
	if menu:
		menu.visible = false
	get_tree().paused = false
	for i in SHOT_PLAN.size():
		_use_shot(i)
		for f in 30:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_shot_dir, SHOT_PLAN[i][0]])
		print("shot %s at %d fps" % [SHOT_PLAN[i][0], Engine.get_frames_per_second()])
	get_tree().quit()


func _use_shot(i: int) -> void:
	var plan: Array = SHOT_PLAN[i]
	_lit = plan[1]
	_outlined = plan[2]
	_grain = plan[3]
	_kuwahara = plan[4]
	_graded = plan[5]
	_fixed_shot = String(plan[0]).ends_with("fixedshot")
	(_cam_fixed if _fixed_shot else _cam_follow).current = true
	_apply_toggles()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_1: _lit = not _lit
		KEY_2: _outlined = not _outlined
		KEY_3: _grain = not _grain
		KEY_4: _kuwahara = not _kuwahara
		KEY_5: _graded = not _graded
		KEY_N: _custom_normals = not _custom_normals
		KEY_C:
			_fixed_shot = not _fixed_shot
			(_cam_fixed if _fixed_shot else _cam_follow).current = true
		KEY_F: print("fps %d, scale %.2f" % [Engine.get_frames_per_second(), get_viewport().scaling_3d_scale])
		KEY_R: get_tree().reload_current_scene()
		_: return
	_apply_toggles()


func _apply_toggles() -> void:
	for mi in _painted:
		if not is_instance_valid(mi):
			continue
		for s in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m:
				m.set_shader_parameter("ramp_strength", 1.0 if _lit else 0.0)
	for m in [_ground_mat, _mud_mat]:
		if m:
			m.set_shader_parameter("ramp_strength", 1.0 if _lit else 0.0)
	for mesh in _character.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _outline_mat if _outlined else null
	_outline_mat.set_shader_parameter("use_custom_normal", _custom_normals)
	_post_mat.set_shader_parameter("kuwahara_radius", 2 if _kuwahara else 0)
	_post_mat.set_shader_parameter("grain_amount", 0.12 if _grain else 0.0)
	_post_mat.set_shader_parameter("wobble_px", 1.2 if _grain else 0.0)
	_env.adjustment_enabled = _graded
	_env.adjustment_saturation = 0.72
	_env.adjustment_contrast = 1.12
