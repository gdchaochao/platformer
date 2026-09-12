extends SceneTree
## 存档系统回归测试（headless）：
##   godot --headless -s res://test/test_save.gd
## 用例1：两次记录取最佳（金币 max、宝石保留高值、cleared 不回退）
## 用例2：重新实例化后从磁盘加载，数据一致（持久化）
## 用例3：unlocked_count 链式解锁（第 1 关恒解锁）


func _initialize() -> void:
	print("== 存档回归测试 ==")
	var sms: Script = load("res://autoload/save_manager.gd")
	var sm: Node = sms.new()
	sm.save_path = "user://test_save_wowo.json"
	if FileAccess.file_exists(sm.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.save_path))
	sm.load_data()

	# 用例1：两次记录取最佳
	sm.record_level_result("res://scenes/levels/level_1_1.tscn", 3, 1, true)
	sm.record_level_result("res://scenes/levels/level_1_1.tscn", 5, 0, true)
	var rec: Dictionary = sm.data["levels"]["level_1_1"]
	var c1: bool = int(rec["coins"]) == 5 and int(rec["gems"]) == 1 and bool(rec["cleared"])
	print("用例1 最佳合并: %s" % ("PASS" if c1 else "FAIL -> " + str(rec)))

	# 用例2：持久化（新实例从磁盘读回）
	var sm2: Node = sms.new()
	sm2.save_path = sm.save_path
	sm2.load_data()
	var c2: bool = sm2.best_coins("res://scenes/levels/level_1_1.tscn") == 5 \
		and sm2.is_cleared("res://scenes/levels/level_1_1.tscn")
	print("用例2 持久化: %s" % ("PASS" if c2 else "FAIL"))

	# 用例3：链式解锁——必须用干净存档（上面的用例已把 1-1 标记 cleared）
	# 注意 unlocked_count 依赖 Game.LEVEL_SEQUENCE（-s 模式无 autoload），这里内联同款逻辑
	var sm3: Node = sms.new()
	sm3.save_path = sm.save_path + ".c3"
	sm3.load_data()  # 全新空档
	var fake_seq := [
		{"scene": "res://scenes/levels/level_1_1.tscn"},
		{"scene": "res://scenes/levels/level_1_2.tscn"},
		{"scene": "res://scenes/levels/level_1_3.tscn"},
	]
	var unlocked := 1
	for i in range(1, fake_seq.size()):
		if sm3.is_cleared(str(fake_seq[i - 1]["scene"])):
			unlocked += 1
		else:
			break
	var c3a: bool = unlocked == 1
	sm3.record_level_result("res://scenes/levels/level_1_1.tscn", 0, 0, true)
	unlocked = 1
	for i in range(1, fake_seq.size()):
		if sm3.is_cleared(str(fake_seq[i - 1]["scene"])):
			unlocked += 1
		else:
			break
	var c3b: bool = unlocked == 2
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm3.save_path))
	var c3: bool = c3a and c3b
	print("用例3 链式解锁: %s（空档解锁=%d 应为1；通 1-1 后=%d 应为2）" % ["PASS" if c3 else "FAIL", (1 if c3a else 0), (2 if c3b else 0)])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sm.save_path))
	var all_pass: bool = c1 and c2 and c3
	print("== %s ==" % ("全部通过" if all_pass else "存在失败"))
	quit(0 if all_pass else 1)
