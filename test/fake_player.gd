extends CharacterBody2D
## 测试用假玩家：模拟重力下落，提供 bounce / take_hit 接口（与真玩家同签名）

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
	move_and_slide()


func bounce() -> void:
	velocity.y = -340.0


func take_hit() -> void:
	set_meta("was_hit", true)
