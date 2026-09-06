extends CharacterBody2D
## 巡逻小怪（森林刺球怪）：
## - 沿平台左右巡逻，碰墙 / 悬崖边缘 / 巡逻边界自动掉头
## - 玩家从头顶踩到 → 小怪被消灭，玩家反弹
## - 侧面/下方碰到玩家 → 玩家受伤（走 take_hit 无敌帧逻辑）
##
## 交互用"每帧几何判定"而不是 Area2D 事件/重叠查询：
## 玩家踩上来时会站在 body 碰撞体顶部，比 Hurtbox 检测区还高，
## 区域检测存在盲区且事件触发时机依赖 velocity（已被踩塌过两次）。

@export var speed: float = 60.0          # 巡逻速度
@export var patrol_min_x: float = 0.0    # 巡逻左边界（世界坐标）
@export var patrol_max_x: float = 1e9    # 巡逻右边界

# 判定参数（按玩家碰撞盒 16x24、小怪半径 12 标定）
const HALF_W := 22.0     # 水平判定半宽
const STOMP_TOP := -20.0 # 踩踏窗口：玩家脚底相对怪中心的上限
const STOMP_BOTTOM := 8.0# 踩踏窗口：玩家脚底相对怪中心的下限
const HIT_DY := 22.0     # 侧碰判定的垂直中心距

var _dir: float = -1.0

@onready var _edge_ray: RayCast2D = $EdgeRay


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
	velocity.x = _dir * speed
	move_and_slide()

	# 掉头三条件：撞墙 / 前方悬崖 / 越出巡逻边界
	if is_on_wall():
		_flip()
	elif is_on_floor() and not _edge_ray.is_colliding():
		_flip()
	if _dir < 0.0 and global_position.x <= patrol_min_x:
		_flip()
	elif _dir > 0.0 and global_position.x >= patrol_max_x:
		_flip()

	# 边缘检测射线始终放在前进方向一侧
	_edge_ray.position.x = 12.0 * _dir

	_interact_players()


func _interact_players() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var body := p as Node2D
		if body == null:
			continue
		var dx: float = absf(body.global_position.x - global_position.x)
		if dx > HALF_W:
			continue
		var dy: float = body.global_position.y - global_position.y  # 玩家在怪下方为正
		var feet: float = dy + 12.0                                  # 玩家脚底相对怪中心
		if body is CharacterBody2D and (body as CharacterBody2D).velocity.y < -10.0:
			continue  # 正在上升：本帧不判定
		if feet > STOMP_TOP and feet < STOMP_BOTTOM:
			# 玩家脚落在怪头顶区间 → 踩死 + 反弹
			if body.has_method("bounce"):
				body.bounce()
			queue_free()
			return
		if absf(dy) < HIT_DY and body.has_method("take_hit"):
			body.take_hit()


func _flip() -> void:
	_dir = -_dir
