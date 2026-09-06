extends Node
## 全局游戏状态单例（Autoload: Game）
## 职责：跨场景的生命/金币计数、关卡顺序表、场景切换。
## 未来扩展：存档系统、设置项、BGM 播放等都挂到这里。

signal coins_changed(value: int)
signal lives_changed(value: int)
signal player_hurt  # 玩家受伤但生命未耗尽：关卡负责把玩家传送回出生点

const START_LEVEL: String = "res://scenes/levels/level_1_1.tscn"

# 关卡顺序表（这就是"推进"的主干）。
# 每关一个条目：scene 场景路径 + world 所属世界 + display 显示名。
# 后续接入水墨山水 World2 时，只要在数组后面追加：
#   { "scene": "res://scenes/levels/world2_ink/level_2_1.tscn", "world": "ink", "display": "水墨山水 2-1" }
# 再创建对应场景文件，关卡流程就会自动串起来。
const LEVEL_SEQUENCE: Array[Dictionary] = [
	{ "scene": "res://scenes/levels/level_1_1.tscn", "world": "forest", "display": "森林王国 1-1 苏醒之林" },
]

var lives: int = 3
var coins: int = 0


func _ready() -> void:
	# 全局回退字体：开源中文像素字体（Fusion Pixel, OFL）
	# 解决 Godot 默认字体不含中文导致 HUD/菜单显示方块的问题
	var pixel_font: Font = load("res://assets/fonts/fusion_pixel.otf")
	if pixel_font:
		ThemeDB.fallback_font = pixel_font
	reset_run()


## 开始新的一轮（生命/金币归零，常用于死亡次数耗尽后重新开始）
func reset_run() -> void:
	lives = 3
	coins = 0
	coins_changed.emit(coins)
	lives_changed.emit(lives)


## 拾取金币
func add_coin(amount: int = 1) -> void:
	coins += amount
	coins_changed.emit(coins)


## 受到一次伤害：扣一条命；生命未耗尽则通知关卡传送玩家回出生点，耗尽则整轮重来
func hurt_player() -> void:
	lives -= 1
	lives_changed.emit(lives)
	if lives <= 0:
		print("生命耗尽，整轮重新开始")
		reset_run()
		reload_current_level()
	else:
		print("受伤，当前生命: %d" % lives)
		player_hurt.emit()


## 通关：看顺序表里还有没有下一关
func on_level_cleared(current_scene_path: String) -> void:
	var idx: int = _index_of(current_scene_path)
	if idx < 0:
		return
	if idx + 1 < LEVEL_SEQUENCE.size():
		var next_level: Dictionary = LEVEL_SEQUENCE[idx + 1]
		print("进入下一关: %s" % next_level["display"])
		get_tree().change_scene_to_file(next_level["scene"])
	else:
		print("全部关卡完成！")
		# TODO: 这里跳转到结算/标题场景
		get_tree().change_scene_to_file(START_LEVEL)


func reload_current_level() -> void:
	get_tree().reload_current_scene()


func _index_of(scene_path: String) -> int:
	for i in LEVEL_SEQUENCE.size():
		if LEVEL_SEQUENCE[i]["scene"] == scene_path:
			return i
	return -1
