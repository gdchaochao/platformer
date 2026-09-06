extends Node2D
## 关卡逻辑：森林王国 1-1（苏醒之林）
## 统一用 group 约定场景里的交互物，避免到处连信号：
##   "coins"     → Area2D 金币（吃到 +1）
##   "killzone"  → Area2D 坠落/陷阱区（碰到扣一条命）
##   "goal"      → Area2D 终点旗帜（触发通关）
##   "hazard"    → Area2D 尖刺等静态危险物（带无敌帧判定的伤害）
## 敌人（walker）的伤害/踩踏由敌人场景自己处理，不走这里。

var _won: bool = false
var _coins_total: int = 0  # 开局缓存金币总数（避免吃到后分母变小）
var _game_over: bool = false
var _game_over_at_ms: int = 0

@onready var _player: CharacterBody2D = $Player
@onready var _spawn: Marker2D = $Spawn
@onready var _coins_label: Label = $HUD/CoinsLabel
@onready var _win_label: Label = $HUD/WinLabel


func _ready() -> void:
	# 全局清屏色：森林天空色（水墨 World2 可改为纸色/青色）
	RenderingServer.set_default_clear_color(Color(0.72, 0.87, 0.68))

	_win_label.visible = false
	_win_label.text = ""

	# 金币/生命变化实时刷新 HUD
	Game.coins_changed.connect(func(_v: int) -> void: _refresh_hud())
	Game.lives_changed.connect(func(_v: int) -> void: _refresh_hud())
	# 受伤未死：传送回出生点
	Game.player_hurt.connect(_on_player_hurt)
	# 生命耗尽：显示 Game Over，玩家按键后重开
	Game.game_over.connect(_on_game_over)

	# 连接各类交互物（按 group 自动装配，场景里新增同组节点无需改代码）
	for coin: Area2D in get_tree().get_nodes_in_group("coins"):
		coin.body_entered.connect(_on_coin_body_entered.bind(coin))
	_coins_total = get_tree().get_nodes_in_group("coins").size()
	for kill: Area2D in get_tree().get_nodes_in_group("killzone"):
		kill.body_entered.connect(_on_killzone_body_entered)
	for goal: Area2D in get_tree().get_nodes_in_group("goal"):
		goal.body_entered.connect(_on_goal_body_entered)
	for hazard: Area2D in get_tree().get_nodes_in_group("hazard"):
		hazard.body_entered.connect(_on_hazard_body_entered)

	_refresh_hud()


func _on_player_hurt() -> void:
	if not is_instance_valid(_player):
		return
	_player.global_position = _spawn.global_position
	_player.velocity = Vector2.ZERO


func _on_game_over() -> void:
	_game_over = true
	_game_over_at_ms = Time.get_ticks_msec()
	if is_instance_valid(_player):
		_player.set_physics_process(false)  # 冻结玩家操作
	$HUD/GameOverRect.visible = true
	$HUD/GameOverTitle.visible = true
	$HUD/GameOverHint.visible = true


func _process(_delta: float) -> void:
	# Game Over 后 0.8 秒防误按，再按跳跃键重开整轮
	if not _game_over:
		return
	if Time.get_ticks_msec() - _game_over_at_ms > 800 and Input.is_action_just_pressed("jump"):
		_game_over = false
		Game.reset_run()
		get_tree().reload_current_scene()


func _refresh_hud() -> void:
	_coins_label.text = "金币 %d/%d    生命 %d" % [Game.coins, _coins_total, Game.lives]


func _on_coin_body_entered(body: Node2D, coin: Area2D) -> void:
	if body.is_in_group("player"):
		coin.queue_free()
		Game.add_coin(1)


func _on_killzone_body_entered(body: Node2D) -> void:
	# 坠落必扣命（不受无敌帧保护），传送回出生点由 player_hurt 信号完成
	if body.is_in_group("player") and not _won:
		Game.hurt_player()


func _on_hazard_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not _won and body.has_method("take_hit"):
		body.take_hit()


func _on_goal_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not _won:
		_won = true
		_win_label.text = "旗帜到手！%s" % Game.LEVEL_SEQUENCE[0]["display"]
		_win_label.visible = true
		# 演示推进：等待 1.5 秒后按关卡顺序表前进
		await get_tree().create_timer(1.5).timeout
		Game.on_level_cleared(scene_file_path)
