extends Node3D
# Trees, undergrowth, grass and rocks along the route, scattered at load from
# route_terrain.gd's layout with a fixed seed, so every load looks the same.
#
# - Forest: a dense band of trees on the banks, just outside the walkable edge.
# - Undergrowth: bushes, ferns and big plants along that edge.
# - Grass and flowers: on the walkable floor, kept off the worn dirt and the mud.
# - Rocks and mushrooms: sparse, near the edges.
#
# One MultiMeshInstance3D per model part per route piece, so each piece culls on
# its own. Nothing here has collision: the walls are the edge, and rootkin sight
# rays see straight through leaves. Materials are swapped for foliage.gdshader
# and handed to occluder_fade.gd.

const FoliageShader := preload("res://shaders/foliage.gdshader")
const Ramp := preload("res://art/painted_ramp.tres")
const DIR := "res://assets/quaternius_nature/models/"

@export var terrain_path := NodePath("../Terrain")
@export var seed := 21
## Spacing of the tree grid, metres. Lower is a denser forest.
@export var tree_spacing := 2.8
@export var forest_depth := 11.0
@export var grass_spacing := 1.15
@export var grass_view_range := 32.0
@export var tree_view_range := 42.0
## Hand-placed landmarks, "model|x|z|scale|yaw_degrees": the dead giant tree,
## the waystone. Drawn like the rest, so they share the look and the fade.
@export var landmarks := PackedStringArray()

# model, weight, scale range, wind. Wind 0 = stays still.
const TREES := [
	["Pine_1", 3, Vector2(0.9, 1.2), 0.012], ["Pine_2", 2, Vector2(0.8, 1.0), 0.012],
	["Pine_3", 3, Vector2(0.9, 1.2), 0.012], ["Pine_4", 2, Vector2(0.8, 1.1), 0.012],
	["Pine_5", 3, Vector2(0.9, 1.2), 0.012],
	["Tree_1", 2, Vector2(0.9, 1.2), 0.015], ["Tree_2", 2, Vector2(0.9, 1.2), 0.015],
	["Tree_3", 2, Vector2(0.9, 1.2), 0.015], ["Tree_4", 1, Vector2(0.9, 1.1), 0.015],
	["Tree_5", 2, Vector2(0.9, 1.2), 0.015],
	["Dead_Tree_2", 1, Vector2(0.5, 0.7), 0.0], ["Dead_Tree_3", 1, Vector2(0.6, 0.8), 0.0],
	["Twisted_Tree_1", 1, Vector2(0.45, 0.6), 0.008],
]
const UNDERGROWTH := [
	["Bush_1", 3, Vector2(0.8, 1.2), 0.03], ["Bush_with_Flowers_1", 1, Vector2(0.8, 1.1), 0.03],
	["Fern_1", 3, Vector2(0.14, 0.2), 0.05], ["Plant_Big_1", 2, Vector2(0.35, 0.5), 0.04],
	["Plant_Big_2", 2, Vector2(0.9, 1.3), 0.02],
]
const GRASS := [
	["Grass_1", 6, Vector2(0.35, 0.55), 0.25], ["Grass_Wispy_2", 2, Vector2(0.35, 0.5), 0.25],
	["Tall_Grass_1", 1, Vector2(0.3, 0.45), 0.25], ["Clover_1", 1, Vector2(0.4, 0.6), 0.1],
	["Flower_Group_2", 1, Vector2(0.25, 0.35), 0.15],
]
const ROCKS := [
	["Rock_Medium_1", 1, Vector2(0.35, 0.7), 0.0], ["Rock_Medium_2", 1, Vector2(0.35, 0.7), 0.0],
	["Rock_Medium_3", 1, Vector2(0.35, 0.7), 0.0], ["Mushroom_1", 1, Vector2(0.6, 0.9), 0.0],
	["Mushroom_Laetiporus_1", 1, Vector2(0.5, 0.8), 0.0],
]

var fade_materials: Array[ShaderMaterial] = []
var _terrain: Node
var _rng := RandomNumberGenerator.new()
var _parts := {}  # model -> [{mesh, xform}] for each mesh part in its scene
var _materials := {}  # "texture|wind|cut" -> ShaderMaterial
# (piece index, model) -> {"model", "xforms": Array[Transform3D], "shadow", "range", "fade"}
var _batches := {}


func _ready() -> void:
	_terrain = get_node(terrain_path)
	_rng.seed = seed
	_scatter()
	for l in landmarks:
		var f := l.split("|")
		var x := float(f[1])
		var z := float(f[2])
		var rot := Basis(Vector3.UP, deg_to_rad(float(f[4]))).scaled(Vector3.ONE * float(f[3]))
		_add("landmark|" + l, f[0], 0.0, "landmark", Transform3D(rot, Vector3(x, _terrain.height_at(x, z), z)))
	_build()


func _piece_of(z: float) -> int:
	var best := 0
	var best_d := INF
	for i in _terrain.pieces.size():
		var p: Vector3 = _terrain.pieces[i]
		var d := maxf(maxf(z - p.x, p.y - z), 0.0)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pick(table: Array) -> Array:
	var total := 0
	for row in table:
		total += row[1]
	var r := _rng.randi_range(1, total)
	for row in table:
		r -= row[1]
		if r <= 0:
			return row
	return table[0]


