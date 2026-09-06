extends Node2D
## 通用关卡逻辑（level_1_1 / level_1_2 / 未来所有关卡共用）
## 场景里用 group 约定交互物，避免到处连信号：
##   "coins"     → Area2D 金币（吃到 +1）
##   "killzone"  → Area2D 坠落/陷阱区（碰到扣一条命）
##   "goal"      → Area2D 终点旗帜（触发通关）
##   "hazard"    → Area2D 尖刺等静态危险物（带无敌帧判定的伤害）
## 敌人（walker）的踩踏/伤害由敌人场景自己处理。
## 每关定制：sky_color 天空色；关卡名自动从 Game.LEVEL_SEQUENCE 读取。

@export var sky_color: Color = Color(0.72, 0.87, 0.68)  # 每关天空色

var _won: bool = false
var _coins_total: int = 0  # 开局缓存金币总数（避免吃到后分母变小）
var _game_over: bool = false
var _game_over_at_ms: int = 0

@onready var _player: CharacterBody2D = $Player
@onready var _spawn: Marker2D = $Spawn
@onready var _coins_label: Label = $HUD/CoinsLabel
@onready var _win_label: Label = $HUD/WinLabel
@onready var _title_label: Label = $HUD/LevelTitle


func _ready() -> void:
	# 每关自己的天空色
	RenderingServer.set_default_clear_color(sky_color)
	Game.play_music("level")
	_focus_canvas_web()

	_win_label.visible = false
	_win_label.text = ""

	# 开场关卡名展示（1.6s 后淡出）
	_title_label.text = Game.display_name(scene_file_path)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _title_label.visible = false)

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


## Web 平台：从主菜单进入关卡后焦点可能留在别处导致键盘失效，
## 主动把焦点拉回 canvas（仅 Web 生效）
func _focus_canvas_web() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){var c=document.querySelector('canvas');if(c&&document.activeElement!==c){try{c.focus();}catch(e){}}})()")


func _on_game_over() -> void:
	_game_over = true
	_game_over_at_ms = Time.get_ticks_msec()
	Game.stop_music()
	Game.play_sfx("game_over")
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
		Game.play_sfx("coin")
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
		_win_label.text = "旗帜到手！%s" % Game.display_name(scene_file_path)
		_win_label.visible = true
		Game.play_sfx("win")
		# 演示推进：等待 1.5 秒后按关卡顺序表前进
		await get_tree().create_timer(1.5).timeout
		Game.on_level_cleared(scene_file_path)
