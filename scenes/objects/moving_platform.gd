extends AnimatableBody2D
## 移动平台：在起始位置与 起始位置+move_offset 之间往复移动。
## 用 AnimatableBody2D（sync_to_physics）——站在上面的玩家会被正确携带，
## 这是 Godot 4 处理移动平台的标准节点（StaticBody2D 移动时会穿透玩家）。

@export var move_offset: Vector2 = Vector2(200, 0)  # 往复位移向量
@export var period: float = 3.0                     # 单程耗时（秒）
@export var start_delay: float = 0.0                # 启动延迟（错开多个平台相位）


func _ready() -> void:
	_run_loop()


func _run_loop() -> void:
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	var target: Vector2 = position + move_offset
	var tw := create_tween().set_loops()
	tw.tween_property(self, "position", target, period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", position, period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
