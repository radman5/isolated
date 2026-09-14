extends Node
# Stage-1 instrumentation (test plan §5). One JSON object per line.
#
# The seam for every later stage is this call and nothing else:
#     Metrics.log_event("hit_taken", {"enemy": 1, "hp": 40})
#
# NOT logged yet, because stage 1 has no enemy to log them against: time-to-kill,
# hits taken, dodge successes, deaths by corridor position. Adding null fields
# for them now would put numbers in the log that get trusted at verdict time.
#
# Stage lives on fight_start only (fight.gd), never here: two places to record
# it is two places to disagree.
#
# ponytail: no aggregation, no summary, no schema. jq reads it at stage 5.

# The A/B's load-bearing field: every log line has to be attributable to a
# build. One word, so `git diff main..stage2b-gesture -- metrics.gd` is the
# whole proof. Do not derive it from file existence - that is cleverness
# someone decodes at 3am.
const INPUT_MODE := "gesture"

var _f: FileAccess
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Headless runs (check.gd) would otherwise write a session file each time and
	# inflate the session count, which is the metric the whole test hinges on.
	if DisplayServer.get_name() == "headless":
		return
	_t0 = Time.get_ticks_msec()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://run_%s.jsonl" % stamp
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		push_warning("metrics: could not open %s - logging disabled" % path)
	else:
		print("metrics -> ", ProjectSettings.globalize_path(path))
	log_event("session_start", {"input_mode": INPUT_MODE})


func log_event(ev: String, data: Dictionary = {}) -> void:
	if _f == null:
		return
	data["t"] = (Time.get_ticks_msec() - _t0) / 1000.0
	data["ev"] = ev
	_f.store_line(JSON.stringify(data))
	_f.flush()  # this prototype gets force-quit a lot


func _exit_tree() -> void:
	log_event("session_end")
	if _f:
		_f.close()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_camera_blame"):
		log_event("camera_blame")
		print("camera blamed")  # so you know the keypress registered
	elif e.is_action_pressed("debug_restart"):
		log_event("restart")
		get_tree().reload_current_scene()
