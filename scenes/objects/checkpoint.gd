extends Area2D
## 检查点旗：玩家经过时激活（旗子变绿+弹一下）。
## 激活位置由 level_base 记录，受伤/坠落重生到最近激活的检查点。

var activated: bool = false

@onready var _flag: Polygon2D = $Flag
@onready var _pole: Polygon2D = $Pole


func activate() -> void:
	if activated:
		return
	activated = true
	# 旗子由灰转绿，杆子提亮
	_flag.color = Color(0.36, 0.72, 0.3, 1)
	_pole.color = Color(0.62, 0.66, 0.6, 1)
	# 激活弹跳动画（juice）
	var tw := create_tween()
	tw.tween_property(_flag, "scale", Vector2(1.25, 0.75), 0.09)
	tw.tween_property(_flag, "scale", Vector2(0.9, 1.15), 0.11)
	tw.tween_property(_flag, "scale", Vector2.ONE, 0.12)
