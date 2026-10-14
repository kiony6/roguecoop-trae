extends RefCounted
## 成长系统纯逻辑（M3）：共享经验池 → 全队升级 → 每人独立抽卡。
## 主机唯一裁决；客户端只把选择回传。全部静态纯函数，无实例状态。

const Combat := preload("res://sim/combat.gd")

## 卡池。除 "id"/"name" 外的键都是修饰项：
## 整数键按加法叠加；"cooldown_scale" 按乘法叠加（越小越快）。
const CARDS: Array = [
	{"id": 0, "name": "锐利弹头", "damage_add": 4},
	{"id": 1, "name": "速射", "cooldown_scale": 0.85},
	{"id": 2, "name": "健壮", "max_hp_add": 25},
	{"id": 3, "name": "磁力", "pickup_add": 30},
	{"id": 4, "name": "散射", "extra_projectiles": 1},
	{"id": 5, "name": "回春", "heal_add": 3},
]


static func xp_to_next(level: int) -> int:
	## 升到下一级所需经验：1 级 10 点，之后每级 +8。
	return 10 + (maxi(level, 1) - 1) * 8


static func default_modifiers() -> Dictionary:
	return {
		"damage_add": 0,
		"cooldown_scale": 1.0,
		"max_hp_add": 0,
		"pickup_add": 0,
		"extra_projectiles": 0,
		"heal_add": 0,
	}


static func card_by_id(id: int) -> Dictionary:
	for c in CARDS:
		if c["id"] == id:
			return c
	return {}


static func apply_card(mods: Dictionary, card: Dictionary) -> Dictionary:
	## 纯函数：返回叠加后的新修饰字典，不修改入参。
	var out := mods.duplicate()
	for k in card.keys():
		if k == "id" or k == "name":
			continue
		if k == "cooldown_scale":
			out["cooldown_scale"] = float(out.get("cooldown_scale", 1.0)) * float(card[k])
		else:
			out[k] = int(out.get(k, 0)) + int(card[k])
	return out


static func draw_choices(rng: RandomNumberGenerator, count: int = 3) -> Array:
	## Fisher-Yates 洗牌后取前 count 张；同种子可复现（便于测试）。
	var idx: Array = []
	for i in CARDS.size():
		idx.append(i)
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var out: Array = []
	for i in mini(count, idx.size()):
		out.append(int(CARDS[idx[i]]["id"]))
	return out


static func max_hp(mods: Dictionary) -> int:
	return Combat.PLAYER_MAX_HP + int(mods.get("max_hp_add", 0))
