extends RefCounted
# The pure half of the environment traps: zone shapes, how they stack, and the
# steering that keeps a walking enemy out of them. No nodes, so check.gd can
# drive all of it with plain dictionaries.
#
# Shapes are flat: {pos, radius} or {pos, size (Vector2), yaw}. Height is ignored,
# the same simplification CombatState.in_arc makes, because everything in this
# prototype stands on one plane.

const SLOW := 0
const BURN := 1
const KILL := 2


static func inside(shape: Dictionary, p: Vector3) -> bool:
	var d := Vector2(p.x - shape.pos.x, p.z - shape.pos.z)
	if shape.has("radius"):
		return d.length() <= shape.radius
	var s: Vector2 = shape.size
	var local := d.rotated(-shape.get("yaw", 0.0))
	return absf(local.x) <= s.x * 0.5 and absf(local.y) <= s.y * 0.5


# Slowest wins, so wading through two patches is not slower than the worst one.
static func speed_mult(zones: Array, p: Vector3) -> float:
	var m := 1.0
	for z in zones:
		if z.kind_id() == SLOW and z.active and inside(z.shape(), p):
			m = minf(m, z.amount)
	return m


# The direction to actually walk: straight at the target if that is clear, else
# the first fan angle that is. `blocked` takes a probe point and answers whether
# stepping there is a bad idea - a live hazard, or no floor.
#
# ponytail: a five-ray fan, not pathfinding. An enemy can still wedge itself
# between a wall and a fire. Swap in a navmesh only if that reads badly in play.
static func steer(to_target: Vector3, from: Vector3, probe: float, blocked: Callable) -> Vector3:
	var dir := to_target
	dir.y = 0.0
	if dir.length() < 0.001:
		return Vector3.ZERO
	dir = dir.normalized()
	for deg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(deg))
		if not blocked.call(from + d * probe):
			return d
	return Vector3.ZERO
