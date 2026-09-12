extends SceneTree
## 敌人交互判定的物理回归测试（headless 运行）：
##   cd <项目目录> && godot --headless -s res://test/test_stomp.gd
## 覆盖 walker / hopper / flyer 三种敌人的头顶踩死与侧碰受伤。

const CASES := [
	{
		"name": "用例1 walker头顶踩死", "enemy": "res://scenes/enemies/walker.tscn", "expect": "stomp",
		"player_pos": Vector2(500, 160), "player_vel": Vector2(0, 200),
		"enemy_pos": Vector2(500, 308), "patrol": Vector2(500, 500), "amp": 0.0,
	},
	{
		"name": "用例2 walker侧碰受伤", "enemy": "res://scenes/enemies/walker.tscn", "expect": "hit",
		"player_pos": Vector2(380, 308), "player_vel": Vector2(120, 0),
		"enemy_pos": Vector2(500, 308), "patrol": Vector2(500, 500), "amp": 0.0,
	},
	{
		"name": "用例3 hopper头顶踩死", "enemy": "res://scenes/enemies/hopper.tscn", "expect": "stomp",
		"player_pos": Vector2(500, 160), "player_vel": Vector2(0, 200),
		"enemy_pos": Vector2(500, 308), "patrol": Vector2(500, 500), "amp": 0.0,
	},
	{
		"name": "用例4 flyer头顶踩死", "enemy": "res://scenes/enemies/flyer.tscn", "expect": "stomp",
		"player_pos": Vector2(500, 100), "player_vel": Vector2(0, 200),
		"enemy_pos": Vector2(500, 250), "patrol": Vector2(500, 500), "amp": 0.0,
	},
]

var _case_idx := 0
var _frames := 0
var _enemy: Node2D
var _player: CharacterBody2D


func _initialize() -> void:
	print("== 敌人交互判定回归测试 ==")
	# 通用地面：顶面 y=320，与游戏一致
	var ground := StaticBody2D.new()
	var gcs := CollisionShape2D.new()
	var gsh := RectangleShape2D.new()
	gsh.size = Vector2(2000, 60)
	gcs.shape = gsh
	ground.add_child(gcs)
	ground.position = Vector2(500, 350)
	root.add_child(ground)
	_start_case.call_deferred(0)


func _start_case(idx: int) -> void:
	_case_idx = idx
	_frames = 0
	var c: Dictionary = CASES[idx]

	var escene: PackedScene = load(c["enemy"])
	_enemy = escene.instantiate()
	_enemy.position = c["enemy_pos"]
	if "patrol_min_x" in _enemy:
		_enemy.patrol_min_x = (c["patrol"] as Vector2).x
		_enemy.patrol_max_x = (c["patrol"] as Vector2).y
	if "float_amplitude" in _enemy:
		_enemy.float_amplitude = c["amp"]
	root.add_child(_enemy)

	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(16, 24)
	cs.shape = sh
	_player.add_child(cs)
	_player.set_script(load("res://test/fake_player.gd"))
	_player.position = c["player_pos"]
	_player.velocity = c["player_vel"]
	root.add_child(_player)


func _process(_delta: float) -> bool:
	_frames += 1
	var c: Dictionary = CASES[_case_idx]
	if _frames > 240:
		print("TEST_FAIL: %s 超时（240 帧内未得到结果）" % c["name"])
		quit(1)
		return true

	var enemy_alive: bool = is_instance_valid(_enemy)
	if c["expect"] == "stomp" and not enemy_alive:
		var bounced: bool = is_instance_valid(_player) and _player.velocity.y < -100.0
		print("%s: PASS（玩家反弹=%s）" % [c["name"], bounced])
		_next_case()
		return false
	if c["expect"] == "hit" and enemy_alive and is_instance_valid(_player) \
			and _player.get_meta("was_hit", false):
		print("%s: PASS" % c["name"])
		_next_case()
		return false
	return false


func _next_case() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	var idx: int = _case_idx + 1
	if idx < CASES.size():
		_start_case.call_deferred(idx)
	else:
		print("== 全部通过 ==")
		quit(0)
