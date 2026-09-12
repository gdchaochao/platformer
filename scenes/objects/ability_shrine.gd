extends Area2D
## 能力祭坛：碰到后授予 export 指定的能力。
## 授予由 level_base 统一处理（本脚本只负责"是什么能力"与收集演出）。
## 幂等：能力已拥有时再次触碰只播放轻微光效，不重复发信号。

@export var ability: String = "double_jump"  # 授予的能力名（对应 Game.abilities 键）

var _collected: bool = false

@onready var _orb: Polygon2D = $Orb
@onready var _halo: Polygon2D = $Halo


func _ready() -> void:
	# 光球悬浮 + 光环呼吸（循环 tween）
	var tw := create_tween().set_loops()
	tw.tween_property(_orb, "position:y", -10.0, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_orb, "position:y", -4.0, 1.0).set_trans(Tween.TRANS_SINE)
	var tw2 := create_tween().set_loops()
	tw2.tween_property(_halo, "scale", Vector2(1.15, 1.15), 0.8)
	tw2.tween_property(_halo, "scale", Vector2(0.9, 0.9), 0.8)


func ability_name() -> String:
	return ability


## 已拥有该能力？（由 level_base 查询决定是否播全演出）
func already_granted() -> bool:
	return Game.has_ability(ability)


## 收集演出：光球放大淡出后隐藏
func collect() -> void:
	if _collected:
		return
	_collected = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_orb, "scale", Vector2(2.2, 2.2), 0.35)
	tw.tween_property(_orb, "modulate:a", 0.0, 0.35)
	tw.tween_property(_halo, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void: visible = false)