func _place(table: Array, x: float, z: float, kind: String) -> void:
	var row := _pick(table)
	var s := _rng.randf_range(row[2].x, row[2].y)
	var rot := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
	var xf := Transform3D(rot, Vector3(x, _terrain.height_at(x, z) - 0.05, z))
	_add("%d|%s" % [_piece_of(z), row[0]], row[0], row[3], kind, xf)


func _add(key: String, model: String, wind: float, kind: String, xf: Transform3D) -> void:
	if not _batches.has(key):
		_batches[key] = {"model": model, "wind": wind, "xforms": [], "kind": kind}
	_batches[key].xforms.append(xf)


func _scatter() -> void:
	var t: Node = _terrain
	var zs := -INF
	var zn := INF
	for p in t.pieces:
		zs = maxf(zs, p.x)
		zn = minf(zn, p.y)
	var hw: float = t.grid_half_width - 2
	# Forest band and undergrowth on a jittered grid over the whole valley.
	var z := zs + forest_depth
	while z > zn - forest_depth:
		var x := -hw
		while x < hw:
			var px := x + _rng.randf_range(-0.45, 0.45) * tree_spacing
			var pz := z + _rng.randf_range(-0.45, 0.45) * tree_spacing
			var d: float = t.walk_dist(px, pz)
			if not t.in_ravine(px, pz) and absf(px) < hw:
				# Densest right at the edge, thinning out into the woods.
				if d > 1.4 and d < forest_depth and _rng.randf() < lerpf(1.0, 0.55, d / forest_depth):
					_place(TREES, px, pz, "tree")
				elif d > 0.1 and d < 2.2 and _rng.randf() < 0.6:
					_place(UNDERGROWTH, px, pz, "under")
				elif d > 0.0 and d < 3.0 and _rng.randf() < 0.07:
					_place(ROCKS, px, pz, "rock")
			x += tree_spacing
		z -= tree_spacing
	# Grass on the walkable floor, off the worn dirt and the mud.
	z = zs
	while z > zn:
		var x := -hw
		while x < hw:
			var px := x + _rng.randf_range(-0.5, 0.5) * grass_spacing
			var pz := z + _rng.randf_range(-0.5, 0.5) * grass_spacing
			if t.walk_dist(px, pz) == 0.0:
				var c: Color = t.paint_at(px, pz, 0.0)
				if c.r < 0.25 and c.g < 0.2 and _rng.randf() < 0.75:
					_place(GRASS, px, pz, "grass")
			x += grass_spacing
		z -= grass_spacing


# The mesh parts of a model scene, each with its transform relative to the root.
func _parts_of(model: String) -> Array:
	if _parts.has(model):
		return _parts[model]
	var root: Node3D = load(DIR + model + ".glb").instantiate()
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		out.append({"mesh": _repaint(mi.mesh, model), "xform": _local_to_root(mi, root)})
	root.free()
	_parts[model] = out
	return out


static func _local_to_root(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# A copy of the mesh with every surface on a foliage.gdshader material.
func _repaint(src: Mesh, model: String) -> Mesh:
	var mesh: Mesh = src.duplicate()
	var wind := 0.0
	for table in [TREES, UNDERGROWTH, GRASS, ROCKS]:
		for row in table:
			if row[0] == model:
				wind = row[3]
	for s in mesh.get_surface_count():
		var old := mesh.surface_get_material(s) as BaseMaterial3D
		var tex: Texture2D = old.albedo_texture if old else null
		var cut := 0.5 if old and old.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0.0
		var key := "%s|%s|%s" % [tex.resource_path if tex else "none", wind, cut]
		if not _materials.has(key):
			var m := ShaderMaterial.new()
			m.shader = FoliageShader
			m.set_shader_parameter("albedo_tex", tex)
			m.set_shader_parameter("ramp", Ramp)
			m.set_shader_parameter("alpha_cut", cut)
			m.set_shader_parameter("wind_strength", wind)
			# Leaves a touch muted; bark pulled well down from the pack's bright orange.
			m.set_shader_parameter("tint", Color(0.86, 0.86, 0.78) if cut > 0.0 else Color(0.62, 0.56, 0.52))
			_materials[key] = m
			# Grass stays under the actors' feet; everything taller can fade.
			if wind < 0.1:
				fade_materials.append(m)
		mesh.surface_set_material(s, _materials[key])
	return mesh


func _build() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		for part in _parts_of(b.model):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = b.xforms.size()
			for i in b.xforms.size():
				mm.set_instance_transform(i, b.xforms[i] * part.xform)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			match b.kind:
				"grass":
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mmi.visibility_range_end = grass_view_range
				"tree", "landmark":
					mmi.visibility_range_end = tree_view_range
				_:
					mmi.visibility_range_end = tree_view_range * 0.7
			add_child(mmi)


func counts() -> Dictionary:
	var out := {}
	for key in _batches:
		var b: Dictionary = _batches[key]
		out[b.kind] = out.get(b.kind, 0) + b.xforms.size()
	return out
