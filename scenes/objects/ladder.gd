extends Area2D
## 梯子：玩家重叠时按上/下即可攀爬。
## 原点 = 梯子顶端（放在平台面上方约 16px），height 向下延伸。
## 视觉（两根竖杆 + 横档）与碰撞区由代码按 height 生成。
## 玩家攀爬逻辑在 player.gd（梯子本身只是检测区）。

@export var height: float = 120.0  # 梯子总长（px）

const WIDTH := 30.0
const COLOR_RAIL := Color(0.9, 0.76, 0.5, 1)
const COLOR_RUNG := Color(0.72, 0.58, 0.36, 1)

# 当前在梯子内的 body 列表（body_entered/exited 事件驱动维护，
# 比每帧 overlaps_body 查询可靠——后者在 _physics_process 时机下状态不稳定）
var _bodies: Array = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 碰撞区：宽 WIDTH，从原点(顶端)向下 height
	var cs: CollisionShape2D = $CollisionShape2D
	var shape := RectangleShape2D.new()
	shape.size = Vector2(WIDTH, height)
	cs.shape = shape
	cs.position = Vector2(0, height / 2.0)

	# 视觉：两根竖杆
	# 注意：必须用显式 Vector2() 包装坐标——float 数组字面量会让每个
	# 数字退化成独立顶点，多边形直接碎成小点（踩过的坑）
	for side in [-1.0, 1.0]:
		var rail := Polygon2D.new()
		rail.color = COLOR_RAIL
		rail.polygon = PackedVector2Array([
			Vector2(side * WIDTH / 2.0 - 2.5 * side, 0.0),
			Vector2(side * WIDTH / 2.0 + 2.5 * side, 0.0),
			Vector2(side * WIDTH / 2.0 + 2.5 * side, height),
			Vector2(side * WIDTH / 2.0 - 2.5 * side, height),
		])
		add_child(rail)
	# 横档：每 24px 一根
	var rung_y := 14.0
	while rung_y < height:
		var rung := Polygon2D.new()
		rung.color = COLOR_RUNG
		rung.polygon = PackedVector2Array([
			Vector2(-WIDTH / 2.0 + 2.0, rung_y - 2.5),
			Vector2(WIDTH / 2.0 - 2.0, rung_y - 2.5),
			Vector2(WIDTH / 2.0 - 2.0, rung_y + 2.5),
			Vector2(-WIDTH / 2.0 + 2.0, rung_y + 2.5),
		])
		add_child(rung)
		rung_y += 24.0


func _on_body_entered(body: Node2D) -> void:
	if not _bodies.has(body):
		_bodies.append(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)


## 玩家侧查询：该 body 是否在梯子区域内
func has_body(body: Node2D) -> bool:
	return _bodies.has(body)
