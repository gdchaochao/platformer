extends Node
## Replay runner: plays back a recorded per-frame input sequence in REAL TIME
## (unpaused), so the level can be rendered / recorded to video.
##
## Env:
##   PF_REPLAY = path to JSON: a list of input dicts, one per physics frame
##               e.g. [{"right":true}, {"right":true,"jump":true}, {}, ...]
##   PF_LEVEL  = scene path (default level_1_1)
##
## Used with Godot Movie Maker mode:
##   PF_REPLAY=/tmp/run.json PF_LEVEL=res://scenes/levels/level_1_1.tscn \
##     godot --path . --write-movie /tmp/out.avi --fixed-fps 60 \
##     res://agent/replay_runner.tscn

const DEFAULT_LEVEL := "res://scenes/levels/level_1_1.tscn"
const CTRL_ACTIONS := {
	"left": ["move_left"],
	"right": ["move_right"],
	"jump": ["jump", "jump_space"],
	"up": ["move_up"],
	"down": ["move_down"],
}
const TAIL_FRAMES := 150  # linger after the last input frame, then quit
const WIN_LINGER := 78     # frames to show the win banner before quitting (~1.3s)

var _frames: Array = []
var _i: int = 0
var _tail: int = 0
var _win_tail: int = -1
var _pressed: Dictionary = {}
var _player: CharacterBody2D = null
var _level: Node = null


func _ready() -> void:
	var rf := OS.get_environment("PF_REPLAY")
	if rf != "":
		var f := FileAccess.open(rf, FileAccess.READ)
		if f:
			_frames = JSON.parse_string(f.get_as_text())
			f.close()
	var lvl := OS.get_environment("PF_LEVEL")
	if lvl == "":
		lvl = DEFAULT_LEVEL
	add_child(load(lvl).instantiate())
	_level = get_child(get_child_count() - 1)
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		_player = ps[0] as CharacterBody2D
		_player.hold_to_auto_jump = false
	print("replay: %d frames to play" % _frames.size())


func _physics_process(_delta: float) -> void:
	# Once the level is won, hold the frame for a moment (so the win banner is
	# visible) and then quit BEFORE the level auto-advances to the next scene
	# (which would destroy this node and the recording would never stop).
	if _level and bool(_level.get("_won")):
		_apply({})
		if _win_tail < 0:
			_win_tail = 0
		_win_tail += 1
		if _win_tail > WIN_LINGER:
			get_tree().quit()
		return
	if _i < _frames.size():
		_apply(_frames[_i])
		_i += 1
	elif _i == _frames.size():
		_apply({})       # release everything
		_i += 1
	else:
		_tail += 1
		if _tail > TAIL_FRAMES:
			get_tree().quit()


func _apply(input: Dictionary) -> void:
	for dim: String in CTRL_ACTIONS.keys():
		var want: bool = bool(input.get(dim, false))
		if want == bool(_pressed.get(dim, false)):
			continue
		_pressed[dim] = want
		for a: String in CTRL_ACTIONS[dim]:
			if want:
				Input.action_press(a)
			else:
				Input.action_release(a)
