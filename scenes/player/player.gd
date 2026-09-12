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
@export var double_jump_ratio: float = 0.92  # 二段跳力度（相对普通跳）
@export var wall_jump_hx: float = 260.0      # 蹬墙跳水平推力
@export var wall_jump_vy: float = -480.0     # 蹬墙跳垂直初速
@export var wall_slide_max: float = 90.0     # 贴墙滑降最大速度
@export var dash_speed: float = 520.0        # 冲刺速度
@export var dash_time: float = 0.18          # 冲刺持续时长
@export var dash_cooldown: float = 0.5       # 冲刺冷却
# --------------------------

var _jump_buffer: float = 0.0
var _coyote: float = 0.0
var _on_ground_last: bool = false
var _jump_held_last: bool = false
var _down_block: bool = false    # 下爬落地脱梯后封锁↓，松开↓才解除（防无限下穿）
var invulnerable: bool = false   # 受伤无敌帧期间忽略再次伤害
var _climbing: bool = false      # 正在爬梯子
var _active_ladder: Node2D = null  # 当前攀爬的梯子（下爬底端判定用）
var _air_jumps_left: int = 0     # 剩余空中跳次数（二段跳能力：1，未解锁：0）
var _wall_lock: float = 0.0      # 蹬墙跳后的水平输入锁定（防立刻贴回）
var _dash_left: float = 0.0      # 冲刺剩余时长
var _dash_cd: float = 0.0        # 冲刺冷却剩余
var _dash_held_last: bool = false


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
	var mount_ladder: Node2D = _mountable_ladder()

	# 进入攀爬：接触梯子 + 正对梯子 + 按上（持续）/按下（封锁时无效）
	# collision_mask 清零：攀爬中不与地形碰撞——站在梯子顶的平台上按↓
	# 才能穿过平台面往下爬（否则会被平台托住永远下不来）
	if not _climbing and mount_ladder \
			and (Input.is_action_pressed("move_up")
				or (Input.is_action_pressed("move_down") and not _down_block)):
		_climbing = true
		_active_ladder = mount_ladder
		velocity = Vector2.ZERO
		collision_mask = 0
		# 吸附到梯子中心：瞬间最多挪十几个像素，杜绝"贴边浮空爬"
		global_position.x = mount_ladder.global_position.x

	if _climbing:
		if not on_ladder:
			# 爬出梯子顶端/底端：向下爬出 → 封锁↓（落地后按住不放不会反复下穿）
			_exit_climb(velocity.y > 0.0)
		elif Input.is_action_just_pressed("jump_space"):
			# 空格：跳离梯子
			_exit_climb(false)
			velocity = Vector2(dir * move_speed * 0.6, jump_velocity * 0.7)
			Game.play_sfx("jump")
		else:
			# 攀爬移动：只上下爬（水平锁定，人贴在梯子上）
			var vdir: float = Input.get_axis("move_up", "move_down")  # 上=-1 下=+1
			velocity = Vector2(0.0, vdir * climb_speed)

			# 下爬到底端：脚一碰到梯子底端立即对齐落地退出。
			# 不能越过底端再退攀——攀爬中碰撞是关闭的，越过底端时
			# 玩家已经嵌进地面矩形里，恢复碰撞会被物理挤出去，
			# 表现就是"往下突破地面掉一下"。
			if vdir > 0.0 and is_instance_valid(_active_ladder):
				var bottom_y: float = _active_ladder.global_position.y + float(_active_ladder.height)
				if global_position.y + 12.0 >= bottom_y - 1.0:
					global_position.y = bottom_y - 12.0  # 脚对齐梯子底端
					velocity = Vector2.ZERO
					_exit_climb(true)
					move_and_slide()  # 恢复碰撞后贴地（轻微嵌入会被平滑推到地表）
					_on_ground_last = is_on_floor()
					return

			move_and_slide()
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

	# --- 冲刺输入与激活（能力未解锁时自然禁用） ---
	var dash_pressed_poll: bool = Input.is_action_pressed("dash") \
		or _down(KEY_SHIFT) or _down(KEY_X)
	var dash_just: bool = Input.is_action_just_pressed("dash") \
		or (dash_pressed_poll and not _dash_held_last)
	_dash_held_last = dash_pressed_poll
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	if dash_just and Game.has_ability("dash") and _dash_cd <= 0.0 and _dash_left <= 0.0:
		_dash_left = dash_time
		_dash_cd = dash_cooldown
		_exit_climb(false)
		var ddir: float = dir if dir != 0.0 else (1.0 if scale.x > 0.0 else -1.0)
		velocity = Vector2(ddir * dash_speed, 0.0)
		Game.play_sfx("dash")

	# --- 冲刺帧：水平匀速、无重力，跳过常规移动 ---
	if _dash_left > 0.0:
		_dash_left -= delta
		velocity.y = 0.0
		velocity.x = signf(velocity.x) * dash_speed
		move_and_slide()
		if is_on_floor() and not _on_ground_last:
			_air_jumps_left = _max_air_jumps()
		_on_ground_last = is_on_floor()
		return

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
	# 优先级：地面跳（buffer+coyote 或 按住连跳）→ 空中二段跳（消耗剩余次数）
	var can_jump: bool = _coyote > 0.0 and (_jump_buffer > 0.0 or (hold_to_auto_jump and jump_pressed))
	if can_jump:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_air_jumps_left = _max_air_jumps()  # 地面起跳：空中跳次数充满
		Game.play_sfx("jump")

	# --- 蹬墙跳（能力解锁后启用）：贴墙滑降减速，按跳向墙反方向弹出 ---
	var on_wall: bool = is_on_wall_only() and Game.has_ability("wall_jump")
	if on_wall and velocity.y > 0.0:
		velocity.y = minf(velocity.y, wall_slide_max)
	if on_wall and _jump_buffer > 0.0:
		var n: float = get_wall_normal().x
		velocity = Vector2(n * wall_jump_hx, wall_jump_vy)
		_jump_buffer = 0.0
		_coyote = 0.0
		_wall_lock = 0.14          # 短暂锁水平输入，防止立刻按回贴墙
		_air_jumps_left = _max_air_jumps()
		_flip(n)
		Game.play_sfx("wall_jump")

	# --- 二段跳（未解锁能力时次数恒为 0，自然禁用） ---
	elif _jump_buffer > 0.0 and _air_jumps_left > 0:
		velocity.y = jump_velocity * double_jump_ratio
		_air_jumps_left -= 1
		_jump_buffer = 0.0
		_coyote = 0.0
		Game.play_sfx("jump", -6.0, 1.3)  # 音调更高，区分二段跳

	# --- 水平移动（地面/空中不同加速，移动时翻转朝向） ---
	_wall_lock = maxf(_wall_lock - delta, 0.0)
	var accel: float = ground_accel if is_on_floor() else air_accel
	if _wall_lock <= 0.0:
		# 蹬墙跳弹开期间保持速度，不读输入
		if dir != 0.0:
			velocity.x = move_toward(velocity.x, dir * move_speed, accel * delta)
			_flip(dir)
		else:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta if is_on_floor() else ground_accel * 0.25 * delta)

	move_and_slide()
	# 落地边沿：空中跳次数重置
	if is_on_floor() and not _on_ground_last:
		_air_jumps_left = _max_air_jumps()
	_on_ground_last = is_on_floor()


