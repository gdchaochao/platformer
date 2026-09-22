extends Node
## Agent harness for Forest Kingdom Platformer.
##
## Purpose: expose a *step-based control interface* so an external "brain"
## (e.g. the JEV decisions model) can play the game one decision at a time,
## fully decoupled from real time.
##
## How it works
##   - The world is PAUSED between decisions. Nothing moves until the brain
##     asks for a step, so the model's network latency does not matter.
##   - A "step" = advance exactly N physics frames with a chosen input state.
##   - We NEVER touch the game logic: input is injected by toggling the same
##     InputMap actions a human would use (Input.action_press/release).
##
## Protocol (one JSON per line). Our lines are prefixed with "@@".
##   Godot -> brain:
##     @@{"type":"hello", ...}                 # once, on startup (world map)
##     @@{"type":"state", ...}                 # after every step
##     @@{"type":"bye"}
##   brain -> Godot:
##     {"cmd":"step","frames":9,"input":{"left":false,"right":true,"jump":false,"up":false,"down":false}}
##     {"cmd":"state"}
##     {"cmd":"quit"}
##
## Launch:
##   PF_LEVEL=res://scenes/levels/level_1_1.tscn \
##     godot --headless --path . res://agent/agent_runner.tscn

const DEFAULT_LEVEL := "res://scenes/levels/level_1_1.tscn"

## Control dimension -> InputMap actions it drives. We toggle action state
## directly (Input.action_press/release) instead of synthesizing key events:
## synthetic key events proved flaky under pause (a held key was seen as
## released after one frame, killing variable jump height).
const CTRL_ACTIONS := {
	"left": ["move_left"],
	"right": ["move_right"],
	"jump": ["jump", "jump_space"],
	"up": ["move_up"],
	"down": ["move_down"],
}

var level: Node = null
var _player: CharacterBody2D = null

var _tick: int = 0
var _sim_time: float = 0.0
var _pressed: Dictionary = {}
var _level_path: String = ""

# stdin reader (blocking read lives on a thread; commands land in _lines)
var _lines: Array = []
var _mutex := Mutex.new()
var _stdin_eof := false
var _stdin_thread: Thread = null
var _quit := false

# deterministic stepping: a counter node (this one) has a HIGHER process
# priority than the player, so it runs AFTER the player each physics frame;
# it re-pauses the tree on the exact frame the requested count is reached.
var _stepping := false
var _frames_done := 0
var _frames_want := 0


func _physics_process(_delta: float) -> void:
	if not _stepping:
		return
	# NB: priority 100 -> runs after the player/enemies this frame, so the
	# frame we pause on has already been simulated exactly once.
	_frames_done += 1
	if _frames_done > _frames_want:
		_stepping = false
		get_tree().paused = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100  # run after the player/enemies within a physics frame
	_level_path = OS.get_environment("PF_LEVEL")
	if _level_path == "":
		_level_path = DEFAULT_LEVEL

	# Freeze the world immediately: we advance it manually, one step at a time.
	get_tree().paused = true

	var packed: PackedScene = load(_level_path)
	if packed == null:
		_send({"type": "error", "msg": "cannot load level: %s" % _level_path})
		get_tree().quit(1)
		return
	level = packed.instantiate()
	add_child(level)
	# The runner itself is PROCESS_MODE_ALWAYS (so it keeps ticking while the
	# world is frozen), but the world must stay pausable -- otherwise it would
	# inherit ALWAYS and keep simulating in real time between our steps.
	level.process_mode = Node.PROCESS_MODE_PAUSABLE

	_refresh_player()
	# Agent mode: disable "hold jump to auto-rejump". The reflex/executor layer
	# must control exactly when jumps happen; auto-rejump makes landings fire
	# an unintended second jump (this broke precise platform hops).
	if is_instance_valid(_player):
		_player.hold_to_auto_jump = false
	_send({
		"type": "hello",
		"level": _level_path,
		"name": Game.display_name(_level_path),
		"fps": Engine.physics_ticks_per_second,
		"controls": CTRL_ACTIONS.keys(),
		"platforms": _collect_solid_aabbs(),
		"goal": _goal_state(),
		"spawn": {"x": _spawn_pos().x, "y": _spawn_pos().y},
		"killzone_top_y": _killzone_top_y(),
	})
	_start_stdin()
	_run_loop()


# ---------------------------------------------------------------- main loop

func _run_loop() -> void:
	while not _quit:
		var line: Variant = await _next_line()
		if line == null:
			break
		var cmd: Variant = JSON.parse_string(line)
		if typeof(cmd) != TYPE_DICTIONARY:
			continue
		match str(cmd.get("cmd", "")):
			"step":
				await _do_step(int(cmd.get("frames", 9)), cmd.get("input", {}))
			"state":
				_send_state()
			"quit":
				_quit = true
	_finish()


func _do_step(frames: int, input: Dictionary) -> void:
	_apply_input(input)
	if frames > 0:
		_frames_want = frames
		_frames_done = 0
		_stepping = true
		get_tree().paused = false
		while _stepping:
			await get_tree().process_frame
		_tick += frames
		_sim_time += float(frames) / float(Engine.physics_ticks_per_second)
	_refresh_player()
	_send_state()


