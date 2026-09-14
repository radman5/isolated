extends Node3D
# Fight bookkeeping for stage 2: start the clock, notice when someone dies, log
# the result, reset for the next go.
#
# Deliberately does NOT count hits taken or dodge successes, even though §5 asks
# for both. Every hit is already an event in the log with a timestamp, so those
# are a jq one-liner over a fight_start..fight_end window. Counting them twice
# would just create a second number that can disagree with the first.

@export var reset_delay := 1.2

var _t0 := 0.0
var _over := false
var _reset_in := 0.0

@onready var player: Node = $Player
@onready var enemy: Node = get_node_or_null("Enemy")


func _ready() -> void:
	_t0 = _now()
	Metrics.log_event("fight_start", {"stage": 2})


func _process(delta: float) -> void:
	if _over:
		_reset_in -= delta
		if _reset_in <= 0.0:
			get_tree().reload_current_scene()
		return

	var winner := ""
	if enemy and enemy.cs.dead():
		winner = "player"
	elif player.cs.dead():
		winner = "enemy"
	if winner == "":
		return

	_over = true
	_reset_in = reset_delay
	Metrics.log_event(
		"fight_end",
		{
			"winner": winner,
			# The §5 headline number.
			"time_to_kill": snappedf(_now() - _t0, 0.01),
			"player_hp_left": snappedf(player.cs.health, 0.1),
		}
	)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
