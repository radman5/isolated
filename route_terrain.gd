extends Node3D
# The route's ground, built at load from the signed distance field that
# tools/gen_route1.py generates: negative where you walk, positive outside, in
# metres, on a 1m grid.
#
# - Height: flat where you walk, banks rising with distance outside, and a
#   ravine that cuts across the valley.
# - Paint (vertex colours, read by terrain_splat.gdshader): R worn dirt along the
#   paths' centre lines, G mud, B leaf litter off the walkable ground.
# - Walls: invisible collision traced just outside the walkable edge with
#   marching squares, so the edge follows every curve. The bridge's corridor is
#   left open; the RavineLip wall blocks it until the tree falls.
# ponytail: rebuilt on every load (a few tens of thousands of cells, well under a
# second). Bake to a resource if routes get much bigger.

const TerrainShader := preload("res://shaders/terrain_splat.gdshader")
const MudShader := preload("res://shaders/mud.gdshader")
const Ramp := preload("res://art/painted_ramp.tres")

## World (x, z) of the field's first cell.
@export var origin := Vector2.ZERO
@export var cells := Vector2i.ZERO
@export var field := PackedFloat32Array()
## Distance to the nearest path centre line (for the worn dirt).
@export var path_field := PackedFloat32Array()
@export var ravine_centre := Vector2.ZERO
## Unit vector across the ravine, along the path that crosses it.
@export var ravine_across := Vector2(0, -1)
@export var ravine_half_width := 0.0
## (ax, az, bx, bz): the bridge's line, kept open in the walls.
@export var bridge := Vector4.ZERO
## (x, z, radius) of each mud patch.
@export var mud := PackedVector3Array()
## (x, z, radius) of worn dirt patches, e.g. round the waystone.
@export var dirt_spots := PackedVector3Array()
## How far the ground sinks under mud, and where the wet surface sits (both
## below ground level), so anything standing in it looks half-submerged.
@export var mud_depth := 0.35
@export var mud_surface := -0.12
@export var bank_height := 3.2
@export var bank_width := 4.0
@export var ravine_depth := 10.0
## How far outside the walkable edge the invisible walls stand.
@export var wall_offset := 0.35
@export var seed := 7

var _noise := FastNoiseLite.new()
var material: ShaderMaterial


func _ready() -> void:
	_noise.seed = seed
	_noise.frequency = 0.045
	_build()


