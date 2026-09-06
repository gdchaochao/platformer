extends Node2D
## 关卡逻辑：森林王国 1-1（苏醒之林）
## 统一用 group 约定场景里的交互物，避免到处连信号：
##   "coins"     → Area2D 金币（吃到 +1）
##   "killzone"  → Area2D 坠落/陷阱区（碰到扣一条命）
##   "goal"      → Area2D 终点旗帜（触发通关）
##   "hazard"    → Area2D 尖刺/敌人（预留，后续加伤害逻辑）

var _won: bool = false

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

	# 连接三类交互物（按 group 自动装配，场景里新增同组节点无需改代码）
	for coin: Area2D in get_tree().get_nodes_in_group("coins"):
		coin.body_entered.connect(_on_coin_body_entered.bind(coin))
	for kill: Area2D in get_tree().get_nodes_in_group("killzone"):
		kill.body_entered.connect(_on_killzone_body_entered)
	for goal: Area2D in get_tree().get_nodes_in_group("goal"):
		goal.body_entered.connect(_on_goal_body_entered)

	_refresh_hud()


func _refresh_hud() -> void:
	var total: int = get_tree().get_nodes_in_group("coins").size()
	_coins_label.text = "金币 %d/%d    生命 %d" % [Game.coins, total, Game.lives]


func _on_coin_body_entered(body: Node2D, coin: Area2D) -> void:
	if body.is_in_group("player"):
		coin.queue_free()
		Game.add_coin(1)


func _on_killzone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not _won:
		Game.hurt_player()


func _on_goal_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not _won:
		_won = true
		_win_label.text = "旗帜到手！%s" % Game.LEVEL_SEQUENCE[0]["display"]
		_win_label.visible = true
		# 演示推进：等待 1.5 秒后按关卡顺序表前进
		await get_tree().create_timer(1.5).timeout
		Game.on_level_cleared(scene_file_path)
