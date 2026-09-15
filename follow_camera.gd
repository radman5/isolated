extends Camera3D
# Follows the player at a fixed angle.
#
# It only moves; it never turns. Mouse aim, WASD and the charge pull-back all
# read this camera's basis, so a constant rotation keeps "up the screen" meaning
# the same world direction wherever the player is.
#
# Smoothness depends on two things:
#   1. It follows the player's INTERPOLATED position, from _process. The player
#      moves in 60Hz physics steps, while the display here is 120Hz ProMotion;
#      following the raw position makes the camera step every other frame, which
#      reads as judder. physics/common/physics_interpolation is on for this.
#   2. The catch-up is exponential and scaled by delta, so it eases the same way
#      at any frame rate and never overshoots.

@export var target_path := NodePath("../Player")
## Degrees above the horizon. Higher looks more top-down.
@export_range(10.0, 89.0, 0.5) var pitch_deg := 50.0
## Direction the camera sits in, around the player. Changing this mid-play would
## change what "up the screen" means, so set it and leave it.
@export_range(-180.0, 180.0, 0.5) var yaw_deg := 40.6
@export var distance := 12.5
@export var look_height := 1.0
## How fast the camera catches up; higher is tighter. It covers about 63% of
## the gap in 1/follow_speed seconds.
@export var follow_speed := 6.0

var _target: Node3D
var _focus := Vector3.ZERO


func _ready() -> void:
	# Moved every frame from an already-interpolated target. Letting the engine
	# interpolate the camera as well would smooth twice and lag a physics tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path)
	if _target:
		# Snap on load so the scene reload after every fight does not swoop in.
		_focus = _target.global_position
	_apply()


func _process(delta: float) -> void:
	if _target:
		var goal := _target.get_global_transform_interpolated().origin
		_focus = _focus.lerp(goal, 1.0 - exp(-follow_speed * delta))
	_apply()


func _apply() -> void:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	# Height is pinned to look_height rather than the player's y, so gravity
	# settling on the capsule cannot make the view bob.
	var look := Vector3(_focus.x, look_height, _focus.z)
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance
	global_transform = Transform3D(Basis(), look + offset).looking_at(look, Vector3.UP)