func _sample(data: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := x - origin.x
	var fz := z - origin.y
	if fx < 0.0 or fz < 0.0 or fx >= cells.x - 1 or fz >= cells.y - 1:
		return outside
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * cells.x + ix
	var top := lerpf(data[i], data[i + 1], tx)
	var bottom := lerpf(data[i + cells.x], data[i + cells.x + 1], tx)
	return lerpf(top, bottom, tz)


# Signed distance to the walkable edge: negative inside.
func sdf(x: float, z: float) -> float:
	return _sample(field, x, z, 40.0)


# Distance (metres, flat) from (x, z) to the nearest walkable ground. 0 inside.
func walk_dist(x: float, z: float) -> float:
	return maxf(sdf(x, z), 0.0)


func _ravine_into(x: float, z: float) -> float:
	# Metres inside the ravine band; negative outside it.
	if ravine_half_width <= 0.0:
		return -INF
	var along := (Vector2(x, z) - ravine_centre).dot(ravine_across)
	return ravine_half_width - absf(along)


func in_ravine(x: float, z: float) -> bool:
	return _ravine_into(x, z) > -1.5


func height_at(x: float, z: float) -> float:
	var d := walk_dist(x, z)
	var n := _noise.get_noise_2d(x, z)
	var h := 0.0
	if d > 0.0:
		# A steep bank first, then rolling forest floor further out.
		h = smoothstep(0.0, bank_width, d) * (bank_height + n * 0.8)
		h += smoothstep(bank_width, bank_width * 3.0, d) * (1.5 + n * 2.0)
	# The mud clearing sinks, easing back up over its last 1.5m and the foot of
	# the banks.
	h -= mud_amount(x, z) * mud_depth * (1.0 - smoothstep(0.0, 1.0, d))
	var into := _ravine_into(x, z)
	if into > -1.2:
		h = lerpf(h, -ravine_depth + n, smoothstep(-1.2, 0.8, into))
	return h


# 1 inside a mud patch, easing to 0 over its outer 1.5m.
func mud_amount(x: float, z: float) -> float:
	var m := 0.0
	for r in mud:
		m = maxf(m, 1.0 - smoothstep(r.z - 1.5, r.z, Vector2(x - r.x, z - r.y).length()))
	return m


func paint_at(x: float, z: float, d: float) -> Color:
	var n := _noise.get_noise_2d(x * 3.0, z * 3.0)
	# Worn dirt along the paths' centre lines, wobbling a little.
	var pd := _sample(path_field, x, z, 12.0) + n * 0.5
	var path := (1.0 - smoothstep(0.8, 1.7, pd)) * (1.0 - smoothstep(0.0, 1.0, d))
	for s in dirt_spots:
		path = maxf(path, 1.0 - smoothstep(s.z * 0.6, s.z, Vector2(x - s.x, z - s.y).length()))
	# Mud on everything the dip reaches, walkable ground and the foot of the banks,
	# with a ragged rim.
	var wobble := _noise.get_noise_2d(x * 1.5 + 40.0, z * 1.5) * 0.25
	var m := smoothstep(0.25, 0.6, mud_amount(x, z) + wobble) * (1.0 - smoothstep(0.6, 1.6, d))
	# Leaf litter from the edge of the walkable ground outwards.
	var litter := smoothstep(0.0, 1.6, d + n * 0.8)
	return Color(path, m, litter, 1.0)


# The field the walls follow: the walkable ground plus the bridge's corridor.
func _wall_field(x: float, z: float) -> float:
	var d := sdf(x, z)
	if bridge != Vector4.ZERO:
		var a := Vector2(bridge.x, bridge.y)
		var b := Vector2(bridge.z, bridge.w)
		var p := Vector2(x, z)
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		# Narrow enough that the walls keep you on the 2.4m-wide bridge.
		d = minf(d, (p - a.lerp(b, t)).length() - 1.2)
	return d - wall_offset


func _build() -> void:
	var nx := cells.x
	var nz := cells.y
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			heights[iz * nx + ix] = height_at(origin.x + ix, origin.y + iz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := origin.x + ix
			var z := origin.y + iz
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
	# The ground only receives shadows. Casting them drew its 100k-odd triangles
	# again in every shadow pass for banks that barely shade anything.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	body.position = Vector3(origin.x + (nx - 1) * 0.5, 0, origin.y + (nz - 1) * 0.5)
	add_child(body)

	_build_walls()
	_build_mud()


# A wet surface just below ground level over each mud patch. Ground that isn't
# sunk hides it by plain depth testing, so it only shows in the dip.
func _build_mud() -> void:
	for r in mud:
		var disc := CylinderMesh.new()
		disc.top_radius = r.z + 0.5
		disc.bottom_radius = r.z + 0.5
		disc.height = 0.02
		disc.radial_segments = 48
		var mat := ShaderMaterial.new()
		mat.shader = MudShader
		mat.set_shader_parameter("ramp", Ramp)
		var mi := MeshInstance3D.new()
		mi.name = "MudSurface"
		mi.mesh = disc
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.x, mud_surface - 0.01, r.y)
		add_child(mi)


# Marching squares over the wall field: each cell the edge crosses gets a
# segment, and each segment becomes a tall two-triangle wall.
func _build_walls() -> void:
	var nx := cells.x
	var nz := cells.y
	var v := PackedFloat32Array()
	v.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			v[iz * nx + ix] = _wall_field(origin.x + ix, origin.y + iz)
	var faces := PackedVector3Array()
	var lo := -ravine_depth - 3.0
	var hi := 6.0
	for iz in nz - 1:
		for ix in nx - 1:
			var c := [v[iz * nx + ix], v[iz * nx + ix + 1], v[(iz + 1) * nx + ix + 1], v[(iz + 1) * nx + ix]]
			var p := [Vector2(ix, iz), Vector2(ix + 1, iz), Vector2(ix + 1, iz + 1), Vector2(ix, iz + 1)]
			var cut := []
			for k in 4:
				var a: float = c[k]
				var b: float = c[(k + 1) % 4]
				if (a < 0.0) != (b < 0.0):
					cut.append((p[k] as Vector2).lerp(p[(k + 1) % 4], a / (a - b)))
			# Two crossings is one segment; four (a saddle) is two.
			for k in range(0, cut.size() - 1, 2):
				var s0: Vector2 = cut[k] + origin
				var s1: Vector2 = cut[k + 1] + origin
				faces.append_array([
					Vector3(s0.x, lo, s0.y), Vector3(s1.x, lo, s1.y), Vector3(s1.x, hi, s1.y),
					Vector3(s0.x, lo, s0.y), Vector3(s1.x, hi, s1.y), Vector3(s0.x, hi, s0.y),
				])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "Walls"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
