extends Node3D
# The route's ground, built from the layout at load: flat where you walk, banks
# rising at the edges, and a ravine that drops away. It's one mesh on a 1m grid
# with a matching HeightMapShape3D, and the vertex colours paint it for
# terrain_splat.gdshader: R worn dirt, G mud, B leaf litter.
#
# tools/gen_route1.py writes the layout into these exports. The invisible walls
# stay the hard edge; the banks are how that edge looks.
# ponytail: rebuilt on every load (about 18k vertices, a few milliseconds). Bake
# it into a resource if the route grows much bigger.

const TerrainShader := preload("res://shaders/terrain_splat.gdshader")
const Ramp := preload("res://art/painted_ramp.tres")

## (z_south, z_north, width) for each walkable piece, centred on x = 0.
@export var pieces := PackedVector3Array()
## (z_south, z_north) of the ravine's gap.
@export var ravine := Vector2.ZERO
## (centre_x, centre_z, size_x, size_z) of each mud patch.
@export var mud := PackedVector4Array()
## (x, z, radius) of worn dirt patches, e.g. round the waystone.
@export var dirt_spots := PackedVector3Array()
@export var bank_height := 3.2
@export var bank_width := 4.0
@export var ravine_depth := 10.0
@export var grid_half_width := 36
@export var seed := 7

var _noise := FastNoiseLite.new()
var _z_max := 0.0
var _z_min := 0.0
var material: ShaderMaterial


func _ready() -> void:
	_noise.seed = seed
	_noise.frequency = 0.045
	for p in pieces:
		_z_max = maxf(_z_max, p.x)
		_z_min = minf(_z_min, p.y)
	_build()


# Distance (metres, flat) from (x, z) to the nearest walkable ground. 0 inside.
func walk_dist(x: float, z: float) -> float:
	var best := INF
	for p in pieces:
		var hw := p.z * 0.5
		var dx := maxf(absf(x) - hw, 0.0)
		var dz := maxf(maxf(z - p.x, p.y - z), 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


func in_ravine(x: float, z: float) -> bool:
	return z < ravine.x and z > ravine.y


func height_at(x: float, z: float) -> float:
	var d := walk_dist(x, z)
	var n := _noise.get_noise_2d(x, z)
	var h := 0.0
	if d > 0.0:
		# A steep bank first, then rolling forest floor further out.
		h = smoothstep(0.0, bank_width, d) * (bank_height + n * 0.8)
		h += smoothstep(bank_width, bank_width * 3.0, d) * (1.5 + n * 2.0)
	if ravine != Vector2.ZERO:
		# The ravine cuts across the whole valley, banks included.
		var into := minf(ravine.x - z, z - ravine.y)
		if into > -1.2:
			var drop := smoothstep(-1.2, 0.8, into)
			h = lerpf(h, -ravine_depth + n, drop)
	return h


func paint_at(x: float, z: float, d: float) -> Color:
	var n := _noise.get_noise_2d(x * 3.0, z * 3.0)
	# Worn dirt: a wandering line down the middle of the route.
	var wander := sin(z * 0.11) * 0.9 + n * 0.5
	var path := (1.0 - smoothstep(0.7, 1.7, absf(x - wander))) * (1.0 - smoothstep(0.0, 1.0, d))
	for s in dirt_spots:
		path = maxf(path, 1.0 - smoothstep(s.z * 0.6, s.z, Vector2(x - s.x, z - s.y).length()))
	var m := 0.0
	for r in mud:
		# An irregular blob inside the mud rectangle, not the rectangle itself.
		var e := Vector2((x - r.x) / (r.z * 0.5), (z - r.y) / (r.w * 0.5)).length()
		var wobble := _noise.get_noise_2d(x * 1.5 + 40.0, z * 1.5) * 0.35
		m = maxf(m, 1.0 - smoothstep(0.75, 1.05, e + wobble))
	# Leaf litter from the edge of the walkable ground outwards.
	var litter := smoothstep(0.0, 1.6, d + n * 0.8)
	return Color(path, m, litter, 1.0)


func _build() -> void:
	var z0 := int(ceil(_z_max)) + 16
	var z1 := int(floor(_z_min)) - 16
	var nx := grid_half_width * 2 + 1
	var nz := z0 - z1 + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			heights[iz * nx + ix] = height_at(ix - grid_half_width, z1 + iz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := float(ix - grid_half_width)
			var z := float(z1 + iz)
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iz - 1, 0) * nx + ix]
			var hu := heights[mini(iz + 1, nz - 1) * nx + ix]
			st.set_normal(Vector3(hl - hr, 2.0, hd - hu).normalized())
			st.set_color(paint_at(x, z, walk_dist(x, z)))
			st.add_vertex(Vector3(x, heights[iz * nx + ix], z))
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var e := c + 1
			# Godot's front faces wind clockwise seen from the front (above).
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(e)
			st.add_index(c)
	var mesh := st.commit()

	material = ShaderMaterial.new()
	material.shader = TerrainShader
	material.set_shader_parameter("grass_tex", load("res://assets/textures/terrain/grass.jpg"))
	material.set_shader_parameter("dirt_tex", load("res://assets/textures/terrain/dirt.jpg"))
	material.set_shader_parameter("leaves_tex", load("res://assets/textures/terrain/leaves.jpg"))
	material.set_shader_parameter("cliff_tex", load("res://assets/textures/terrain/cliff.png"))
	material.set_shader_parameter("ramp", Ramp)
	# Only the banks fade, never the floor an actor stands on.
	material.set_shader_parameter("fade_min_height", 1.2)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)

	# HeightMapShape3D is centred on its node, one unit per cell.
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = heights
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(0, 0, (z0 + z1) * 0.5)
	add_child(body)
