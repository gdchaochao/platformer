extends SceneTree
## 诊断：检查 1-3 场景中梯子的视觉节点是否正确生成

var _level: Node
var _frames := 0


func _initialize() -> void:
	var s: PackedScene = load("res://scenes/levels/level_1_3.tscn")
	_level = s.instantiate()
	root.add_child(_level)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	for ladder_name in ["Ladder1", "Ladder2"]:
		var l: Node2D = _level.get_node_or_null(ladder_name)
		if l == null:
			print(ladder_name, ": 不存在！")
			continue
		print(ladder_name, " pos=", l.position, " height=", l.get("height"),
			" 子节点数=", l.get_child_count())
		for c in l.get_children():
			var info := "  " + c.get_class() + " " + c.name
			if c is Polygon2D:
				var pg := c as Polygon2D
				info += " color=%s 点数=%d" % [pg.color, pg.polygon.size()]
			if c is CollisionShape2D:
				var cs := c as CollisionShape2D
				info += " shape=%s pos=%s" % ["有" if cs.shape else "无", cs.position]
			print(info)
	quit(0)
	return true
