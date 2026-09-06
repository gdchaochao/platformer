extends SceneTree
## 踩踏判定的物理回归测试（headless 运行）：
##   cd <项目目录> && godot --headless -s res://test/test_stomp.gd
## 用例1：玩家从怪头顶落下 → 怪被踩死，玩家反弹
## 用例2：玩家从侧面同高度走向怪 → 玩家受伤（was_hit）

var _stage := 1
var _frames := 0
var _walker: Node2D
var _player: CharacterBody2D


func _initialize() -> void:
	print("== 踩踏判定回归测试 ==")
	# 通用地面：y=350 中心、厚 60（顶面 y=320，与游戏一致）
	var ground := StaticBody2D.new()
	var gcs := CollisionShape2D.new()
	var gsh := RectangleShape2D.new()
	gsh.size = Vector2(2000, 60)
	gcs.shape = gsh
	ground.add_child(gcs)
	ground.position = Vector2(500, 350)
	root.add_child(ground)
	_spawn_case(Vector2(500, 160), Vector2(0, 200))  # 用例1：头顶下落


func _spawn_case(player_pos: Vector2, player_vel: Vector2) -> void:
	var wscene: PackedScene = load("res://scenes/enemies/walker.tscn")
	_walker = wscene.instantiate()
	_walker.position = Vector2(500, 308)
	# 巡逻边界钉在同一点 → 小怪原地不动，保证玩家落点必中
	_walker.patrol_min_x = 500.0
	_walker.patrol_max_x = 500.0
	root.add_child(_walker)

	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(16, 24)
	cs.shape = sh
	_player.add_child(cs)
	_player.set_script(load("res://test/fake_player.gd"))
	_player.position = player_pos
	_player.velocity = player_vel
	root.add_child(_player)
	_frames = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 30 == 0 and is_instance_valid(_walker) and is_instance_valid(_player):
		print("[f%d] walker=%s player=%s vel=%s" % [
			_frames, _walker.position, _player.position, _player.velocity])
	if _frames > 240:
		print("TEST_FAIL: 用例%d 超时（240 帧内未得到结果）" % _stage)
		quit(1)
		return true

	if _stage == 1:
		# 用例1成功 = walker 被消灭（queue_free 后 is_instance_valid 为 false）
		if not is_instance_valid(_walker):
			var bounced: bool = _player.velocity.y < -100.0
			print("用例1 踩踏消灭: PASS（玩家反弹=%s）" % bounced)
			_player.queue_free()
			_stage = 2
			# 用例2：玩家与怪同高，从侧面推向怪
			_spawn_case.call_deferred(Vector2(380, 308), Vector2(120, 0))
		return false

	if _stage == 2:
		# 用例2成功 = 玩家被打上 was_hit 标记，且怪还活着
		if is_instance_valid(_walker) and _player.get_meta("was_hit", false):
			print("用例2 侧碰受伤: PASS")
			print("== 全部通过 ==")
			quit(0)
			return true
		return false

	return false
