extends Node
## 存档管理器（Autoload: SaveManager）
## 存 user://save.json——桌面写本地文件，Web 导出时 Godot 自动映射到
## IndexedDB，刷新/重开浏览器数据不丢，两端同一套代码。
## 记录：每关最佳金币/宝石、是否通关。选关解锁逻辑基于 cleared 链。

var save_path: String = "user://save.json"
var data: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	data = {"levels": {}}
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				data = parsed
			if not data.has("levels"):
				data["levels"] = {}


func save_data() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _key(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


## 记录一次通关结果：金币/宝石取历史最佳，cleared 只置真不清除
func record_level_result(scene_path: String, coins: int, gems: int, cleared: bool) -> void:
	var key := _key(scene_path)
	var prev: Dictionary = data["levels"].get(key, {})
	data["levels"][key] = {
		"coins": maxi(int(prev.get("coins", 0)), coins),
		"gems": maxi(int(prev.get("gems", 0)), gems),
		"cleared": bool(prev.get("cleared", false)) or cleared,
	}
	save_data()


func is_cleared(scene_path: String) -> bool:
	var rec: Dictionary = data["levels"].get(_key(scene_path), {})
	return bool(rec.get("cleared", false))


func best_coins(scene_path: String) -> int:
	var rec: Dictionary = data["levels"].get(_key(scene_path), {})
	return int(rec.get("coins", 0))


func best_gems(scene_path: String) -> int:
	var rec: Dictionary = data["levels"].get(_key(scene_path), {})
	return int(rec.get("gems", 0))


## 已解锁关卡数：第 1 关始终解锁，其余按"前一关已通关"链式解锁。
## （选关面板转正时直接用它判断按钮可用性）
func unlocked_count() -> int:
	var n := 1
	for i in range(1, Game.LEVEL_SEQUENCE.size()):
		if is_cleared(str(Game.LEVEL_SEQUENCE[i - 1]["scene"])):
			n += 1
		else:
			break
	return n
