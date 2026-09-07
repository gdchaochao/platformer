extends CharacterBody2D
## 玩家角色控制（森林王国主角：小蘑菇人）
## 手感参数集中在顶部 @export，方便在编辑器里调试。
## 输入三重保险：InputMap 动作（逻辑+物理双绑）+ 物理/逻辑键轮询兜底。

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
@export var hold_to_auto_jump: bool = true  # 按住跳跃键：落地瞬间自动再跳（连跳手感试验）
@export var climb_speed: float = 120.0       # 梯子攀爬速度
# --------------------------

var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _on_ground_last: bool = false
var _jump_held_last: bool = false
var _down_block: bool = false    # 下爬落地脱梯后封锁↓，松开↓才解除（防无限下穿）
var invulnerable: bool = false   # 受伤无敌帧期间忽略再次伤害
var _climbing: bool = false      # 正在爬梯子


func _physics_process(delta: float) -> void:
	# 水平输入（动作优先，轮询兜底）
	var dir: float = Input.get_axis("move_left", "move_right")
	if dir == 0.0:
		if _down(KEY_A) or _down(KEY_LEFT):
			dir = -1.0
		elif _down(KEY_D) or _down(KEY_RIGHT):
			dir = 1.0

	# ---------- 梯子攀爬 ----------
	# ↓松开即解除封锁
	if not Input.is_action_pressed("move_down"):
		_down_block = false

	var on_ladder: bool = _overlapping_ladder()

	# 进入攀爬：接触梯子 + 按上（持续）/按下（封锁时无效）
	# collision_mask 清零：攀爬中不与地形碰撞——站在梯子顶的平台上按↓
	# 才能穿过平台面往下爬（否则会被平台托住永远下不来）
	if not _climbing and on_ladder \
			and (Input.is_action_pressed("move_up")
				or (Input.is_action_pressed("move_down") and not _down_block)):
		_climbing = true
		velocity = Vector2.ZERO
		collision_mask = 0

	if _climbing:
		if not on_ladder:
			# 爬出梯子顶端/底端：向下爬出 → 封锁↓（落地后按住不放不会反复下穿）
			_exit_climb(velocity.y > 0.0)
		elif Input.is_action_just_pressed("jump_space"):
			# 空格：跳离梯子
			_exit_climb(false)
			velocity = Vector2(velocity.x, jump_velocity * 0.7)
			Game.play_sfx("jump")
		else:
			# 攀爬移动：上/下爬，左右慢移（移出梯子即脱离）
			var vdir: float = Input.get_axis("move_up", "move_down")  # 上=-1 下=+1
			velocity = Vector2(dir * move_speed * 0.5, vdir * climb_speed)
			move_and_slide()
			if dir != 0.0:
				_flip(dir)
			if is_on_floor() and vdir > 0.0:
				_exit_climb(true)  # 爬到底落地
			_on_ground_last = is_on_floor()
			return

	# ---------- 常规移动 ----------
	var jump_pressed: bool = Input.is_action_pressed("jump") \
		or _down(KEY_SPACE) or _down(KEY_W) or _down(KEY_UP)

	# --- 跳跃缓冲：动作系统边沿 或 轮询边沿，二者取或 ---
	var jump_just: bool = Input.is_action_just_pressed("jump") \
		or (jump_pressed and not _jump_held_last)
	if jump_just:
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
	# 边沿触发（buffer + coyote） 或 按住连跳（落地即自动再跳）
	var can_jump: bool = _coyote > 0.0 and (_jump_buffer > 0.0 or (hold_to_auto_jump and jump_pressed))
	if can_jump:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		Game.play_sfx("jump")

	# --- 水平移动（地面/空中不同加速，移动时翻转朝向） ---
	var accel: float = ground_accel if is_on_floor() else air_accel
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * move_speed, accel * delta)
		_flip(dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta if is_on_floor() else ground_accel * 0.25 * delta)

	move_and_slide()
	_on_ground_last = is_on_floor()


## 是否与任意梯子（group "ladders"）重叠。
## 用梯子维护的进出列表查询（事件驱动），overlaps_body 在物理帧回调时机下不可靠。
func _overlapping_ladder() -> bool:
	for lad in get_tree().get_nodes_in_group("ladders"):
		if lad is Area2D and (lad as Area2D).has_method("has_body") and (lad as Area2D).has_body(self):
			return true
	return false


## 脱离攀爬：恢复与地形的碰撞（所有攀爬出口必须走这里）。
## block_down=true 时封锁↓键直到松开（用于下爬落地场景，防按住↓反复下穿地图）。
func _exit_climb(block_down: bool = false) -> void:
	_climbing = false
	collision_mask = 1
	if block_down:
		_down_block = true


func _flip(dir: float) -> void:
	if dir > 0.0 and scale.x < 0.0:
		scale.x = 1.0
	elif dir < 0.0 and scale.x > 0.0:
		scale.x = -1.0


## 键轮询兜底：物理键与逻辑键都查（不同浏览器事件字段填充有差异）
func _down(k: Key) -> bool:
	return Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)


## 踩到敌人头顶时的反弹
func bounce() -> void:
	velocity.y = bounce_velocity


## 受伤（尖刺/敌人碰撞）：无敌帧内忽略；扣命后由关卡把玩家传送回出生点
func take_hit() -> void:
	if invulnerable:
		return
	invulnerable = true
	if _climbing:
		_exit_climb(false)
	Game.play_sfx("hurt")
	Game.hurt_player()
	if not is_inside_tree():
		return
	# 无敌闪烁 1.1 秒（tween 挂在节点上，场景重载时自动销毁）
	var tw := create_tween()
	for i in range(4):
		tw.tween_property(self, "modulate:a", 0.35, 0.14)
		tw.tween_property(self, "modulate:a", 1.0, 0.14)
	tw.tween_callback(func() -> void: invulnerable = false)
