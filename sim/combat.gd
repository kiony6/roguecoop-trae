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

# —— M4.1：掉落有界化（防止无上限累积拖垮主机） ——
const LOOT_TTL := 12.0  # 掉落自生成起的存活秒数，到期未被拾取即消失
const MAX_LOOT := 200  # 全场掉落硬上限，超限先淘汰最旧的

# —— M3：敌人种类与 Boss ——
const ENEMY_KIND_NORMAL := 0
const ENEMY_KIND_BOSS := 1
const BOSS_MAX_HP := 200
const BOSS_SPEED := 70.0
const BOSS_RADIUS := 28.0
const BOSS_TOUCH_DAMAGE := 20
const BOSS_TOUCH_INTERVAL := 0.8
const BOSS_EVERY_KILLS := 15  # 每累计击杀这么多普通怪刷新 1 只 Boss
const WIN_BOSS_KILLS := 3  # 击败这么多 Boss 即胜利结算

# —— M3：掉落种类与经验 ——
const LOOT_KIND_XP := 0  # 普通经验碎片
const LOOT_KIND_BIG := 1  # Boss 大碎片
const XP_PER_SHARD := 5
const XP_PER_BIG := 25

# —— M3：倒地与救援 ——
# M4.3：去掉流血永久阵亡——只要还有存活队友，倒地者可无限期/无限次被救起。
const PLAYER_ALIVE := 0
const PLAYER_DOWNED := 1
const PLAYER_DEAD := 2  # 保留：仍被绘制与升级下发过滤引用，但不再由流血触发
const REVIVE_HP := 50  # 被救起后恢复到的血量
const REVIVE_RADIUS := 46.0  # 队友需在此半径内才能推进救援
const REVIVE_HOLD := 2.0  # 需持续贴近的秒数
const REVIVE_INVULN := 1.5  # 救起后的短暂无敌


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


static func enemy_max_hp(kind: int) -> int:
	return BOSS_MAX_HP if kind == ENEMY_KIND_BOSS else ENEMY_MAX_HP


static func enemy_speed(kind: int) -> float:
	return BOSS_SPEED if kind == ENEMY_KIND_BOSS else ENEMY_SPEED


static func enemy_radius(kind: int) -> float:
	return BOSS_RADIUS if kind == ENEMY_KIND_BOSS else ENEMY_RADIUS


static func enemy_touch_damage(kind: int) -> int:
	return BOSS_TOUCH_DAMAGE if kind == ENEMY_KIND_BOSS else ENEMY_TOUCH_DAMAGE


static func enemy_touch_interval(kind: int) -> float:
	return BOSS_TOUCH_INTERVAL if kind == ENEMY_KIND_BOSS else ENEMY_TOUCH_INTERVAL


static func loot_xp(kind: int) -> int:
	return XP_PER_BIG if kind == LOOT_KIND_BIG else XP_PER_SHARD
