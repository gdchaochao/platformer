extends Node2D
## 主菜单：标题 + 开始游戏
## 空格 / 回车 / 点击按钮均可开始。

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.72, 0.87, 0.68))
	Game.play_music("menu")
	# 立绘蘑菇人：冻结物理，当作装饰
	var player: Node = get_node_or_null("Player")
	if player:
		player.set_physics_process(false)
	var btn: Button = $UI/StartButton
	btn.pressed.connect(_start)
	btn.grab_focus()
	# Web：确保 canvas 持有键盘焦点
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){var c=document.querySelector('canvas');if(c){try{c.focus();}catch(e){}}})()")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept"):
		_start()


func _start() -> void:
	Game.play_sfx("click")
	get_tree().change_scene_to_file(Game.LEVEL_SEQUENCE[0]["scene"])
