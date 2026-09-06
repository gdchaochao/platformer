extends Area2D
## 弹跳蘑菇：玩家落到帽子上被大弹力弹起（比普通跳高得多）
## 放在地面上即可工作，无需关卡脚本参与。

@export var launch_velocity: float = -740.0  # 弹射初速度（≈280px 弹高）

@onready var _cap: Polygon2D = $Cap


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# 玩家上升中穿过时不触发，避免二次弹射
	if body is CharacterBody2D and (body as CharacterBody2D).velocity.y < -50.0:
		return
	(body as CharacterBody2D).velocity.y = launch_velocity
	Game.play_sfx("bounce")
	_squash()


## 帽子压扁回弹的小动画（juice）
func _squash() -> void:
	var tw := create_tween()
	tw.tween_property(_cap, "scale", Vector2(1.25, 0.55), 0.08)
	tw.tween_property(_cap, "scale", Vector2(0.9, 1.15), 0.1)
	tw.tween_property(_cap, "scale", Vector2.ONE, 0.12)
