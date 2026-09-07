extends SceneTree
## 梯子下爬回归测试（headless）：
##   godot --headless -s res://test/test_ladder_bottom.gd
## 场景：地面 top=320；梯子顶端 y=135、height=190（底端 325，故意比地面深 5px）
## 玩家按住 ↓ 从梯子顶爬到底。
## 断言：落地站稳（is_on_floor）且脚底不越过地面线 2px 以上（不穿地）。

var _frames: int = 0
var _player: CharacterBody2D


func _initialize() -> void:
	print("== 梯子下爬回归测试 ==")
	_register_actions()

	# 地面：top=320
	var ground := StaticBody2D.new()
	var gcs := CollisionShape2D.new()
	var gsh := RectangleShape2D.new()
	gsh.size = Vector2(800, 60)
	gcs.shape = gsh
	ground.add_child(gcs)
	ground.position = Vector2(560, 350)
	root.add_child(ground)

	# 梯子：底端 325，故意超深 5px（验证代码层的底端对齐防护）
	var ladder: Area2D = (load("res://scenes/objects/ladder.tscn") as PackedScene).instantiate()
	ladder.position = Vector2(560, 135)
	ladder.height = 190.0
	root.add_child(ladder)

	# 真玩家
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.position = Vector2(560, 118)  # 梯子顶端上方，正对梯子
	root.add_child(_player)

	# 全程按住 ↓
	Input.action_press("move_down")


## 测试环境没有 Game autoload，需手动注册玩家用到的输入动作
func _register_actions() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_J],
		"jump_space": [KEY_SPACE],
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k: Key in actions[action]:
			var ev := InputEventKey.new()
			ev.keycode = k
			InputMap.action_add_event(action, ev)


func _process(_delta: float) -> bool:
	_frames += 1
	# headless 下 idle 帧率 ≠ 物理帧率，这里只看结果不看帧数：
	# 玩家落地站稳且脚底不越过地面线 2px 以上 → PASS
	if is_instance_valid(_player) and _player.is_on_floor():
		var feet: float = _player.global_position.y + 12.0
		var no_sink: bool = feet <= 322.0
		print("落地 脚底=%.1f（地面线=320，梯子底端故意超深5px）" % feet)
		if no_sink:
			print("TEST_PASS: 下爬到底正确落地，未穿地")
			quit(0)
		else:
			print("TEST_FAIL: 穿地 %.1fpx" % (feet - 320.0))
			quit(1)
		return true
	if _frames >= 1200:
		print("TEST_FAIL: 超时未落地 player=%s" % _player.global_position)
		quit(1)
		return true
	return false
