#!/usr/bin/env python3
"""Generates demos/route1.tscn, Route 1 of Beyond the Glade. Edit and rerun:

    python3 tools/gen_route1.py [seed]

The beats and their order come from "Route 1 shape" (#8) and "Route 1 monsters"
(#17); where they sit is generated with the usual map-gen tools:

1. Clearings by constrained random walk. Each beat's clearing is placed a path's
   length on from the last, turning by a random amount. It's biased to keep
   heading north, and rejected and retried if it crowds an earlier clearing or path.
2. Winding paths. A Catmull-Rom spline through each pair of clearings, with a
   sideways-pushed midpoint for a meander, sampled into segments with a width
   that drifts along the way.
3. Side nooks. A few short dead-end spurs off the paths, each ending in a small
   clearing, so the route isn't one corridor.
4. A signed distance field (SDF). The walkable ground is a smooth union
   (smooth-min) of the clearings, as circles, and the path segments, as capsules.
   It's negative inside and positive outside, in metres, on a 1m grid.
5. Domain warping. The SDF is sampled at a point pushed about by fractal value
   noise, so no edge is a straight line or a perfect circle.
6. The ravine cuts a band across the whole valley at the path that crosses it.

The field goes into the Terrain node. At load, route_terrain.gd raises banks
from it, paints the ground, and traces the collision walls along its outline
with marching squares. route_foliage.gd plants the forest with Poisson-disc
sampling.
"""
import math
import random
import sys
from pathlib import Path

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 8
rng = random.Random(SEED)

# name, radius. In route order. Leg 1 ends at the waystone.
BEATS = [
    ("Glade", 16),        # home: you start here
    ("ClearingA", 9),     # the first surprise: a stump barkling on the way in
    ("MudClearing", 12),  # a pair of barklings, mud
    ("WaystoneClearing", 10),  # rest point, the dead giant tree
    ("Stretch", 15),      # stealth stretch: the nest and the satchel
    ("ClearingC", 11),    # a group of 3 barklings
    ("RavineLip", 7),     # the placeholder trigger fells the tree
    ("FarSide", 9),       # Settlement 2
]
RAVINE_HALF_WIDTH = 4.0
NOOKS = 3


# --- noise -----------------------------------------------------------------

