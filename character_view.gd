extends Node3D
# The visible character. It watches its actor's combat state and plays the
# matching KayKit animation, and never changes gameplay: timings, movement and the
# hit test all stay in combat_state/player/enemy. So the animation is fitted to the
# game, not the game to the animation. Delete this node and the game plays
# identically, just invisibly.
#
# Swings are time-warped around their measured IMPACT moment (the frame the hand
# moves fastest), so the blade lands exactly when the active frames start however
# long the wind-up is tuned to be. A held charge simply stops advancing at the top
# of the wind-up, which is the pose the game is holding.

const CombatState := preload("res://combat_state.gd")
const Stance := preload("res://stance_state.gd")

const ANIM_FILES := ["General", "MovementBasic", "MovementAdvanced", "CombatMelee", "CombatRanged", "Special"]

# Seconds into each clip where the swinging hand is fastest. Measured by sampling
# handslot.r speed across every clip (see git history); re-measure if clips change.
const IMPACT := {
	"Melee_1H_Attack_Slice_Horizontal": 0.27,
	"Melee_1H_Attack_Slice_Diagonal": 0.42,
	"Melee_1H_Attack_Stab": 0.40,
	"Melee_1H_Attack_Chop": 0.59,
	"Melee_1H_Attack_Jump_Chop": 0.73,
}
# The pose is held this far before impact, and the active window covers PRE..POST
# around it, so the strike reads as happening during the active frames.
const PRE := 0.05
const POST := 0.12
# A wind-up shorter than the clip's own run-up trims the start instead of playing
# absurdly fast; this is the most it will speed the anticipation up.
const MAX_WINDUP_SPEED := 1.5

@export var model: PackedScene
@export var right_hand: PackedScene
@export var left_hand: PackedScene
@export var model_scale := 0.9
@export var is_enemy := false
## Speed at which the run cycle plays at 1x, in m/s.
@export var run_speed := 5.0
@export var walk_speed := 2.0

# Loaded once and shared by every character: they all use Rig_Medium.
static var _library_cache := {}
static var _clip_lib := {}

var _actor: Node
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _right: Node3D
var _left: Node3D
var _clip := ""
var _prev_state := -1
var _was_charging := false
var _swing_clip := ""
var _impact := 0.0
var _start := 0.0
var _phase := -1
var _dead_played := false
var _bow_mesh: MeshInstance3D


func _ready() -> void:
	_actor = get_parent()
	var m: Node3D = model.instantiate()
	add_child(m)
	# KayKit faces +Z; this game's forward is -Z. Feet at the capsule's base.
	m.rotation.y = PI
	m.scale = Vector3.ONE * model_scale
	m.position.y = -1.0
	_skel = m.get_node("Rig_Medium/Skeleton3D")
	_ap = AnimationPlayer.new()
	m.add_child(_ap)
	_ap.root_node = NodePath("..")
	_load_libraries()
	for lib_name in _library_cache:
		_ap.add_animation_library(lib_name, _library_cache[lib_name])
	_right = _attach(right_hand, "handslot.r")
	_left = _attach(left_hand, "handslot.l")
	if _left:
		_bow_mesh = _find_blend_mesh(_left)
	_play("Skeletons_Idle" if is_enemy else "Idle_A", 0.0)


static func _load_libraries() -> void:
	if not _library_cache.is_empty():
		return
	for f in ANIM_FILES:
		var scene: Node = load("res://assets/kaykit/animations/Rig_Medium_%s.glb" % f).instantiate()
		var src: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var lib: AnimationLibrary = src.get_animation_library(&"").duplicate(true)
		scene.free()
		for anim_name in lib.get_animation_list():
			var a: Animation = lib.get_animation(anim_name)
			_strip_root_motion(a)
			if String(anim_name).begins_with("Idle") or String(anim_name).begins_with("Running") \
					or String(anim_name).begins_with("Walking") or anim_name in [&"Skeletons_Idle", &"Skeletons_Walking",
					&"Melee_Blocking", &"Ranged_Bow_Aiming_Idle"]:
				a.loop_mode = Animation.LOOP_LINEAR
			_clip_lib[String(anim_name)] = f
		_library_cache[f] = lib


# Dodges and the skeleton death slide the root bone up to 0.7 m. The physics body
# already does the moving, so sideways root motion would drag the mesh off it.
# Vertical motion (hops, falls) is kept.
static func _strip_root_motion(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(a.track_get_path(t)).ends_with(":root"):
			continue
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(0.0, v.y, 0.0))


func _attach(scene: PackedScene, bone: String) -> Node3D:
	if scene == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	_skel.add_child(ba)
	var w: Node3D = scene.instantiate()
	ba.add_child(w)
	return w


func _find_blend_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.mesh and n.mesh.get_blend_shape_count() > 0:
		return n
	for c in n.get_children():
		var found := _find_blend_mesh(c)
		if found:
			return found
	return null


func _process(delta: float) -> void:
	var cs = _actor.cs
	var ss = _actor.get("ss")
	_update_weapons(ss)

	if cs.dead():
		if not _dead_played:
			_dead_played = true
			_play("Skeletons_Death" if is_enemy else "Death_A", 0.1)
		return

	var state: int = cs.state
	var entered: bool = state != _prev_state
	_prev_state = state

	match state:
		CombatState.WINDUP, CombatState.ACTIVE, CombatState.RECOVERY:
			_drive_swing(cs, entered)
		CombatState.DODGE:
			if entered:
				_play(_dodge_clip(), 0.05)
				_ap.speed_scale = 0.4 / maxf(cs.dodge_time, 0.01)
		CombatState.STAGGER:
			if entered:
				_play("Hit_A", 0.05)
				_ap.speed_scale = 1.0
		_:
			_drive_idle(ss, entered)


