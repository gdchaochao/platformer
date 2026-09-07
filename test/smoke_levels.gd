extends SceneTree
## 冒烟测试：依次加载 1-1 / 1-2 / 主菜单，验证三个场景都能无错运行
##   godot --headless -s res://test/smoke_levels.gd

const SCENES := [
	"res://scenes/levels/level_1_1.tscn",
	"res://scenes/levels/level_1_2.tscn",
	"res://scenes/levels/level_1_3.tscn",
	"res://scenes/ui/main_menu.tscn",
]
const NAMES := ["1-1", "1-2", "1-3", "主菜单"]

var _step := -1
var _frames := 0


func _initialize() -> void:
	print("== 场景冒烟测试 ==")
	_advance()


func _advance() -> void:
	_step += 1
	_frames = 0
	if _step < SCENES.size():
		change_scene_to_file(SCENES[_step])
	else:
		print("== 冒烟通过 ==")
		quit(0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 45:
		var ok: bool = current_scene != null
		print("%s 加载: %s -> %s" % [NAMES[_step], SCENES[_step].get_file(), ok])
		if not ok:
			print("TEST_FAIL: 场景未加载")
			quit(1)
			return true
		_advance.call_deferred()
	elif _frames > 200:
		print("TEST_FAIL: 场景加载超时")
		quit(1)
		return true
	return false
