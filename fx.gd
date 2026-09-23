extends RefCounted
# Hit feedback: sparks, an enemy flash, a ground ring. Static helpers, no state
# beyond the F2 switch. Everything here only decorates; gameplay never reads it.
#
# CPUParticles3D, not GPU: the web build runs the Compatibility renderer.

## F2 toggles. Off skips shake, sparks, flash, rings, knockback slow-mo and the
## swing freeze, but keeps the chain's original hitstop, so off plays exactly
## like the game before any of this existed.
static var on := true

static var _white: StandardMaterial3D


# A one-shot burst sprayed around `dir`. Frees itself.
static func sparks(tree: SceneTree, at: Vector3, dir: Vector3, col: Color, amount := 14) -> void:
	if not on:
		return
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = col
	quad.material = m
	p.mesh = quad
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.35
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	tree.current_scene.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


# Every mesh under the enemy's Model goes white for `secs` of real time, so the
# flash still shows through a hitstop freeze.
static func flash(enemy: Node, secs := 0.08) -> void:
	if not on:
		return
	if _white == null:
		_white = StandardMaterial3D.new()
		_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_white.albedo_color = Color(1, 1, 1, 0.85)
		_white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var meshes := enemy.find_children("*", "MeshInstance3D", true, false)
	for mi in meshes:
		mi.material_overlay = _white
	var t := enemy.get_tree().create_timer(secs, true, false, true)
	t.timeout.connect(func():
		for mi in meshes:
			if is_instance_valid(mi):
				mi.material_overlay = null
	)


# An expanding, fading ring on the ground: readable from across the arena.
static func ring(tree: SceneTree, at: Vector3, col: Color, size := 2.0) -> void:
	if not on:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.current_scene.add_child(mi)
	mi.global_position = Vector3(at.x, 0.06, at.z)
	mi.scale = Vector3.ONE * 0.4
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)


# Draws every effect once, out of sight under the floor, so their shaders compile
# at load. Otherwise the first hit of a session stalls the frame while they do,
# which is a real hitch, not a styled one, and worst on web.
static func prewarm(tree: SceneTree, at: Vector3) -> void:
	var under := at + Vector3(0, -3, 0)
	var was := on
	on = true
	sparks(tree, under, Vector3.UP, Color.WHITE, 1)
	ring(tree, under, Color.WHITE)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	tree.current_scene.add_child(box)
	box.global_position = under
	flash(box, 0.2)
	tree.create_timer(0.3, true, false, true).timeout.connect(box.queue_free)
	on = was
