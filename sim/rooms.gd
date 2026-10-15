extends RefCounted
## 程序化房间纯逻辑（M4）。确定性地生成一屏矩形墙体，并保证出生区无障碍。
## 只在主机生成一次，经可靠 RPC 下发；双方用同一份墙体做玩家碰撞与本地预测。
## 注意：墙体只与玩家碰撞，不拦敌人/掉落/弹丸（敌人无寻路，拦墙会卡死）。

const ARENA_HALF := Vector2(1100.0, 800.0)  # 竞技场半宽/半高（原点为中心）
const WALL_MIN := 120.0
const WALL_MAX := 260.0
const MARGIN := 80.0  # 墙体距竞技场边界的最小距离
const CLEAR_RADIUS := 320.0  # 出生点周围该半径内不放墙（保证联机测试可达）


static func arena_rect() -> Rect2:
	return Rect2(-ARENA_HALF, ARENA_HALF * 2.0)


static func clamp_inside(pos: Vector2, margin: float = 0.0) -> Vector2:
	var half := ARENA_HALF - Vector2(margin, margin)
	return Vector2(clampf(pos.x, -half.x, half.x), clampf(pos.y, -half.y, half.y))


static func generate(seed_value: int, wall_count: int = 6) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var walls: Array = []
	var tries := 0
	while walls.size() < wall_count and tries < wall_count * 40:
		tries += 1
		var w := rng.randf_range(WALL_MIN, WALL_MAX)
		var h := rng.randf_range(WALL_MIN, WALL_MAX)
		var cx := rng.randf_range(-ARENA_HALF.x + MARGIN + w * 0.5, ARENA_HALF.x - MARGIN - w * 0.5)
		var cy := rng.randf_range(-ARENA_HALF.y + MARGIN + h * 0.5, ARENA_HALF.y - MARGIN - h * 0.5)
		var r := Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
		if _rect_near_center(r) or _rect_overlaps(r, walls):
			continue
		walls.append(r)
	return walls


static func blocked(walls: Array, pos: Vector2, radius: float) -> bool:
	for w in walls:
		var r: Rect2 = w
		var closest := Vector2(
			clampf(pos.x, r.position.x, r.position.x + r.size.x),
			clampf(pos.y, r.position.y, r.position.y + r.size.y)
		)
		if pos.distance_squared_to(closest) <= radius * radius:
			return true
	return false


static func _rect_near_center(r: Rect2) -> bool:
	# 矩形上离原点最近的点，若落在出生区内则判为过近
	var closest := Vector2(
		clampf(0.0, r.position.x, r.position.x + r.size.x),
		clampf(0.0, r.position.y, r.position.y + r.size.y)
	)
	return closest.length() < CLEAR_RADIUS


static func _rect_overlaps(r: Rect2, walls: Array) -> bool:
	for w in walls:
		if r.intersects(w as Rect2):
			return true
	return false
