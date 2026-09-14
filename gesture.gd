extends RefCounted
# Flick detection and bow drag. Spec §2's load-bearing rule lives here:
# gestures only register while a button is held, so free aiming never swings.
#
# No ring buffer, despite §9 asking for one: InputEventMouseMotion already
# carries an engine-computed `screen_velocity` in px/s. We use screen_velocity
# and not velocity because the project's stretch mode is "canvas_items", which
# scales `velocity` by the content scale — the threshold would then drift with
# window size.
#
# Pure: fed two Vector2s, returns one. No nodes, no Input, so check.gd can flick
# it thousands of times with no mouse and no window.

# Tunables. player.gd mirrors these as @export and pushes them every frame.
var flick_threshold := 1200.0  # px/s. NEEDS CALIBRATION - see `peak` below.
var refractory := 0.12
var drag_max_px := 300.0
var near_miss_frac := 0.6  # counts as "rejected" for the overlay, nothing more
var idle_reset := 0.05  # no motion for this long counts as the mouse stopping

var held := false
var vel := Vector2.ZERO  # last sample, for the overlay
var peak := 0.0  # session max. THIS is the calibration instrument: flick
# five times, read it, set flick_threshold from it.
var drag := Vector2.ZERO  # accumulated relative since press (bow draw)
var rejected := 0  # near-misses this hold

var _cool := 0.0
var _above := false
var _idle := 0.0  # time since the last real motion sample


func press() -> void:
	held = true
	drag = Vector2.ZERO
	rejected = 0
	_above = false


func release() -> void:
	held = false
	_above = false


func tick(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	# A still mouse produces no motion events at all, so without this _above
	# stays latched from the last flick and the NEXT flick is silently eaten -
	# flick, pause, flick would only ever swing once. Treat a gap in samples as
	# the speed having fallen to zero, which is what it physically is.
	_idle += delta
	if _idle > idle_reset:
		_above = false


# Returns the flick vector on the frame the threshold is crossed, else ZERO.
func sample(relative: Vector2, screen_velocity: Vector2) -> Vector2:
	# Godot emits motion events even when the mouse has not moved.
	if relative.is_zero_approx():
		return Vector2.ZERO

	_idle = 0.0
	var speed := screen_velocity.length()
	vel = screen_velocity
	peak = maxf(peak, speed)

	# §2: nothing registers unless a button is held. Resetting _above here is
	# what stops a flick that began before the press from carrying into it.
	if not held:
		_above = false
		return Vector2.ZERO

	drag += relative

	var was_above := _above
	_above = speed >= flick_threshold
	if not _above:
		if speed >= flick_threshold * near_miss_frac:
			rejected += 1
		return Vector2.ZERO

	# §4: fire on the CROSSING, never on completion. `was_above` is the whole
	# rule - a sustained fast drag fires once, on its first sample over the
	# line, rather than every frame or at the end of the gesture.
	if was_above or _cool > 0.0:
		return Vector2.ZERO

	_cool = refractory
	return screen_velocity


func drag_strength() -> float:
	return clampf(drag.length() / maxf(drag_max_px, 1.0), 0.0, 1.0)
