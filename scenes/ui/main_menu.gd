extends Node2D
## 主菜单：标题 + 开始游戏
## 空格 / 回车 / 点击按钮均可开始。
## DEBUG_LEVEL_SELECT = true 时右侧显示"关卡选择"测试面板（可跳任意关）。

@onready var _debug_panel: Control = $UI/DebugPanel
@onready var _level_grid: GridContainer = $UI/DebugPanel/LevelScroll/LevelGrid


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
	_build_level_select()
	_check_debug_level_param()


## 测试用：URL 带 ?level=N 时直接进入第 N 关（如 ?level=3 进 1-3）。
## 仅在 DEBUG_LEVEL_SELECT 开启时生效，正式版无效。
func _check_debug_level_param() -> void:
	if not Game.DEBUG_LEVEL_SELECT or not OS.has_feature("web"):
		return
	var q: String = str(JavaScriptBridge.eval("location.search"))
	var idx := q.find("level=")
	if idx < 0:
		return
	var n := int(q.substr(idx + 6))
	if n >= 1 and n <= Game.LEVEL_SEQUENCE.size():
		get_tree().change_scene_to_file.call_deferred(Game.LEVEL_SEQUENCE[n - 1]["scene"])


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept"):
		_start()


func _start() -> void:
	Game.play_sfx("click")
	get_tree().change_scene_to_file(Game.LEVEL_SEQUENCE[0]["scene"])


## 测试用关卡选择面板：动态读取关卡顺序表生成按钮。
## 3 列紧凑网格 + 滚动容器兜底，关卡再多也不溢出画面。
## 显隐由 Game.DEBUG_LEVEL_SELECT 控制，上线改 false 即整体隐藏。
func _build_level_select() -> void:
	_debug_panel.visible = Game.DEBUG_LEVEL_SELECT
	if not Game.DEBUG_LEVEL_SELECT:
		return
	var font: Font = load("res://assets/fonts/fusion_pixel.otf")
	for entry: Dictionary in Game.LEVEL_SEQUENCE:
		var display: String = str(entry["display"])
		var b := Button.new()
		b.text = _short_label(display)          # 按钮只显示 "1-1" 这样的短编号
		b.tooltip_text = display                 # 鼠标悬停可看完整关卡名
		b.custom_minimum_size = Vector2(56, 24)
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_goto_level.bind(str(entry["scene"])))
		_level_grid.add_child(b)


## "森林王国 1-1 苏醒之林" → "1-1"（取第二段；格式不符则回退原文本）
func _short_label(display: String) -> String:
	var parts := display.split(" ", false)
	return parts[1] if parts.size() >= 2 else display


func _goto_level(scene_path: String) -> void:
	Game.play_sfx("click")
	get_tree().change_scene_to_file(scene_path)
