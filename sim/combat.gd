extends RefCounted
## 战斗规则常量与纯函数（M2）。主机是唯一裁决方，客户端只负责播放。

const PLAYER_MAX_HP := 100
const ENEMY_MAX_HP := 30
const ENEMY_SPEED := 90.0
const ENEMY_RADIUS := 14.0
const ENEMY_TOUCH_DAMAGE := 8
const ENEMY_TOUCH_INTERVAL := 0.6
const PLAYER_RADIUS := 14.0
const PROJECTILE_SPEED := 520.0
const PROJECTILE_TTL := 1.5
const PROJECTILE_RADIUS := 8.0
const PROJECTILE_DAMAGE := 12
const FIRE_COOLDOWN := 0.22
const PICKUP_RADIUS := 26.0
const LOOT_MAGNET_RADIUS := 90.0
const LOOT_MAGNET_SPEED := 220.0
const SPAWN_INTERVAL := 1.5
const SPAWN_RADIUS := 420.0
const MAX_ENEMIES := 24


static func aim_dir(from: Vector2, targets: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for t in targets:
		var d: float = from.distance_to(t["pos"])
		if d < best_d:
			best_d = d
			best = t["pos"]
	if best_d == INF:
		return Vector2.ZERO
	var dir := best - from
	if dir.length() < 0.0001:
		return Vector2.ZERO
	return dir.normalized()


static func circle_hit(a: Vector2, ra: float, b: Vector2, rb: float) -> bool:
	var r := ra + rb
	return a.distance_squared_to(b) <= r * r
