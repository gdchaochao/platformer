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
@export var jump_velocity: float = -470.0    # 起跳初速度（负 = 向上）
@export var gravity_scale_hold: float = 1.0  # 按住跳跃键时的重力倍率（跳得高）
@export var gravity_scale_release: float = 1.8  # 松开跳跃键的重力倍率（快速落下=可调跳跃高度）
@export var jump_buffer_time: float = 0.12   # 落地前按跳跃的宽容时间
@export var coyote_time: float = 0.10        # 离开平台后仍可起跳的宽容时间
# --------------------------

var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _on_ground_last: bool = false
var _jump_held_last: bool = false

@onready var _cap: Polygon2D = $Cap
@onready var _body: Polygon2D = $Body
@onready var _eye_l: Polygon2D = $EyeL
@onready var _eye_r: Polygon2D = $EyeR


func _physics_process(delta: float) -> void:
	# 水平输入：A/D 或 方向键
	# 同时检测物理键与逻辑键：桌面两者一致；Web 浏览器只可靠支持逻辑键(key)。
	var dir: float = 0.0
	if _down(KEY_A) or _down(KEY_LEFT):
		dir -= 1.0
	if _down(KEY_D) or _down(KEY_RIGHT):
		dir += 1.0

	# 跳跃输入：空格 / W / 上方向
	var jump_pressed: bool = _down(KEY_SPACE) or _down(KEY_W) or _down(KEY_UP)

	# --- 跳跃缓冲：检测"新按下"（边沿触发）时置位缓冲，落地瞬间自动起跳 ---
	# 注意：不能用"是否在地面"判断，否则站在地面按跳跃永远无法起跳！
	if jump_pressed and not _jump_held_last:
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_jump_held_last = jump_pressed

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


## 同时检测物理键与逻辑键（Web 平台 physical keycode 不可靠，需逻辑键兜底）
func _down(k: Key) -> bool:
	return Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)


func _flip(dir: float) -> void:
	if dir > 0.0 and scale.x < 0.0:
		scale.x = 1.0
	elif dir < 0.0 and scale.x > 0.0:
		scale.x = -1.0


## 受伤闪烁（占位：之后可换真正的受伤动画/无敌帧）
func take_hit_feedback() -> void:
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.15).timeout
	modulate = Color.WHITE
