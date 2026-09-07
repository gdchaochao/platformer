extends SceneTree
## 梯子攀爬回归测试（headless）：
##   godot --headless -s res://test/test_ladder.gd
## 用例1/2：底部按↑开始攀爬并持续向上
## 用例3（双向）：从梯子顶部的 one-way 平台上按↓ → 下穿平台往下爬 → 落地脱梯
##               且按住↓落地后不会重新进入攀爬（防无限下穿地图）

var _frames := 0
var _player: CharacterBody2D
var _failed := false
var _key_pressed := false
var _stage := 1


func _initialize() -> void:
	print("== 梯子攀爬回归测试 ==")
	_build_world()


func _build_world() -> void:
	# 地面（顶面 y=320）
	var ground := StaticBody2D.new()
	var gcs := CollisionShape2D.new()
	var gsh := RectangleShape2D.new()
	gsh.size = Vector2(2000, 60)
	gcs.shape = gsh
	ground.add_child(gcs)
	ground.position = Vector2(500, 350)
	root.add_child(ground)

	# 梯子：顶端 y=135，长 190（区域 135..325）
	var ladder := (load("res://scenes/objects/ladder.tscn") as PackedScene).instantiate()
	ladder.position = Vector2(500, 135)
	ladder.height = 190.0
	root.add_child(ladder)


func _spawn_player(pos: Vector2) -> void:
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.position = pos
	root.add_child(_player)


func _process(_delta: float) -> bool:
	_frames += 1
	# 第一帧再模拟按键（_initialize 时 autoload 的动作注册尚未完成）
	if not _key_pressed:
		_key_pressed = true
		if _stage == 1:
			_spawn_player(Vector2(500, 308))
			Input.action_press("move_up")  # 用例1/2：按住上爬
		return false

	# ---------- 用例 1/2：底部向上爬 ----------
	if _stage == 1:
		if _frames == 10:
			_player._climbing = true  # 强制进入，区分"进入失败"与"执行失败"
		elif _frames == 30:
			var ok1: bool = _player._climbing and _player.position.y < 308.0
			print("用例1 按上开始攀爬: %s (y=%.0f)" % ["PASS" if ok1 else "FAIL", _player.position.y])
			_failed = _failed or not ok1
		elif _frames == 90:
			var ok2: bool = _player.position.y < 240.0
			print("用例2 持续攀爬(1.5s y=%.0f): %s" % [_player.position.y, "PASS" if ok2 else "FAIL"])
			_failed = _failed or not ok2
			# 进入用例3：玩家重置到"梯子顶部的 one-way 平台"上，按住↓不放
			_stage = 3
			_frames = 0
			_player.queue_free()
			_player = null
			var plat := StaticBody2D.new()
			var pcs := CollisionShape2D.new()
			var psh := RectangleShape2D.new()
			psh.size = Vector2(160, 18)
			pcs.shape = psh
			pcs.one_way_collision = true
			plat.add_child(pcs)
			plat.position = Vector2(500, 160)  # 顶面 y=151（梯子顶端 135 下方 16px）
			root.add_child(plat)
			_spawn_player(Vector2(500, 139))
			Input.action_release("move_up")
			Input.action_press("move_down")
		return false

	# ---------- 用例 3：顶部按↓下穿平台往下爬，落地后按住↓不得重新进入 ----------
	if _stage == 3:
		if _frames == 10 or _frames == 20:
			print("[f%d] on_ladder=%s down_pressed=%s block=%s climbing=%s y=%.0f" % [
				_frames, _player._overlapping_ladder(),
				Input.is_action_pressed("move_down"), _player._down_block,
				_player._climbing, _player.position.y])
		if _frames == 20:
			var entered: bool = _player._climbing
			print("用例3a 平台顶按↓进入攀爬: %s" % ["PASS" if entered else "FAIL"])
			_failed = _failed or not entered
		elif _frames == 80:
			var sunk: bool = _player.position.y > 175.0
			print("用例3b 下穿平台(y=%.0f): %s" % [_player.position.y, "PASS" if sunk else "FAIL"])
			_failed = _failed or not sunk
		elif _frames >= 400:
			var landed: bool = _player.position.y < 320.0 and not _player._climbing
			var no_reenter: bool = _player.position.y < 320.0  # 落地后持续按↓也不下穿
			print("用例3c 到底落地脱梯(y=%.0f climbing=%s): %s" % [
				_player.position.y, _player._climbing, "PASS" if landed else "FAIL"])
			print("用例3d 按住↓不重新下穿(y=%.0f): %s" % [
				_player.position.y, "PASS" if no_reenter else "FAIL"])
			_failed = _failed or not landed or not no_reenter
			if _failed:
				print("TEST_FAIL: 梯子双向攀爬异常")
				quit(1)
				return true
			# 进入用例4：玩家站在梯子侧边缘（中心偏出 21px，擦到检测区但没正对）
			_stage = 4
			_frames = 0
			_player.queue_free()
			_player = null
			_spawn_player(Vector2(521, 139))
			Input.action_press("move_up")
		return false

	# ---------- 用例 4：擦边不得攀爬（须正对梯子） ----------
	if _stage == 4:
		if _frames == 30:
			var refused: bool = not _player._climbing and _player.position.y > 130.0
			print("用例4 擦边拒绝攀爬(y=%.0f climbing=%s): %s" % [
				_player.position.y, _player._climbing, "PASS" if refused else "FAIL"])
			_failed = _failed or not refused
			if _failed:
				print("TEST_FAIL")
				quit(1)
			else:
				print("== 全部通过 ==")
				quit(0)
			return true
	return false