# --- swings ------------------------------------------------------------------

func _drive_swing(cs, entered: bool) -> void:
	var charging: bool = cs.charging()
	if cs.state == CombatState.WINDUP and entered:
		_begin_swing(_pick_swing_clip(false), cs.windup_time, 0.06)
		_was_charging = false
	# Turning into a charge swaps to the heavy overhead, held at its wind-up.
	if charging and not _was_charging:
		_begin_swing(_pick_swing_clip(true), cs.windup_time, 0.12)
		_ap.seek(maxf(_impact - PRE, 0.0), true)
	_was_charging = charging

	var p := _clip_len()
	match cs.state:
		CombatState.WINDUP:
			if charging:
				_ap.speed_scale = 0.0
			elif _phase != 0:
				_phase = 0
		CombatState.ACTIVE:
			if _phase != 1:
				_phase = 1
				_ap.seek(maxf(_impact - PRE, 0.0), true)
				_ap.speed_scale = (PRE + POST) / maxf(cs.active_time, 0.01)
		CombatState.RECOVERY:
			if _phase != 2:
				_phase = 2
				_ap.seek(minf(_impact + POST, p), true)
				# Play the follow-through, but never so slowly that it outlasts the
				# recovery; whatever is left is cut by the blend back to idle.
				var rest := p - (_impact + POST)
				_ap.speed_scale = clampf(rest / maxf(cs.recovery_time, 0.01), 1.0, 2.5)


func _begin_swing(clip: String, windup: float, blend: float) -> void:
	_swing_clip = clip
	_impact = IMPACT.get(clip, 0.3)
	var hold := maxf(_impact - PRE, 0.0)
	_start = maxf(0.0, hold - windup * MAX_WINDUP_SPEED)
	_play(clip, blend)
	_ap.seek(_start, true)
	_ap.speed_scale = (hold - _start) / maxf(windup, 0.01)
	_phase = 0


func _pick_swing_clip(charged: bool) -> String:
	if is_enemy:
		return "Melee_1H_Attack_Chop"
	if charged:
		return "Melee_1H_Attack_Jump_Chop"
	var ss = _actor.ss
	# The chain alternates sides and ends on a thrust.
	if ss.chain >= ss.chain_cap:
		return "Melee_1H_Attack_Stab"
	return "Melee_1H_Attack_Slice_Horizontal" if ss.chain <= 1 else "Melee_1H_Attack_Slice_Diagonal"


# --- everything else ----------------------------------------------------------

func _drive_idle(ss, entered: bool) -> void:
	if ss != null and ss.stance == Stance.BLOCK:
		_play_loop("Melee_Blocking", 0.1)
		return
	if ss != null and ss.stance == Stance.BOW:
		if _clip != "Ranged_Bow_Draw" and _clip != "Ranged_Bow_Aiming_Idle":
			_play("Ranged_Bow_Draw", 0.1)
			_ap.speed_scale = 1.0
		elif _clip == "Ranged_Bow_Draw" and not _ap.is_playing():
			_play_loop("Ranged_Bow_Aiming_Idle", 0.1)
		return
	if _clip == "Ranged_Bow_Draw" or _clip == "Ranged_Bow_Aiming_Idle":
		_play("Ranged_Bow_Release", 0.05)
		_ap.speed_scale = 1.5
	if _clip == "Ranged_Bow_Release" and _ap.is_playing():
		return

	var v: Vector3 = _actor.velocity
	var speed := Vector2(v.x, v.z).length()
	if speed < 0.3:
		_play_loop("Skeletons_Idle" if is_enemy else "Idle_A", 0.15)
		_ap.speed_scale = 1.0
	elif is_enemy:
		_play_loop("Skeletons_Walking", 0.15)
		_ap.speed_scale = speed / walk_speed
	elif speed < 2.5:
		_play_loop("Walking_A", 0.15)
		_ap.speed_scale = speed / walk_speed
	else:
		_play_loop("Running_A", 0.15)
		_ap.speed_scale = speed / run_speed


func _dodge_clip() -> String:
	var d: Vector3 = _actor.dodge_dir
	# Into the actor's own frame, where forward is -Z.
	var local: Vector3 = _actor.global_transform.basis.inverse() * d
	if absf(local.z) >= absf(local.x):
		return "Dodge_Forward" if local.z < 0.0 else "Dodge_Backward"
	return "Dodge_Right" if local.x > 0.0 else "Dodge_Left"


func _update_weapons(ss) -> void:
	if ss == null or _left == null:
		return
	var bow: bool = _actor.weapon == Stance.BOW
	_left.visible = bow
	if _right:
		_right.visible = not bow
	if _bow_mesh:
		_bow_mesh.set_blend_shape_value(0, _actor.draw_strength)


func _clip_len() -> float:
	return _ap.get_animation(_key(_swing_clip)).length


func _key(clip: String) -> String:
	return "%s/%s" % [_clip_lib[clip], clip]


func _play(clip: String, blend: float) -> void:
	_clip = clip
	_ap.play(_key(clip), blend)
	_ap.speed_scale = 1.0


func _play_loop(clip: String, blend: float) -> void:
	if _clip != clip or not _ap.is_playing():
		_play(clip, blend)
