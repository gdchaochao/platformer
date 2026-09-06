extends CharacterBody2D
## 玩家角色控制（森林王国主角：小蘑菇人）
## 包含一套"手感良好"的基础平台跳跃参数：
##   加速/摩擦、变量跳跃高度、跳跃缓冲(jump buffer)、土狼时间(coyote time)。
## 这些参数都集中在顶部 @export，方便在编辑器里调试手感。

# ---------- 可调参数 ----------
@export var move_speed: float = 220.0        # 最大水平速度 (px/s)
@export var ground_accel: float = 2200.0     # 地面加速
@export var air_accel: float = 1400.0        # 空中加速（空中操控性）
@export var friction: float = 2000.0         # 地面松手减速
@export var jump_velocity: float = -530.0    # 起跳初速度（负 = 向上）≈143px 跳高
@export var bounce_velocity: float = -340.0  # 踩到敌人头顶的反弹速度
@export var gravity_scale_hold: float = 1.0  # 按住跳跃键时的重力倍率（跳得高）
@export var gravity_scale_release: float = 1.8  # 松开跳跃键的重力倍率（快速落下=可调跳跃高度）
@export var jump_buffer_time: float = 0.12   # 落地前按跳跃的宽容时间
@export var coyote_time: float = 0.10        # 离开平台后仍可起跳的宽容时间
# --------------------------

var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _on_ground_last: bool = false
var invulnerable: bool = false   # 受伤无敌帧期间忽略再次伤害

@onready var _cap: Polygon2D = $Cap
@onready var _body: Polygon2D = $Body
@onready var _eye_l: Polygon2D = $EyeL
@onready var _eye_r: Polygon2D = $EyeR


func _physics_process(delta: float) -> void:
	# 输入全部走 InputMap 动作（Game._setup_input 注册）：
	# 动作系统由引擎维护按键状态，多键同时按住不会互斥，Web/桌面行为一致。
	var dir: float = Input.get_axis("move_left", "move_right")
	var jump_pressed: bool = Input.is_action_pressed("jump")

	# --- 跳跃缓冲：is_action_just_pressed 引擎级边沿检测，按下瞬间置位 ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	# --- 土狼时间：离开平台边缘后的一小段时间仍允许起跳 ---
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# --- 重力（变量跳跃高度：按住跳得高，松开掉得快） ---
	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
	var g_mult: float = gravity_scale_release
	if jump_pressed and velocity.y < 0.0:
		g_mult = gravity_scale_hold
	velocity.y += gravity * g_mult * delta

	# --- 起跳 ---
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0

	# --- 水平移动（地面/空中不同加速，移动时翻转朝向） ---
	var accel: float = ground_accel if is_on_floor() else air_accel
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * move_speed, accel * delta)
		_flip(dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta if is_on_floor() else ground_accel * 0.25 * delta)

	move_and_slide()
	_on_ground_last = is_on_floor()


func _flip(dir: float) -> void:
	if dir > 0.0 and scale.x < 0.0:
		scale.x = 1.0
	elif dir < 0.0 and scale.x > 0.0:
		scale.x = -1.0


## 踩到敌人头顶时的反弹
func bounce() -> void:
	velocity.y = bounce_velocity


## 受伤（尖刺/敌人碰撞）：无敌帧内忽略；扣命后由关卡把玩家传送回出生点
func take_hit() -> void:
	if invulnerable:
		return
	invulnerable = true
	Game.hurt_player()
	if not is_inside_tree():
		return
	# 无敌闪烁 1.1 秒（tween 挂在节点上，场景重载时自动销毁）
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(self, "modulate:a", 0.35, 0.14)
		tw.tween_property(self, "modulate:a", 1.0, 0.14)
	tw.tween_callback(func() -> void: invulnerable = false)


## 受伤闪烁（占位：之后可换真正的受伤动画/无敌帧）
func take_hit_feedback() -> void:
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.15).timeout
	modulate = Color.WHITE
