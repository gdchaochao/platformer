extends Area2D
## 大宝石：藏在支路/高处的稀有收集品，独立于金币计数。
## 收集逻辑由 level_base 按 "gems" group 统一装配；这里只负责浮动动画。

func _ready() -> void:
	var base_y: float = position.y
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position:y", base_y - 9.0, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", base_y, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
