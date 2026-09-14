extends RefCounted
# Camera-relative movement plus the fixed-camera input-transition rule from the
# test plan §3: "on any cut outside combat, held input retains its previous
# meaning until the stick/key is released."
#
# ponytail: no cut detection, no blending. Latch the basis on press, drop it on
# release, which is the whole rule. Stage 1 has one camera that never cuts, so
# the latch is provably a no-op here (latched always == current). It exists so
# stage 3's corridor can add a second angle without relearning the Resident Evil
# lesson at the worst possible moment.

var _latched: Basis
var _held := false


# input: Input.get_vector(left, right, forward, back)
# cam:   the active camera's global basis
# Returns a normalised world direction on the XZ plane, or ZERO.
func to_world(input: Vector2, cam: Basis) -> Vector3:
	if input == Vector2.ZERO:
		_held = false
		return Vector3.ZERO
	if not _held:
		_latched = cam
		_held = true
	return project(input, _latched)


# Screen-space vector -> world direction on the XZ plane. Shared by movement and
# by sword flicks, so a flick "up the screen" means the same direction as
# pressing W. Static: flick callers must NOT reuse this object's instance, whose
# latch would engage on the first flick sample and never release.
static func project(input: Vector2, cam: Basis) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var f := -cam.z
	var r := cam.x
	f.y = 0.0
	r.y = 0.0
	# Degenerate only if the camera looks straight down. Not our camera.
	# -input.y because screen +y is down, and get_vector returns +y for "back".
	return (r.normalized() * input.x - f.normalized() * input.y).normalized()
