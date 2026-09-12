extends Control
## 全通关结算页：展示本局金币/宝石/用时，按空格或点按钮回主菜单。
## 进入本页时 Game 不清零（数据展示完离开时才 reset_run）。

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.17, 0.28))
	Game.play_sfx("win")
	Game.play_music("menu")

	$Panel/CoinsLabel.text = "金币  %d" % Game.coins
	$Panel/GemsLabel.text = "宝石  %d" % Game.gems
	$Panel/TimeLabel.text = "用时  %s" % Game.format_time(Game.run_elapsed_ms)

	var btn: Button = $Panel/MenuButton
	btn.pressed.connect(_back)
	btn.grab_focus()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept"):
		_back()


func _back() -> void:
	Game.play_sfx("click")
	Game.reset_run()
	get_tree().change_scene_to_file(Game.MAIN_MENU)
