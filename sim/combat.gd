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

# —— 子项目 5：技能体系常量的落地部分（只加不改，保证既有测试零回归）——
const LOOT_KIND_BYTE := 2  # 字节币：技能节点生成/消耗的资源型掉落
const XP_PER_BYTE := 3  # 拾取字节币的基础经验
const BYTE_SHIELD := 30  # 「防火墙」单层护盾吸收量
const BYTE_SHIELD_INTERVAL := 6.0  # 「防火墙」护盾生成周期
const DRAIN_HEAL := 3  # 「吸血脉冲」每次命中回血量
const SUMMON_TTL := 12.0  # 「傀儡召唤」僚机存活秒数
const SUMMON_DAMAGE := 10  # 「傀儡召唤」僚机伤害

# —— 子项目 5：动态特效种类（仅走新增 FX RPC 传整数，不改任何二进制协议）——
const FX_HIT := 0  # 命中火花
const FX_CHAIN := 1  # 电弧折线
const FX_BURST := 2  # 爆裂环
const FX_PULSE := 3  # 同心波纹
const FX_NUKE := 4  # 核打击白闪 + 冲击环
const FX_LASER := 5  # 激光亮束
const FX_FROST := 6  # 冰霜锥
const FX_BURN := 7  # 灼烧焰
const FX_SHIELD := 8  # 护盾罩
const FX_DRAIN := 9  # 吸血连线
const FX_COIN := 10  # 字节币生成/拾取
const FX_LEVELUP := 11  # 升级光柱
const FX_REACTION := 12  # 元素反应爆闪
const FX_SPIKE := 13  # 尖刺锥（尖刺数据包）
const FX_CHIP := 14  # 芯片方格（芯片数据包）
const FX_BUG := 15  # BUG 腐蚀泡（BUG 机制）
const FX_NULL := 16  # 空指针十字镖（空指针 / 最弱协议处决）
const FX_SPIN := 17  # 旋转数据包
const FX_GIGA := 18  # 千兆攻冲击（超大范围）
const FX_FAULT := 19  # 测试故障扫描线
const FX_MAX := 20  # 特效种类数（供设置项遍历/单测断言）

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
	if kind == LOOT_KIND_BIG:
		return XP_PER_BIG
	if kind == LOOT_KIND_BYTE:
		return XP_PER_BYTE
	return XP_PER_SHARD
