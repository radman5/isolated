#!/usr/bin/env python3
"""Generates demos/route1.tscn, the Route 1 graybox. Edit the layout here and rerun:

    python3 tools/gen_route1.py

The route runs north (towards -z) from the Glade. Each PIECE is a strip of
ground: (name, south z, north z, width). Walls go along every edge that isn't
shared with the next piece; they're invisible, the hard edge of the route.
route_terrain.gd raises banks along the same edges and paints the ground, and
route_foliage.gd plants the forest on them. occluder_fade.gd makes trees and
banks see-through wherever they hide an actor from the camera.
Beats follow "Route 1 shape" (#8) and "Route 1 monsters" (#17).
"""
from pathlib import Path

# name, z_south, z_north, width. Contiguous: each piece starts where the last ended.
PIECES = [
    ("Glade",       20,   -20,  40),   # the arena floor already covers this one
    ("Path1",      -20,   -40,   6),   # the forest closes in
    ("ClearingA",  -40,   -56,  16),   # the first surprise: a stump barkling
    ("Path2",      -56,   -70,   6),
    ("MudClearing", -70,  -90,  20),   # a pair of barklings, mud
    ("Path3",      -90,  -100,   6),
    ("WaystoneClearing", -100, -114, 16),  # rest point, dead giant tree
    ("Path4",     -114,  -122,   6),
    ("Stretch",   -122,  -146,  30),   # stealth stretch: the nest and the satchel
    ("Path5",     -146,  -154,   6),
    ("ClearingC", -154,  -172,  18),   # a group of 3 barklings
    ("Path6",     -172,  -180,   6),
    ("RavineLip", -180,  -184,  14),   # the placeholder trigger fells the tree
    # the ravine: -184 to -192, no ground
    ("FarSide",   -192,  -206,  16),   # Settlement 2's end marker
]
RAVINE = (-184, -192)
NEST_Z = -134  # the nest demo's layout, moved north by this much

# Scene files list a basis row by row: these face west (-x), east (+x), north (-z).
WEST, EAST, NORTH = "0, 0, 1, 0, 1, 0, -1, 0, 0", "0, 0, -1, 0, 1, 0, 1, 0, 0", "1, 0, 0, 0, 1, 0, 0, 0, 1"
SOUTH = "-1, 0, 0, 0, 1, 0, 0, 0, -1"


def xf(basis, x, y, z):
    return f"Transform3D({basis}, {x}, {y}, {z})"


subs, nodes, walls = [], [], []
sub_id = 0


def sub(kind, **props):
    global sub_id
    sub_id += 1
    sid = f"s{sub_id}"
    body = "".join(f"{k} = {v}\n" for k, v in props.items())
    subs.append(f'[sub_resource type="{kind}" id="{sid}"]\n{body}')
    return sid


def static_box(name, size, pos, mat=None, parent="."):
    shape = sub("BoxShape3D", size=f"Vector3({size[0]}, {size[1]}, {size[2]})")
    path = name if parent == "." else f"{parent}/{name}"
    out = f'[node name="{name}" type="StaticBody3D" parent="{parent}"]\nposition = Vector3({pos[0]}, {pos[1]}, {pos[2]})\n\n'
    out += f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{path}"]\nshape = SubResource("{shape}")\n\n'
    if mat:
        mesh = sub("BoxMesh", size=f"Vector3({size[0]}, {size[1]}, {size[2]})")
        out += f'[node name="MeshInstance3D" type="MeshInstance3D" parent="{path}"]\nmesh = SubResource("{mesh}")\nsurface_material_override/0 = SubResource("{mat}")\n\n'
    return out


mat_log = sub("StandardMaterial3D", albedo_color="Color(0.33, 0.25, 0.17, 1)")
mat_tree = sub("StandardMaterial3D", albedo_color="Color(0.4, 0.36, 0.3, 1)")
mat_satchel = sub("StandardMaterial3D", albedo_color="Color(0.62, 0.42, 0.2, 1)")
mat_exit = sub("StandardMaterial3D", transparency="1", shading_mode="0", albedo_color="Color(0.35, 1, 0.45, 0.5)")
mat_trigger = sub("StandardMaterial3D", transparency="1", shading_mode="0", albedo_color="Color(1, 0.85, 0.3, 0.55)")


# Walls: along both sides of each piece, and across each boundary where the
# neighbour is narrower. The ravine's lip and far side get walls across the gap
# sides so you can't walk round it.
H, T = 3, 1.0
wall_i = 0


def wall(x0, x1, z0, z1):
    global wall_i
    wall_i += 1
    sx, sz = max(abs(x1 - x0), T), max(abs(z1 - z0), T)
    walls.append(static_box(f"Wall{wall_i}", (sx, H, sz), ((x0 + x1) / 2, H / 2, (z0 + z1) / 2), parent="Forest"))


