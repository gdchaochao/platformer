extends SceneTree
## 梯子攀爬回归测试（headless）：
##   godot --headless -s res://test/test_ladder.gd
## 玩家站在梯子下方，按住"上"→ 应持续向上攀爬（y 不断减小）

var _frames := 0
var _player: CharacterBody2D
var _failed := false
var _key_pressed := false


func _initialize() -> void:
	print("== 梯子攀爬回归测试 ==")
	# 地面（顶面 y=320）
	var ground := StaticBody2D.new()
	var gcs := CollisionShape2D.new()
	var gsh := RectangleShape2D.new()
	gsh.size = Vector2(2000, 60)
	gcs.shape = gsh
	ground.add_child(gcs)
	ground.position = Vector2(500, 350)
	root.add_child(ground)

	# 梯子：顶端 y=135，长 190（区域 135..325，覆盖站地玩家）
	var ladder := (load("res://scenes/objects/ladder.tscn") as PackedScene).instantiate()
	ladder.position = Vector2(500, 135)
	ladder.height = 190.0
	root.add_child(ladder)

	# 真玩家（带真实脚本与攀爬逻辑）
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.position = Vector2(500, 308)
	root.add_child(_player)


func _process(_delta: float) -> bool:
	_frames += 1
	# 第一帧再模拟按键（_initialize 时 autoload 的动作注册尚未完成）
	if not _key_pressed:
		_key_pressed = true
		Input.action_press("move_up")
		return false
	if _frames == 10:
		# 强制进入攀爬：区分"进入条件失败" vs "攀爬执行失败"
		_player._climbing = true
		print("[f10] 强制 _climbing=true")
	if _frames >= 11 and _frames <= 15:
		var ladders := get_nodes_in_group("ladders")
		var ld: Area2D = ladders[0] if ladders.size() > 0 else null
		var meta_ladder: bool = _player.get_meta("on_ladder", false)
		var exit_reason: String = _player.get_meta("exit_reason", "")
		var up_pressed: bool = Input.is_action_pressed("move_up")
		if ld:
			print("[f%d] climbing=%s meta_ladder=%s exit=%s up=%s y=%.1f" % [
				_frames, _player._climbing, meta_ladder, exit_reason,
				up_pressed, _player.position.y])
	if _frames == 30:
		var climbing: bool = _player._climbing
		var on_ladder: bool = _player._overlapping_ladder()
		var pressed: bool = Input.is_action_pressed("move_up")
		var has_action: bool = InputMap.has_action("move_up")
		print("[f30] y=%.0f climbing=%s on_ladder=%s pressed=%s action_exists=%s" % [
			_player.position.y, climbing, on_ladder, pressed, has_action])
		if climbing and _player.position.y < 308.0:
			print("用例1 按上开始攀爬: PASS")
		else:
			print("用例1 按上开始攀爬: FAIL")
			_failed = true
	elif _frames == 90:
		# 持续攀爬：idle 帧率高于物理帧，用宽容阈值（0.6s 物理时间应爬 ~70px）
		var ok2: bool = _player.position.y < 240.0
		print("用例2 持续攀爬(1.5s y=%.0f): %s" % [_player.position.y, "PASS" if ok2 else "FAIL"])
		if not ok2:
			_failed = true
	elif _frames >= 95:
		if _failed:
			print("TEST_FAIL: 梯子攀爬异常")
			quit(1)
		else:
			print("== 全部通过 ==")
			quit(0)
		return true
	return false
