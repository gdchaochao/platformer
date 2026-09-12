extends CharacterBody2D
## 跳跳怪（苔藓蛙）：
## - 状态机：落地蹲伏（rest_time 蓄力，视觉压扁）→ 朝玩家方向蹦跳 → 空中 → 落地
## - 玩家在 sense_range 内才追着跳，否则原地小跳
## - 玩家从头顶踩到 → 消灭 + 反弹；侧面碰到 → 玩家受伤（几何判定同 walker）
## - 巡逻边界钳制：蹦出 patrol_min_x / patrol_max_x 会被拉回

@export var hop_vx: float = 130.0         # 蹦跳水平速度
@export var hop_vy: float = -400.0        # 蹦跳垂直初速
@export var rest_time: float = 0.9        # 落地后蹲伏时长
@export var sense_range: float = 320.0    # 感知玩家距离（超出则原地小跳）
@export var patrol_min_x: float = 0.0     # 活动左边界（世界坐标）
@export var patrol_max_x: float = 1e9     # 活动右边界

# 判定参数（与 walker 同款标定）
const HALF_W := 22.0
const STOMP_TOP := -20.0
const STOMP_BOTTOM := 8.0
const HIT_DY := 22.0

var _rest: float = 1.2  # 开局先多蹲一会，给玩家接近的时间
var _airborne: bool = false

@onready var _body_vis: Node2D = $BodyVis


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
		_airborne = true
		# 空中保持水平速度，身体逐渐回正
		_body_vis.scale = _body_vis.scale.lerp(Vector2.ONE, 6.0 * delta)
	else:
		if _airborne:
			_airborne = false
			_squash()  # 落地压扁反馈
		velocity.x = 0.0
		_rest -= delta
		if _rest <= 0.0:
			_hop()

	move_and_slide()

	# 活动边界钳制（直接夹位置，防止蹦出巡逻区）
	if global_position.x < patrol_min_x:
		global_position.x = patrol_min_x
	elif global_position.x > patrol_max_x:
		global_position.x = patrol_max_x

	_interact_players()


func _hop() -> void:
	_rest = rest_time
	var dir := 1.0
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p := players[0] as Node2D
		var dx: float = p.global_position.x - global_position.x
		if absf(dx) > 4.0 and absf(dx) <= sense_range:
			dir = signf(dx)
		elif absf(dx) <= 4.0:
			dir = [-1.0, 1.0].pick_random()  # 玩家正好在头顶：随机方向蹦开
	velocity = Vector2(dir * hop_vx, hop_vy)
	# 起跳拉伸
	_body_vis.scale = Vector2(0.82, 1.22)


## 落地压扁（juice）
func _squash() -> void:
	_body_vis.scale = Vector2(1.18, 0.8)
	var tw := create_tween()
	tw.tween_property(_body_vis, "scale", Vector2.ONE, 0.12)


func _interact_players() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var body := p as Node2D
		if body == null:
			continue
		var dx: float = absf(body.global_position.x - global_position.x)
		if dx > HALF_W:
			continue
		var dy: float = body.global_position.y - global_position.y
		var feet: float = dy + 12.0
		if body is CharacterBody2D and (body as CharacterBody2D).velocity.y < -10.0:
			continue  # 正在上升：本帧不判定
		if feet > STOMP_TOP and feet < STOMP_BOTTOM:
			Game.play_sfx("stomp")
			if body.has_method("bounce"):
				body.bounce()
			queue_free()
			return
		if absf(dy) < HIT_DY and body.has_method("take_hit"):
			body.take_hit()