## 可用空中跳次数：二段跳能力解锁后为 1，否则 0
func _max_air_jumps() -> int:
	return 1 if Game.has_ability("double_jump") else 0


## 是否与任意梯子（group "ladders"）重叠。
## 用梯子维护的进出列表查询（事件驱动），overlaps_body 在物理帧回调时机下不可靠。
## 攀爬中保持判断用（此时玩家已被吸附到梯子中心）。
func _overlapping_ladder() -> bool:
	for lad in get_tree().get_nodes_in_group("ladders"):
		if lad is Area2D and (lad as Area2D).has_method("has_body") and (lad as Area2D).has_body(self):
			return true
	return false


## 是否存在可以攀爬的梯子：有重叠 + 玩家正对梯子中心（can_mount）。
## 进入攀爬用；返回该梯子以便吸附对中。
func _mountable_ladder() -> Node2D:
	for lad in get_tree().get_nodes_in_group("ladders"):
		if lad is Area2D and (lad as Area2D).has_method("has_body") \
				and (lad as Area2D).has_method("can_mount"):
			var l := lad as Area2D
			if l.has_body(self) and l.can_mount(self):
				return l
	return null


## 脱离攀爬：恢复与地形的碰撞（所有攀爬出口必须走这里）。
## block_down=true 时封锁↓键直到松开（用于下爬落地场景，防按住↓反复下穿地图）。
func _exit_climb(block_down: bool = false) -> void:
	_climbing = false
	_active_ladder = null
	collision_mask = 1
	_air_jumps_left = _max_air_jumps()  # 跳离/离开梯子：空中跳重置
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
	_dash_left = 0.0  # 受伤打断冲刺
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