func _finish() -> void:
	_send({"type": "bye"})
	get_tree().paused = false
	get_tree().quit(0)


# ---------------------------------------------------------------- input

func _apply_input(input: Dictionary) -> void:
	for dim: String in CTRL_ACTIONS.keys():
		var want: bool = bool(input.get(dim, false))
		if want == bool(_pressed.get(dim, false)):
			continue
		_pressed[dim] = want
		for action: String in CTRL_ACTIONS[dim]:
			if want:
				Input.action_press(action)
			else:
				Input.action_release(action)


# ---------------------------------------------------------------- stdin

func _start_stdin() -> void:
	_stdin_thread = Thread.new()
	_stdin_thread.start(_stdin_loop)


func _stdin_loop() -> void:
	while true:
		var line := OS.read_string_from_stdin()
		if line == "":
			_mutex.lock()
			_stdin_eof = true
			_mutex.unlock()
			return
		_mutex.lock()
		_lines.append(line)
		_mutex.unlock()


func _next_line() -> Variant:
	while true:
		_mutex.lock()
		if _lines.size() > 0:
			var l: Variant = _lines.pop_front()
			_mutex.unlock()
			return l
		var eof: bool = _stdin_eof
		_mutex.unlock()
		if eof:
			return null
		await get_tree().process_frame
	return null


# ---------------------------------------------------------------- state

func _send(d: Dictionary) -> void:
	printraw("@@" + JSON.stringify(d) + "\n")


func _send_state() -> void:
	_send(_build_state())


func _build_state() -> Dictionary:
	var s: Dictionary = {
		"type": "state",
		"tick": _tick,
		"pframes": Engine.get_physics_frames(),
		"time": snappedf(_sim_time, 0.001),
		"lives": Game.lives,
		"coins": Game.coins,
		"gems": Game.gems,
		"won": bool(level.get("_won")),
		"game_over": Game.is_game_over,
	}
	if is_instance_valid(_player):
		s["player"] = {
			"x": snappedf(_player.global_position.x, 0.1),
			"y": snappedf(_player.global_position.y, 0.1),
			"vx": snappedf(_player.velocity.x, 0.1),
			"vy": snappedf(_player.velocity.y, 0.1),
			"on_floor": _player.is_on_floor(),
			"climbing": bool(_player.get("_climbing")),
		}
	# goal
	var g: Dictionary = _goal_state()
	if not g.is_empty():
		s["goal"] = g
	# enemies
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			enemies.append({"x": snappedf(e.global_position.x, 0.1), "y": snappedf(e.global_position.y, 0.1)})
	s["enemies"] = enemies
	# hazards (spikes)
	var hazards: Array = []
	for h in get_tree().get_nodes_in_group("hazard"):
		var a: Dictionary = _area_aabb(h)
		if not a.is_empty():
			hazards.append(a)
	s["hazards"] = hazards
	s["killzone_top_y"] = _killzone_top_y()
	return s


# ---------------------------------------------------------------- world introspection

func _refresh_player() -> void:
	var ps: Array = get_tree().get_nodes_in_group("player")
	_player = ps[0] as CharacterBody2D if ps.size() > 0 else null


func _goal_state() -> Dictionary:
	for g in get_tree().get_nodes_in_group("goal"):
		return {"x": snappedf(g.global_position.x, 0.1), "y": snappedf(g.global_position.y, 0.1)}
	return {}


func _spawn_pos() -> Vector2:
	if level and level.has_node("Spawn"):
		return (level.get_node("Spawn") as Node2D).global_position
	return Vector2.ZERO


func _killzone_top_y() -> float:
	var top: float = 1e9
	for k in get_tree().get_nodes_in_group("killzone"):
		var a: Dictionary = _area_aabb(k)
		if not a.is_empty():
			top = minf(top, float(a["y"]))
	return top


func _collect_solid_aabbs() -> Array:
	var out: Array = []
	for n in level.find_children("*", "StaticBody2D", true, false):
		var a: Dictionary = _node_aabb(n)
		if not a.is_empty():
			out.append(a)
	# stable order by x
	out.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	return out


func _area_aabb(a: Node) -> Dictionary:
	return _node_aabb(a)


## AABB of a body/area from its RectangleShape2D collision shapes (world space).
func _node_aabb(b: Node2D) -> Dictionary:
	var minp := Vector2(1e18, 1e18)
	var maxp := Vector2(-1e18, -1e18)
	var found := false
	for c in b.get_children():
		if c is CollisionShape2D:
			var cs := c as CollisionShape2D
			if cs.shape is RectangleShape2D:
				var hs: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
				var t := cs.global_transform
				for corner in [Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(-hs.x, hs.y), Vector2(hs.x, hs.y)]:
					var wp: Vector2 = t * corner
					minp = minp.min(wp)
					maxp = maxp.max(wp)
					found = true
	if not found:
		return {}
	return {
		"x": snappedf(minp.x, 0.1), "y": snappedf(minp.y, 0.1),
		"w": snappedf(maxp.x - minp.x, 0.1), "h": snappedf(maxp.y - minp.y, 0.1),
	}