def _hash(ix, iz, s):
    h = (ix * 374761393 + iz * 668265263 + s * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def value_noise(x, z, s):
    ix, iz = math.floor(x), math.floor(z)
    fx, fz = x - ix, z - iz
    ux, uz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
    a, b = _hash(ix, iz, s), _hash(ix + 1, iz, s)
    c, d = _hash(ix, iz + 1, s), _hash(ix + 1, iz + 1, s)
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz


def fbm(x, z, s, octaves=3):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total += (value_noise(x * freq, z * freq, s + o * 17) - 0.5) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm * 2.0  # about -1..1


# --- layout ----------------------------------------------------------------

def heading_dir(t):
    # t = 0 heads north (-z); positive turns east (+x).
    return (math.sin(t), -math.cos(t))


def seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    qx, qz = ax + dx * t, az + dz * t
    return math.hypot(px - qx, pz - qz)


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * (2 * p1[i] + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                        + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(2))


def place_clearings():
    for _attempt in range(400):
        centres, headings, t = [(0.0, 0.0)], [0.0], 0.0
        ok = True
        for i in range(1, len(BEATS)):
            r_prev, r = BEATS[i - 1][1], BEATS[i][1]
            placed = False
            for _try in range(60):
                # Mean-reverting: it winds, but keeps making progress north.
                nt = max(-0.95, min(0.95, t * 0.35 + rng.uniform(-0.8, 0.8)))
                # The ravine crossing needs a short, straight run for the bridge.
                gap = rng.uniform(12, 15) if BEATS[i][0] == "FarSide" else rng.uniform(12, 24)
                L = r_prev + r + gap
                dx, dz = heading_dir(nt)
                c = (centres[-1][0] + dx * L, centres[-1][1] + dz * L)
                if all(math.hypot(c[0] - o[0], c[1] - o[1]) > BEATS[j][1] + r + 9
                       for j, o in enumerate(centres[:-1])):
                    centres.append(c)
                    headings.append(nt)
                    t = nt
                    placed = True
                    break
            if not placed:
                ok = False
                break
        if ok:
            return centres, headings
    raise SystemExit("could not place the clearings; try another seed")


centres, headings = place_clearings()
N = len(BEATS)

# Paths: a spline from each clearing to the next, pushed sideways mid-way.
paths = []  # list of polylines [(x, z, width)]
for i in range(N - 1):
    a, b = centres[i], centres[i + 1]
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    nx, nz = -(b[1] - a[1]) / L, (b[0] - a[0]) / L
    straight = BEATS[i + 1][0] == "FarSide"
    push = 0.0 if straight else rng.uniform(-0.28, 0.28) * L
    mid = ((a[0] + b[0]) / 2 + nx * push, (a[1] + b[1]) / 2 + nz * push)
    ctrl = [(2 * a[0] - mid[0], 2 * a[1] - mid[1]), a, mid, b, (2 * b[0] - mid[0], 2 * b[1] - mid[1])]
    pts = []
    for k in range(2):
        steps = max(4, int(L / 3))
        for s in range(steps + (1 if k == 1 else 0)):
            x, z = catmull(ctrl[k], ctrl[k + 1], ctrl[k + 2], ctrl[k + 3], s / steps)
            w = 5.0 + 1.6 * fbm(x * 0.05, z * 0.05, SEED + 3)
            pts.append((x, z, 3.2 if straight else w))
    paths.append(pts)

# Side nooks: a short dead-end spur off a path, ending in a small clearing.
nooks = []
spurs = []
candidates = [i for i in range(N - 1) if BEATS[i + 1][0] not in ("FarSide", "Stretch") and BEATS[i][0] != "Stretch"]
rng.shuffle(candidates)
def try_nook(pts, k, side):
    (xa, za, _), (xb, zb, _) = pts[k - 1], pts[k + 1]
    L = math.hypot(xb - xa, zb - za)
    nx, nz = -(zb - za) / L * side, (xb - xa) / L * side
    length, r = rng.uniform(12, 16), rng.uniform(4.5, 6.0)
    c = (pts[k][0] + nx * length, pts[k][1] + nz * length)
    others = [n_ for n_ in nooks]
    if not all(math.hypot(c[0] - o[0], c[1] - o[1]) > BEATS[j][1] + r + 5 for j, o in enumerate(centres)):
        return False
    if not all(math.hypot(c[0] - o[0], c[1] - o[1]) > o[2] + r + 6 for o in others):
        return False
    if not all(seg_dist(c[0], c[1], p[m][0], p[m][1], p[m + 1][0], p[m + 1][1]) > r + 6
               for p in paths for m in range(len(p) - 1)):
        return False
    nooks.append((c[0], c[1], r))
    spurs.append([(pts[k][0], pts[k][1], 3.4), (c[0], c[1], 3.4)])
    return True


for i in candidates:
    if len(nooks) >= NOOKS:
        break
    pts = paths[i]
    spots = [(k, side) for k in (len(pts) // 3, len(pts) // 2, 2 * len(pts) // 3) for side in (-1, 1)]
    rng.shuffle(spots)
    for k, side in spots:
        if 0 < k < len(pts) - 1 and try_nook(pts, k, side):
            break

# The ravine: across the straight path into the far side.
rp = paths[N - 2]
ra, rb = rp[0], rp[-1]
rlen = math.hypot(rb[0] - ra[0], rb[1] - ra[1])
fwd = ((rb[0] - ra[0]) / rlen, (rb[1] - ra[1]) / rlen)
rc = ((ra[0] + rb[0]) / 2, (ra[1] + rb[1]) / 2)
# Keep the ravine clear of both clearings' edges.
lip_r, far_r = BEATS[N - 2][1], BEATS[N - 1][1]
along = lip_r + (rlen - lip_r - far_r) / 2
rc = (ra[0] + fwd[0] * along, ra[1] + fwd[1] * along)
band_dir = (-fwd[1], fwd[0])


def ravine_d(x, z):
    # Positive outside the ravine band, negative inside it.
    return abs((x - rc[0]) * fwd[0] + (z - rc[1]) * fwd[1]) - RAVINE_HALF_WIDTH


# --- the field ---------------------------------------------------------------

def smin(a, b, k):
    h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25


segs = []  # (ax, az, bx, bz, half width)
for pts in paths + spurs:
    for m in range(len(pts) - 1):
        a, b = pts[m], pts[m + 1]
        segs.append((a[0], a[1], b[0], b[1], (a[2] + b[2]) / 4))
circles = [(c[0], c[1], BEATS[i][1]) for i, c in enumerate(centres)] + nooks

xs = [c[0] for c in centres] + [n[0] for n in nooks]
zs = [c[1] for c in centres] + [n[1] for n in nooks]
MARGIN = 26
x0, x1 = math.floor(min(xs) - max(r for _, r in BEATS) - MARGIN), math.ceil(max(xs) + max(r for _, r in BEATS) + MARGIN)
z0, z1 = math.floor(min(zs) - max(r for _, r in BEATS) - MARGIN), math.ceil(max(zs) + max(r for _, r in BEATS) + MARGIN)
NX, NZ = x1 - x0 + 1, z1 - z0 + 1
WARP = 2.6


def walk_sdf(x, z):
    wx = x + WARP * fbm(x * 0.07, z * 0.07, SEED + 11)
    wz = z + WARP * fbm(x * 0.07 + 31.0, z * 0.07, SEED + 23)
    d = 1e9
    for cx, cz, r in circles:
        if abs(wx - cx) < r + 30 and abs(wz - cz) < r + 30:
            d = smin(d, math.hypot(wx - cx, wz - cz) - r, 4.0)
    for ax, az, bx, bz, hw in segs:
        if min(ax, bx) - 30 < wx < max(ax, bx) + 30 and min(az, bz) - 30 < wz < max(az, bz) + 30:
            d = smin(d, seg_dist(wx, wz, ax, az, bx, bz) - hw, 3.0)
    return max(d, -ravine_d(x, z), -40.0)


def path_sdf(x, z):
    # Distance to the paths' centre lines, unwarped: the worn dirt follows it.
    d = 1e9
    for pts in paths:
        for m in range(len(pts) - 1):
            a, b = pts[m], pts[m + 1]
            if min(a[0], b[0]) - 12 < x < max(a[0], b[0]) + 12 and min(a[1], b[1]) - 12 < z < max(a[1], b[1]) + 12:
                d = min(d, seg_dist(x, z, a[0], a[1], b[0], b[1]))
    return min(d, 12.0)


field, pfield = [], []
for iz in range(NZ):
    for ix in range(NX):
        x, z = x0 + ix, z0 + iz
        field.append(max(min(walk_sdf(x, z), 40.0), -40.0))
        pfield.append(path_sdf(x, z))

# --- the scene ---------------------------------------------------------------


def yaw_xf(yaw, x, y, z):
    # Scene files list the basis row by row. A node with this yaw faces
    # (-sin yaw, -cos yaw).
    c, s = math.cos(yaw), math.sin(yaw)
    return f"Transform3D({c:.5f}, 0, {s:.5f}, 0, 1, 0, {-s:.5f}, 0, {c:.5f}, {x:.3f}, {y:.3f}, {z:.3f})"


def frame(i):
    # Local frame at clearing i: forward along the route, right to its right.
    t = headings[i + 1] if i + 1 < N else headings[i]
    t = (headings[i] + t) / 2
    f = heading_dir(t)
    return centres[i], f, (-f[1], f[0]), -t


def local(i, lx, lz):
    # lx right, lz back (so -lz is forward), like the nest demo's layout.
    c, f, r, _ = frame(i)
    return (c[0] + r[0] * lx - f[0] * lz, c[1] + r[1] * lx - f[1] * lz)


def idx(name):
    return [b[0] for b in BEATS].index(name)


subs, nodes = [], []
sub_id = 0


def sub(kind, **props):
    global sub_id
    sub_id += 1
    sid = f"s{sub_id}"
    subs.append(f'[sub_resource type="{kind}" id="{sid}"]\n' + "".join(f"{k} = {v}\n" for k, v in props.items()))
    return sid


def static_box(name, size, xf, mat=None):
    shape = sub("BoxShape3D", size=f"Vector3({size[0]}, {size[1]}, {size[2]})")
    out = f'[node name="{name}" type="StaticBody3D" parent="."]\ntransform = {xf}\n\n'
    out += f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{name}"]\nshape = SubResource("{shape}")\n\n'
    if mat:
        mesh = sub("BoxMesh", size=f"Vector3({size[0]}, {size[1]}, {size[2]})")
        out += f'[node name="MeshInstance3D" type="MeshInstance3D" parent="{name}"]\nmesh = SubResource("{mesh}")\nsurface_material_override/0 = SubResource("{mat}")\n\n'
    return out


mat_bark = sub("StandardMaterial3D", albedo_color="Color(0.34, 0.27, 0.21, 1)")
mat_log = sub("StandardMaterial3D", albedo_color="Color(0.33, 0.25, 0.17, 1)")
mat_satchel = sub("StandardMaterial3D", albedo_color="Color(0.62, 0.42, 0.2, 1)")
mat_exit = sub("StandardMaterial3D", transparency="1", shading_mode="0", albedo_color="Color(0.35, 1, 0.45, 0.5)")
mat_trigger = sub("StandardMaterial3D", transparency="1", shading_mode="0", albedo_color="Color(1, 0.85, 0.3, 0.55)")

# Monsters, placed in each clearing's local frame. Leg 1 is in group "leg1", so a
# leg 2 restart removes them. Local yaw 0 faces forward, pi faces back.
NEST = 'nest = "nest"\nstretch_path = NodePath("../Stretch")\n'
monsters = []
a = idx("ClearingA")
monsters.append(("StumpBarkling", "barkling", a, 0, BEATS[a][1] - 2.5, math.pi, 'disguised = true\n', "leg1"))
m = idx("MudClearing")
monsters += [("MudBarkling1", "barkling", m, -3, -3, math.pi, "", "leg1"),
             ("MudBarkling2", "barkling", m, 3, -3, math.pi, "", "leg1")]
n = idx("Stretch")
# The nest demo's layout: the side four face outwards, the last faces on up the
# route behind the log, leaving a sneaking lane up the middle and round the log.
monsters += [("Rootkin1", "rootkin", n, -3.5, 3, math.pi / 2, NEST, "leg2"),
             ("Rootkin2", "rootkin", n, 3.5, 3, -math.pi / 2, NEST, "leg2"),
             ("Rootkin3", "rootkin", n, -3.5, -3, math.pi / 2, NEST, "leg2"),
             ("Rootkin4", "rootkin", n, 3.5, -3, -math.pi / 2, NEST, "leg2"),
             ("Rootkin5", "rootkin", n, 0, -6, 0.0, NEST, "leg2")]
g = idx("ClearingC")
monsters += [("GroupBarkling1", "barkling", g, -3, -2, math.pi, "", "leg2"),
             ("GroupBarkling2", "barkling", g, 3, -2, math.pi, "", "leg2"),
             ("GroupBarkling3", "barkling", g, 0, -5, math.pi, "", "leg2")]
for name, scene, i, lx, lz, lyaw, extra, group in monsters:
    x, z = local(i, lx, lz)
    nodes.append(f'[node name="{name}" parent="." groups=["{group}"] instance=ExtResource("{scene}")]\n'
                 f'transform = {yaw_xf(frame(i)[3] + lyaw, x, 1.05, z)}\n{extra}\n')

# Mud: a round patch in the mud clearing (the terrain paints it).
mx, mz = local(m, 0, 1)
MUD = [(round(mx, 2), round(mz, 2), 5.5)]
nodes.append(f'[node name="Mud" type="Node3D" parent="."]\ntransform = {yaw_xf(0, mx, 0, mz)}\n'
             'script = ExtResource("zone")\nkind = "slow"\nradius = 5.5\namount = 0.35\ncolour = Color(0, 0, 0, 0)\n\n')

# The waystone and the dead giant tree.
w = idx("WaystoneClearing")
wx, wz = local(w, 0, 0)
tx, tz = local(w, 5, -2)
nodes.append(f'[node name="Waystone" type="Node3D" parent="."]\ntransform = {yaw_xf(0, wx, 0, wz)}\nscript = ExtResource("waystone")\n\n')
tree_shape = sub("CylinderShape3D", height="14.0", radius="1.0")
nodes.append(f'[node name="DeadTree" type="StaticBody3D" parent="."]\ntransform = {yaw_xf(0, tx, 7, tz)}\n\n'
             f'[node name="CollisionShape3D" type="CollisionShape3D" parent="DeadTree"]\nshape = SubResource("{tree_shape}")\n\n')

# The nest: the stretch, the log for cover, and the satchel at the heart.
ncx, ncz = centres[n]
nyaw = frame(n)[3]
side = BEATS[n][1] * 2 + 4
nodes.append(f'[node name="Stretch" type="Node3D" parent="."]\ntransform = {yaw_xf(nyaw, ncx, 0, ncz)}\n'
             f'script = ExtResource("stretch")\nsize = Vector3({side}, 4, {side})\n\n')
lx_, lz_ = local(n, 0, -8.5)
nodes.append(static_box("Log", (7, 1.8, 0.6), yaw_xf(nyaw, lx_, 0.9, lz_), mat_log))
satchel_mesh = sub("BoxMesh", size="Vector3(0.5, 0.35, 0.3)")
nodes.append(f'[node name="Satchel" type="Node3D" parent="."]\ntransform = {yaw_xf(0, ncx, 0, ncz)}\nscript = ExtResource("pickup")\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="Satchel"]\ntransform = {yaw_xf(0, 0, 0.18, 0)}\n'
             f'mesh = SubResource("{satchel_mesh}")\nsurface_material_override/0 = SubResource("{mat_satchel}")\n\n')

# The ravine: an invisible lip wall until the placeholder trigger drops the bridge.
ryaw = -math.atan2(fwd[0], -fwd[1])
lipx, lipz = rc[0] - fwd[0] * (RAVINE_HALF_WIDTH + 0.4), rc[1] - fwd[1] * (RAVINE_HALF_WIDTH + 0.4)
nodes.append(static_box("RavineLip", (8, 3, 0.5), yaw_xf(ryaw, lipx, 1.5, lipz)))
nodes.append(static_box("Bridge", (2.4, 0.6, RAVINE_HALF_WIDTH * 2 + 4), yaw_xf(ryaw, rc[0], -0.3, rc[1]), mat_bark))
trig_mesh = sub("CylinderMesh", top_radius="1.2", bottom_radius="1.2", height="0.04")
lip = idx("RavineLip")
fx_, fz_ = local(lip, 3.5, 1.5)
nodes.append(f'[node name="FellTree" type="Node3D" parent="."]\ntransform = {yaw_xf(0, fx_, 0, fz_)}\nscript = ExtResource("bridge")\n'
             'bridge_path = NodePath("../Bridge")\nlip_path = NodePath("../RavineLip")\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="FellTree"]\nmesh = SubResource("{trig_mesh}")\nsurface_material_override/0 = SubResource("{mat_trigger}")\n\n')

# Settlement 2: the exit, which only counts with the satchel.
ex, ez = centres[idx("FarSide")]
exit_mesh = sub("CylinderMesh", top_radius="1.5", bottom_radius="1.5", height="0.04")
nodes.append(f'[node name="Exit" type="Node3D" parent="."]\ntransform = {yaw_xf(0, ex, 0, ez)}\n\n'
             f'[node name="MeshInstance3D" type="MeshInstance3D" parent="Exit"]\nmesh = SubResource("{exit_mesh}")\nsurface_material_override/0 = SubResource("{mat_exit}")\n\n')

# Signposts, so a playtester knows what each beat is meant to be.
signs = [("SignGlade", "The Glade", idx("Glade"), 0, 4), ("SignWaystone", "Waystone (rest point)", w, 0, 2.5),
         ("SignNest", "Stealth stretch: the nest", n, 0, BEATS[n][1] - 1),
         ("SignRavine", "Ravine: step on the gold ring (placeholder puzzle)", lip, 0, 2.5),
         ("SignSettlement", "Settlement 2", idx("FarSide"), 0, 3)]
for name, text, i, lx, lz in signs:
    x, z = local(i, lx, lz)
    nodes.append(f'[node name="{name}" type="Label3D" parent="."]\ntransform = {yaw_xf(0, x, 3, z)}\nbillboard = 1\n'
                 f'pixel_size = 0.01\nfont_size = 48\noutline_size = 12\ntext = "{text}"\n\n')

# Landmarks drawn by route_foliage.gd: model|x|z|scale|yaw degrees.
landmarks = [("Dead_Tree_1", tx, tz, 1.0, 20), ("Rock_Medium_1", wx, wz, 0.55, 0)]
for k, (lx, lz) in enumerate([(-9, 6), (8, 4), (-10, -5), (11, -4)]):
    x, z = local(n, lx, lz)
    landmarks.append((("Tree_3", "Pine_5", "Tree_5", "Pine_1")[k], x, z, 0.33, k * 50))
for k, (cx, cz, r) in enumerate(nooks):
    landmarks.append((("Rock_Medium_2", "Rock_Medium_3", "Rock_Medium_1")[k % 3], cx + r * 0.3, cz - r * 0.2, 0.6, k * 70))
    landmarks.append(("Mushroom_Laetiporus_1", cx - r * 0.35, cz + r * 0.25, 0.8, k * 40))
DIRT_SPOTS = [(wx, wz, 3.2), (0, 0, 4.0), (ex, ez, 3.5)]

gx, gz = centres[0]


def packed(kind, rows):
    return f"{kind}(" + ", ".join(f"{v:.2f}" if isinstance(v, float) else str(v) for row in rows for v in row) + ")"


floats = lambda vals: "PackedFloat32Array(" + ", ".join(f"{v:.1f}" for v in vals) + ")"
bridge_a = (rc[0] - fwd[0] * (RAVINE_HALF_WIDTH + 2.5), rc[1] - fwd[1] * (RAVINE_HALF_WIDTH + 2.5))
bridge_b = (rc[0] + fwd[0] * (RAVINE_HALF_WIDTH + 2.5), rc[1] + fwd[1] * (RAVINE_HALF_WIDTH + 2.5))
nodes.append(f'[node name="Terrain" type="Node3D" parent="."]\nscript = ExtResource("terrain")\n'
             f'origin = Vector2({x0}, {z0})\ncells = Vector2i({NX}, {NZ})\nfield = {floats(field)}\npath_field = {floats(pfield)}\n'
             f'ravine_centre = Vector2({rc[0]:.3f}, {rc[1]:.3f})\nravine_across = Vector2({fwd[0]:.5f}, {fwd[1]:.5f})\n'
             f'ravine_half_width = {RAVINE_HALF_WIDTH}\n'
             f'bridge = Vector4({bridge_a[0]:.3f}, {bridge_a[1]:.3f}, {bridge_b[0]:.3f}, {bridge_b[1]:.3f})\n'
             f'mud = {packed("PackedVector3Array", MUD)}\ndirt_spots = {packed("PackedVector3Array", [(round(x, 2), round(z, 2), r) for x, z, r in DIRT_SPOTS])}\n\n')
lm = ", ".join(f'"{m_}|{x:.2f}|{z:.2f}|{sc}|{yw}"' for m_, x, z, sc, yw in landmarks)
nodes.append(f'[node name="Foliage" type="Node3D" parent="."]\nscript = ExtResource("foliage")\nlandmarks = PackedStringArray({lm})\n\n')
nodes.append('[node name="OccluderFade" type="Node" parent="."]\nscript = ExtResource("fade")\n\n')

head = '''[gd_scene format=3]

[ext_resource type="PackedScene" path="res://demos/arena.tscn" id="arena"]
[ext_resource type="Script" path="res://route.gd" id="route"]
[ext_resource type="PackedScene" path="res://barkling.tscn" id="barkling"]
[ext_resource type="PackedScene" path="res://rootkin.tscn" id="rootkin"]
[ext_resource type="Script" path="res://stealth_stretch.gd" id="stretch"]
[ext_resource type="Script" path="res://pickup.gd" id="pickup"]
[ext_resource type="Script" path="res://waystone.gd" id="waystone"]
[ext_resource type="Script" path="res://bridge_trigger.gd" id="bridge"]
[ext_resource type="Script" path="res://traps/hazard_zone.gd" id="zone"]
[ext_resource type="Script" path="res://route_terrain.gd" id="terrain"]
[ext_resource type="Script" path="res://route_foliage.gd" id="foliage"]
[ext_resource type="Script" path="res://occluder_fade.gd" id="fade"]
[ext_resource type="Environment" path="res://art/route_env.tres" id="env"]

'''
root = f'''[node name="Arena" instance=ExtResource("arena")]
script = ExtResource("route")
spawn_enemies = false
clear_wins = false
exit_needs = "satchel"
stage = "route1"

[node name="WorldEnvironment" parent="." index="0"]
environment = ExtResource("env")

[node name="Sun" parent="." index="1"]
light_color = Color(1, 0.9, 0.72, 1)
directional_shadow_max_distance = 38.0
directional_shadow_mode = 1

[node name="Ground" parent="." index="3"]
collision_layer = 0

[node name="MeshInstance3D" parent="Ground"]
visible = false

[node name="Post1" parent="." index="4"]
visible = false

[node name="Post2" parent="." index="5"]
visible = false

[node name="Post3" parent="." index="6"]
visible = false

[node name="Player" parent="." index="7"]
transform = {yaw_xf(0, gx, 1.05, gz + 6)}

'''
out = head + "\n".join(subs) + "\n" + root + "".join(nodes)
Path(__file__).resolve().parent.parent.joinpath("demos/route1.tscn").write_text(out)
length = sum(math.hypot(p[k + 1][0] - p[k][0], p[k + 1][1] - p[k][1]) for p in paths for k in range(len(p) - 1))
print(f"seed {SEED}: {N} clearings, {len(nooks)} nooks, path {length:.0f} m, field {NX}x{NZ}, "
      f"bounds x {x0}..{x1} z {z0}..{z1}")
