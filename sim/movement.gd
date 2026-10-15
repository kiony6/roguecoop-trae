extends RefCounted
## 权威移动步进。主机是唯一裁决方，客户端预测复用同一份实现以保持一致。
## M4：支持矩形墙体（轴分离滑动）与竞技场边界钳制。墙体只拦玩家，不拦敌人/掉落/弹丸。

const Combat := preload("res://sim/combat.gd")
const Rooms := preload("res://sim/rooms.gd")

const SPEED := 220.0


static func step(
	pos: Vector2, move: Vector2, delta: float, speed: float = SPEED, walls: Array = []
) -> Vector2:
	var dir := move
	var len := dir.length()
	if len > 1.0:
		dir = dir / len
	var out := pos
	var dx := dir.x * speed * delta
	if not is_zero_approx(dx):
		out.x = _clamp_axis_x(out.x, out.y, dx, walls)
	var dy := dir.y * speed * delta
	if not is_zero_approx(dy):
		out.y = _clamp_axis_y(out.x, out.y, dy, walls)
	var half := Rooms.ARENA_HALF - Vector2(Combat.PLAYER_RADIUS, Combat.PLAYER_RADIUS)
	out.x = clampf(out.x, -half.x, half.x)
	out.y = clampf(out.y, -half.y, half.y)
	return out


static func _clamp_axis_x(x: float, y: float, dx: float, walls: Array) -> float:
	var target := x + dx
	for w in walls:
		var r: Rect2 = w
		var top := r.position.y - Combat.PLAYER_RADIUS
		var bot := r.position.y + r.size.y + Combat.PLAYER_RADIUS
		if y < top or y > bot:
			continue
		if dx > 0.0:
			var edge := r.position.x - Combat.PLAYER_RADIUS
			if x <= edge and target > edge:
				target = edge
		else:
			var edge2 := r.position.x + r.size.x + Combat.PLAYER_RADIUS
			if x >= edge2 and target < edge2:
				target = edge2
	return target


static func _clamp_axis_y(x: float, y: float, dy: float, walls: Array) -> float:
	var target := y + dy
	for w in walls:
		var r: Rect2 = w
		var left := r.position.x - Combat.PLAYER_RADIUS
		var right := r.position.x + r.size.x + Combat.PLAYER_RADIUS
		if x < left or x > right:
			continue
		if dy > 0.0:
			var edge := r.position.y - Combat.PLAYER_RADIUS
			if y <= edge and target > edge:
				target = edge
		else:
			var edge2 := r.position.y + r.size.y + Combat.PLAYER_RADIUS
			if y >= edge2 and target < edge2:
				target = edge2
	return target
