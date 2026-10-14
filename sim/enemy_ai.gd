extends RefCounted
## 敌人 AI 纯逻辑（M2）：追击最近的玩家。仅主机执行。

const Combat := preload("res://sim/combat.gd")


static func chase_dir(pos: Vector2, targets: Array) -> Vector2:
	return Combat.aim_dir(pos, targets)


static func step(
	pos: Vector2, dir: Vector2, delta: float, speed: float = Combat.ENEMY_SPEED
) -> Vector2:
	return pos + dir * speed * delta
