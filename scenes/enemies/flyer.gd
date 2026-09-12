extends Node2D
## 飞行怪（萤翼蛾）：
## - 沿水平路线巡逻（patrol_min_x / patrol_max_x）
## - 垂直方向正弦浮动（float_amplitude / float_speed），phase 随机起始
## - 玩家从头顶踩到 → 消灭 + 反弹；侧面/下方碰到 → 玩家受伤
## - 不用物理体：飞行无重力，交互用与 walker 相同的每帧几何判定
##   （Hurtbox/事件方案已在此项目两次踩坑，几何判定最稳）

@export var speed: float = 80.0            # 水平巡逻速度
@export var patrol_min_x: float = 0.0      # 巡逻左边界（世界坐标）
@export var patrol_max_x: float = 1e9      # 巡逻右边界
@export var float_amplitude: float = 24.0  # 垂直浮动幅度（px）
@export var float_speed: float = 3.0       # 浮动角速度（rad/s）

# 判定参数（玩家碰撞盒 16x24；飞行怪体积小，窗口比 walker 稍宽容）
const HALF_W := 20.0
const STOMP_TOP := -18.0
const STOMP_BOTTOM := 10.0
const HIT_DY := 20.0

var _dir: float = -1.0
var _base_y: float = 0.0
var _phase: float = 0.0

@onready var _wing_l: Polygon2D = $WingL
@onready var _wing_r: Polygon2D = $WingR


func _ready() -> void:
	_base_y = global_position.y
	_phase = randf() * TAU  # 随机相位：同屏多只蛾不同步扇翅


func _physics_process(delta: float) -> void:
	_phase += float_speed * delta

	# 水平巡逻往返
	global_position.x += _dir * speed * delta
	if _dir < 0.0 and global_position.x <= patrol_min_x:
		_dir = 1.0
	elif _dir > 0.0 and global_position.x >= patrol_max_x:
		_dir = -1.0

	# 垂直正弦浮动（绕初始高度）
	global_position.y = _base_y + sin(_phase) * float_amplitude

	# 翅膀扑扇（绕翅根缩放，视觉近似扇动）
	var flap: float = 0.35 + 0.65 * absf(sin(_phase * 7.0))
	_wing_l.scale.y = flap
	_wing_r.scale.y = flap

	_interact_players()


func _interact_players() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var body := p as Node2D
		if body == null:
			continue
		var dx: float = absf(body.global_position.x - global_position.x)
		if dx > HALF_W:
			continue
		var dy: float = body.global_position.y - global_position.y  # 玩家在蛾下方为正
		var feet: float = dy + 12.0                                  # 玩家脚底相对蛾中心
		if body is CharacterBody2D and (body as CharacterBody2D).velocity.y < -10.0:
			continue  # 正在上升：本帧不判定
		if feet > STOMP_TOP and feet < STOMP_BOTTOM:
			# 从头顶拍中 → 消灭 + 反弹
			Game.play_sfx("stomp")
			if body.has_method("bounce"):
				body.bounce()
			queue_free()
			return
		if absf(dy) < HIT_DY and body.has_method("take_hit"):
			body.take_hit()