for i, (name, zs, zn, w) in enumerate(PIECES):
    hw = w / 2
    wall(-hw - T / 2, -hw - T / 2, zs, zn)
    wall(hw + T / 2, hw + T / 2, zs, zn)
    prev_w = PIECES[i - 1][3] if i > 0 and PIECES[i - 1][2] == zs else 0
    next_w = PIECES[i + 1][3] if i + 1 < len(PIECES) and PIECES[i + 1][1] == zn else 0
    for z, nw, sign in ((zs, prev_w, 1), (zn, next_w, -1)):
        if nw >= w:
            continue
        z_edge = z + sign * T / 2
        if nw == 0:
            wall(-hw, hw, z_edge, z_edge)
        else:
            wall(-hw, -nw / 2, z_edge, z_edge)
            wall(nw / 2, hw, z_edge, z_edge)

# Monsters. Leg 1 in group "leg1", so a leg 2 restart removes them.
enemies = [
    ("StumpBarkling", "barkling", SOUTH, 0, -47, 'disguised = true\n', "leg1"),
    ("MudBarkling1", "barkling", SOUTH, -3, -84, "", "leg1"),
    ("MudBarkling2", "barkling", SOUTH, 3, -84, "", "leg1"),
    ("Rootkin1", "rootkin", WEST, -3.5, NEST_Z + 3, 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n', "leg2"),
    ("Rootkin2", "rootkin", EAST, 3.5, NEST_Z + 3, 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n', "leg2"),
    ("Rootkin3", "rootkin", WEST, -3.5, NEST_Z - 3, 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n', "leg2"),
    ("Rootkin4", "rootkin", EAST, 3.5, NEST_Z - 3, 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n', "leg2"),
    ("Rootkin5", "rootkin", NORTH, 0, NEST_Z - 6, 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n', "leg2"),
    ("GroupBarkling1", "barkling", SOUTH, -3, -161, "", "leg2"),
    ("GroupBarkling2", "barkling", SOUTH, 3, -161, "", "leg2"),
    ("GroupBarkling3", "barkling", SOUTH, 0, -165, "", "leg2"),
]
for name, scene, basis, x, z, extra, group in enemies:
    nodes.append(f'[node name="{name}" parent="." groups=["{group}"] instance=ExtResource("{scene}")]\ntransform = {xf(basis, x, 1.05, z)}\n{extra}\n')

# The mud clearing's mud.
nodes.append('[node name="Mud" type="Node3D" parent="."]\n'
             f'transform = {xf(NORTH, 0, 0, -80)}\nscript = ExtResource("zone")\nkind = "slow"\nsize = Vector2(14, 10)\n'
             'amount = 0.35\ncolour = Color(0, 0, 0, 0)\n\n')  # the terrain paints the mud

# The waystone and the dead giant tree.
nodes.append(f'[node name="Waystone" type="Node3D" parent="."]\ntransform = {xf(NORTH, 0, 0, -107)}\nscript = ExtResource("waystone")\n\n')
tree_shape = sub("CylinderShape3D", height="14.0", radius="1.3")
nodes.append(f'[node name="DeadTree" type="StaticBody3D" parent="."]\ntransform = {xf(NORTH, 5, 7, -110)}\n\n'
             f'[node name="CollisionShape3D" type="CollisionShape3D" parent="DeadTree"]\nshape = SubResource("{tree_shape}")\n\n')

# The nest: the stretch, the log for cover, and the satchel at the heart.
nodes.append(f'[node name="Stretch" type="Node3D" parent="."]\ntransform = {xf(NORTH, 0, 0, NEST_Z)}\nscript = ExtResource("stretch")\nsize = Vector3(30, 4, 22)\n\n')
nodes.append(static_box("Log", (7, 1.8, 0.6), (0, 0.9, NEST_Z - 8.5), mat_log))
satchel_mesh = sub("BoxMesh", size="Vector3(0.5, 0.35, 0.3)")
nodes.append(f'[node name="Satchel" type="Node3D" parent="."]\ntransform = {xf(NORTH, 0, 0, NEST_Z)}\nscript = ExtResource("pickup")\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="Satchel"]\ntransform = {xf(NORTH, 0, 0.18, 0)}\nmesh = SubResource("{satchel_mesh}")\nsurface_material_override/0 = SubResource("{mat_satchel}")\n\n')

# The ravine: an invisible lip wall until the placeholder trigger drops the bridge.
rz0, rz1 = RAVINE
nodes.append(static_box("RavineLip", (14, 3, 0.5), (0, 1.5, rz0 - 0.25)))
bridge_len = abs(rz1 - rz0) + 2
nodes.append(static_box("Bridge", (2.4, 0.6, bridge_len), (0, -0.3, (rz0 + rz1) / 2), mat_tree))
trig_mesh = sub("CylinderMesh", top_radius="1.2", bottom_radius="1.2", height="0.04")
nodes.append(f'[node name="FellTree" type="Node3D" parent="."]\ntransform = {xf(NORTH, 4.5, 0, -182)}\nscript = ExtResource("bridge")\n'
             'bridge_path = NodePath("../Bridge")\nlip_path = NodePath("../RavineLip")\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="FellTree"]\nmesh = SubResource("{trig_mesh}")\nsurface_material_override/0 = SubResource("{mat_trigger}")\n\n')

# Settlement 2: the exit, which only counts with the satchel.
exit_mesh = sub("CylinderMesh", top_radius="1.5", bottom_radius="1.5", height="0.04")
nodes.append(f'[node name="Exit" type="Node3D" parent="."]\ntransform = {xf(NORTH, 0, 0, -200)}\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="Exit"]\nmesh = SubResource("{exit_mesh}")\nsurface_material_override/0 = SubResource("{mat_exit}")\n\n')

# Signposts, so a playtester knows what each beat is meant to be.
for name, text, x, z in [
    ("SignGlade", "The Glade", 0, 14), ("SignWaystone", "Waystone (rest point)", 0, -104),
    ("SignNest", "Stealth stretch: the nest", 0, -123.5), ("SignRavine", "Ravine: step on the gold ring (placeholder puzzle)", 0, -179),
    ("SignSettlement", "Settlement 2", 0, -197),
]:
    nodes.append(f'[node name="{name}" type="Label3D" parent="."]\ntransform = {xf(NORTH, x, 3, z)}\nbillboard = 1\npixel_size = 0.01\nfont_size = 48\noutline_size = 12\ntext = "{text}"\n\n')

head = '''[gd_scene format=3]

[ext_resource type="PackedScene" path="res://demos/arena.tscn" id="arena"]
[ext_resource type="Script" path="res://route.gd" id="route"]
[ext_resource type="PackedScene" path="res://barkling.tscn" id="barkling"]
[ext_resource type="PackedScene" path="res://rootkin.tscn" id="rootkin"]
[ext_resource type="Script" path="res://stealth_stretch.gd" id="stretch"]
[ext_resource type="Script" path="res://pickup.gd" id="pickup"]
[ext_resource type="Script" path="res://waystone.gd" id="waystone"]
[ext_resource type="Script" path="res://bridge_trigger.gd" id="bridge"]
[ext_resource type="Script" path="res://route_terrain.gd" id="terrain"]
[ext_resource type="Script" path="res://route_foliage.gd" id="foliage"]
[ext_resource type="Script" path="res://occluder_fade.gd" id="fade"]
[ext_resource type="Environment" path="res://art/route_env.tres" id="env"]
[ext_resource type="Script" path="res://traps/hazard_zone.gd" id="zone"]

'''
root = '''[node name="Arena" instance=ExtResource("arena")]
script = ExtResource("route")
spawn_enemies = false
clear_wins = false
exit_needs = "satchel"
stage = "route1"

[node name="Post1" parent="." index="4"]
visible = false

[node name="Post2" parent="." index="5"]
visible = false

[node name="Post3" parent="." index="6"]
visible = false

[node name="Player" parent="." index="7"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.05, 12)

[node name="WorldEnvironment" parent="." index="0"]
environment = ExtResource("env")

[node name="Sun" parent="." index="1"]
light_color = Color(1, 0.9, 0.72, 1)
directional_shadow_max_distance = 38.0

[node name="MeshInstance3D" parent="Ground"]
visible = false

[node name="Forest" type="Node3D" parent="."]

'''
def packed(kind, rows):
    return f"{kind}(" + ", ".join(str(v) for row in rows for v in row) + ")"


MUD = [(0, -80, 14, 10)]
DIRT_SPOTS = [(0, -107, 3.2), (0, 0, 4.0), (0, -200, 3.5)]
# Landmarks drawn by route_foliage.gd: model, x, z, scale, yaw (degrees).
LANDMARKS = [
    ("Dead_Tree_1", 5, -110, 1.0, 20),     # the dead giant tree
    ("Rock_Medium_1", 0, -107, 0.55, 0),   # the waystone
    ("Tree_3", -9, -128, 0.35, 0), ("Pine_5", 8, -130, 0.35, 40),  # saplings round the nest
    ("Tree_5", -10, -139, 0.3, 90), ("Pine_1", 11, -138, 0.3, 10),
]
pieces = [(zs, zn, w) for _, zs, zn, w in PIECES]
nodes.append(f'[node name="Terrain" type="Node3D" parent="."]\nscript = ExtResource("terrain")\n'
             f'pieces = {packed("PackedVector3Array", pieces)}\nravine = Vector2({RAVINE[0]}, {RAVINE[1]})\n'
             f'mud = {packed("PackedVector4Array", MUD)}\ndirt_spots = {packed("PackedVector3Array", DIRT_SPOTS)}\n\n')
landmarks = ", ".join(f'"{m}|{x}|{z}|{sc}|{yaw}"' for m, x, z, sc, yaw in LANDMARKS)
nodes.append(f'[node name="Foliage" type="Node3D" parent="."]\nscript = ExtResource("foliage")\n'
             f'landmarks = PackedStringArray({landmarks})\n\n')
nodes.append('[node name="OccluderFade" type="Node" parent="."]\nscript = ExtResource("fade")\n\n')

out = head + "\n".join(subs) + "\n" + root + "".join(walls) + "".join(nodes)
Path(__file__).resolve().parent.parent.joinpath("demos/route1.tscn").write_text(out)
print(f"wrote demos/route1.tscn: {len(PIECES)} pieces, {wall_i} walls, {len(enemies)} monsters")
