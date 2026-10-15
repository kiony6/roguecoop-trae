extends RefCounted
## 竞技场纯逻辑。墙体已移除（2026-10-16）：地图内不再有墙，
## generate 恒返回空数组；仅保留竞技场边界与点-矩形碰撞供移动逻辑复用。

const ARENA_HALF := Vector2(1100.0, 800.0)  # 竞技场半宽/半高（原点为中心）


static func arena_rect() -> Rect2:
	return Rect2(-ARENA_HALF, ARENA_HALF * 2.0)


static func clamp_inside(pos: Vector2, margin: float = 0.0) -> Vector2:
	var half := ARENA_HALF - Vector2(margin, margin)
	return Vector2(clampf(pos.x, -half.x, half.x), clampf(pos.y, -half.y, half.y))


static func generate(_seed_value: int, _wall_count: int = 0) -> Array:
	## 地图墙体已移除：恒返回空数组（保留签名以免改动调用方与协议布局）。
	return []


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
