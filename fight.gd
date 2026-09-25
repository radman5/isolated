extends Node3D
# Fight bookkeeping: spawn the enemies, start the clock, notice when the fight is
# decided, log the result, reset for the next go.
#
# Deliberately does NOT count hits taken or dodge successes, even though §5 asks
# for both. Every hit is already an event in the log with a timestamp, so those
# are a jq one-liner over a fight_start..fight_end window. Counting them twice
# would just create a second number that can disagree with the first.
#
# The enemy count is a static so it survives the reload between fights. Changing
# it restarts the fight instead of adding enemies to one in progress, because a
# fight whose enemy count changed halfway through has a meaningless time_to_kill.

const EnemyScene := preload("res://enemy.tscn")
const MAX_ENEMIES := 8
const MAX_ARROWS := 7
# Spawn points, filled in order, all inside the fixed camera's frame.
const SLOTS := [
	Vector3(0, 0, -6), Vector3(-4, 0, -5), Vector3(4, 0, -5), Vector3(-6, 0, -1),
	Vector3(6, 0, -1), Vector3(-2, 0, -8), Vector3(2, 0, -8), Vector3(-7, 0, -5),
]

@export var reset_delay := 1.2
## What the enemy-count buttons spawn.
@export var enemy_scene: PackedScene = EnemyScene
## Off for a hand-built encounter: fight.gd uses the enemies already placed in the
## scene, and the enemy-count buttons are hidden.
@export var spawn_enemies := true
## Written to fight_start so logs from different demos can be told apart.
@export var stage := "2c"

static var enemy_count := 1

var _t0 := 0.0
var _over := false
var _reset_in := 0.0
var _arrow_label := Label.new()
var _hp_bar := ProgressBar.new()
var _down := 0
var _winner := ""

@onready var player: Node = $Player
## Killing every enemy ends the fight. Off for a route, where the exit ends it.
@export var clear_wins := true
## Reaching the exit only counts while carrying this item (e.g. "satchel").
@export var exit_needs := ""
## Optional. Reaching it ends the fight: "sneaked" if nothing woke, else "escaped".
@onready var _exit: Node3D = get_node_or_null("Exit")


func _ready() -> void:
	for i in (enemy_count if spawn_enemies else 0):
		var e := enemy_scene.instantiate()
		e.name = "Enemy%d" % (i + 1)
		e.position = SLOTS[i] + Vector3(0, 1.05, 0)
		add_child(e)
		# The arena is a straight fight: no sneaking up on anyone.
		e.wake("arena")
	_build_controls()
	_t0 = _now()
	Metrics.log_event("fight_start", {
		"stage": stage, "enemies": get_tree().get_nodes_in_group("enemies").size() if not spawn_enemies else enemy_count,
	})


func _process(delta: float) -> void:
	if _over:
		_reset_in -= delta
		if _reset_in <= 0.0:
			get_tree().reload_current_scene()
		return

	_hp_bar.value = player.cs.health
	var enemies := get_tree().get_nodes_in_group("enemies")
	# Stage 3: the health you carry into each next fight is the whole experiment.
	var down := enemies.filter(func(e): return e.cs.dead()).size()
	if down > _down:
		_down = down
		Metrics.log_event("enemy_down", {"cleared": down, "player_hp": snappedf(player.cs.health, 0.1)})
	var winner := ""
	if clear_wins and not enemies.is_empty() and enemies.all(func(e): return e.cs.dead()):
		winner = "player"
	elif player.cs.dead():
		winner = "enemy"
	elif _exit and (exit_needs == "" or player.carrying.has(exit_needs)) and Vector2(player.global_position.x - _exit.global_position.x, player.global_position.z - _exit.global_position.z).length() < 1.5:
		winner = "escaped" if enemies.any(func(e): return e.awake()) else "sneaked"
	if winner == "":
		return

	_over = true
	_winner = winner
	_reset_in = reset_delay
	Metrics.log_event(
		"fight_end",
		{
			"winner": winner,
			"enemies": enemies.size(),
			# The §5 headline number: time to clear every enemy.
			"time_to_kill": snappedf(_now() - _t0, 0.01),
			"player_hp_left": snappedf(player.cs.health, 0.1),
			# On a death, the corridor position it happened at is cleared + 1.
			"cleared": _down,
			"alerted": enemies.filter(func(e): return e.awake()).size(),
		}
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_MINUS, KEY_KP_SUBTRACT:
			if spawn_enemies:
				_change_enemies(-1)
		KEY_EQUAL, KEY_KP_ADD:
			if spawn_enemies:
				_change_enemies(1)
		KEY_BRACKETLEFT:
			_change_arrows(-1)
		KEY_BRACKETRIGHT:
			_change_arrows(1)


func _change_enemies(d: int) -> void:
	var n := clampi(enemy_count + d, 0, MAX_ENEMIES)
	if n == enemy_count:
		return
	enemy_count = n
	Metrics.log_event("enemies_changed", {"count": n})
	get_tree().reload_current_scene.call_deferred()


# Arrows change live: a volley size is not a property of the fight, so there is
# nothing to restart.
func _change_arrows(d: int) -> void:
	var n := clampi(player.arrow_count + d, 1, MAX_ARROWS)
	if n == player.arrow_count:
		return
	player.arrow_count = n
	_arrow_label.text = "  arrows %d  " % n
	Metrics.log_event("arrows_changed", {"count": n})


func _build_controls() -> void:
	# Started from the menu's Start button: a player, not a tuner. No debug text.
	if DemoMenu.playing:
		for n in ["HUD/Label", "DebugDraw"]:
			var d := get_node_or_null(n)
			if d:
				d.queue_free()
	var rows := VBoxContainer.new()
	rows.anchor_left = 1.0
	rows.anchor_right = 1.0
	rows.offset_left = -260.0
	rows.offset_right = -12.0
	rows.offset_top = 8.0
	if spawn_enemies:
		var enemy_label := Label.new()
		enemy_label.text = "  enemies %d  " % enemy_count
		rows.add_child(_row(enemy_label, _change_enemies))
	_arrow_label.text = "  arrows %d  " % player.arrow_count
	rows.add_child(_row(_arrow_label, _change_arrows))
	if DemoMenu.playing:
		rows.queue_free()
	else:
		$HUD.add_child(rows)
	# ponytail: stock ProgressBar. §3 rules out an attractive one; this one is for reading.
	_hp_bar.max_value = player.cs.health_max
	_hp_bar.show_percentage = false
	_hp_bar.modulate = Color(0.9, 0.25, 0.2)
	_hp_bar.anchor_top = 1.0
	_hp_bar.anchor_bottom = 1.0
	_hp_bar.offset_left = 12.0
	_hp_bar.offset_right = 312.0
	_hp_bar.offset_top = -36.0
	_hp_bar.offset_bottom = -12.0
	$HUD.add_child(_hp_bar)


func _row(label: Label, change: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_button("  −  ", change.bind(-1)))
	box.add_child(label)
	box.add_child(_button("  +  ", change.bind(1)))
	return box


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# Never take focus. A focused Button activates on ui_accept, and Space is dodge.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
