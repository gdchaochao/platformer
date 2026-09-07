extends SceneTree
## 诊断：打印主菜单关卡按钮的全局坐标，并换算为浏览器 CSS 坐标
## （窗口 1280x577、viewport 640x360、keep 黑边居中）

var _menu: Node
var _frames := 0


func _initialize() -> void:
	var s: PackedScene = load("res://scenes/ui/main_menu.tscn")
	_menu = s.instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var box: VBoxContainer = _menu.get_node("UI/DebugPanel/LevelSelectBox")
	var win := Vector2(1280, 577)
	var vp := Vector2(640, 360)
	var sc: float = minf(win.x / vp.x, win.y / vp.y)
	var off: Vector2 = (win - vp * sc) / 2.0
	for b in box.get_children():
		var btn := b as Button
		var gc: Vector2 = btn.get_global_rect().get_center()
		var css := off + gc * sc
		print("%s | game_center=%s size=%s | css_click=(%d,%d)" % [
			btn.text, gc, btn.size, int(css.x), int(css.y)])
	var start: Button = _menu.get_node("UI/StartButton")
	var sc2: Vector2 = start.get_global_rect().get_center()
	var css2 := off + sc2 * sc
	print("开始游戏 | game_center=%s | css_click=(%d,%d)" % [sc2, int(css2.x), int(css2.y)])
	quit(0)
	return true
