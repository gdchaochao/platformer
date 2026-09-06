extends CharacterBody2D
## 巡逻小怪（森林刺球怪）：
## - 沿平台左右巡逻，碰墙 / 悬崖边缘 / 巡逻边界自动掉头
## - 玩家从头顶踩到 → 小怪被消灭，玩家反弹
## - 侧面/下方碰到玩家 → 玩家受伤（走 take_hit 无敌帧逻辑）

@export var speed: float = 60.0          # 巡逻速度
@export var patrol_min_x: float = 0.0    # 巡逻左边界（世界坐标）
@export var patrol_max_x: float = 1e9    # 巡逻右边界

var _dir: float = -1.0

@onready var _edge_ray: RayCast2D = $EdgeRay


func _ready() -> void:
	$Hurtbox.body_entered.connect(_on_hurtbox_body_entered)


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


func _flip() -> void:
	_dir = -_dir


func _on_hurtbox_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# 踩踏判定：玩家正在下落 且 玩家位置明显高于小怪中心
	if body.velocity.y > 40.0 and body.global_position.y < global_position.y - 6.0:
		if body.has_method("bounce"):
			body.bounce()
		queue_free()
	elif body.has_method("take_hit"):
		body.take_hit()
