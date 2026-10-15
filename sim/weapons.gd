extends RefCounted
## 武器纯逻辑（M4）：武器决定开火冷却、伤害、弹丸数、散布、弹速、存活时间与弹丸半径。
## 全部静态纯函数，无实例状态。手枪参数与 M2/M3 的默认投射物一致（第 1 波零回归）。

const KIND_PISTOL := 0
const KIND_RIFLE := 1
const KIND_SHOTGUN := 2

const MAX_PROJECTILES := 64  # 主机同时在场的弹丸上限（超出则不再生成）

const KINDS: Array = [
	{
		"id": 0,
		"name": "手枪",
		"cooldown": 0.22,
		"damage": 12,
		"projectiles": 1,
		"spread": 0.0,
		"speed": 520.0,
		"ttl": 1.5,
		"radius": 8.0,
	},
	{
		"id": 1,
		"name": "步枪",
		"cooldown": 0.11,
		"damage": 9,
		"projectiles": 1,
		"spread": 0.03,
		"speed": 760.0,
		"ttl": 1.2,
		"radius": 6.0,
	},
	{
		"id": 2,
		"name": "霰弹枪",
		"cooldown": 0.55,
		"damage": 7,
		"projectiles": 5,
		"spread": 0.35,
		"speed": 460.0,
		"ttl": 0.6,
		"radius": 7.0,
	},
]


static func default_id() -> int:
	return KIND_PISTOL


static func count() -> int:
	return KINDS.size()


static func by_id(id: int) -> Dictionary:
	for w in KINDS:
		if w["id"] == id:
			return w
	return KINDS[0]


static func name_of(id: int) -> String:
	return str(by_id(id)["name"])


static func cooldown(id: int, mods: Dictionary) -> float:
	return float(by_id(id)["cooldown"]) * float(mods.get("cooldown_scale", 1.0))


static func damage(id: int, mods: Dictionary) -> int:
	return int(by_id(id)["damage"]) + int(mods.get("damage_add", 0))


static func projectile_count(id: int, mods: Dictionary) -> int:
	return int(by_id(id)["projectiles"]) + int(mods.get("extra_projectiles", 0))


static func spread(id: int) -> float:
	return float(by_id(id)["spread"])


static func speed(id: int) -> float:
	return float(by_id(id)["speed"])


static func ttl(id: int) -> float:
	return float(by_id(id)["ttl"])


static func radius(id: int) -> float:
	return float(by_id(id)["radius"])


static func reach(id: int) -> float:
	## M4.4：武器有效射程 = 弹速 × 存活时间，作为自动攻击的索敌门限。
	return speed(id) * ttl(id)
