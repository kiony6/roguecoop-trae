extends RefCounted  # gdlint:ignore=max-public-methods
## 技能节点纯逻辑（子项目 5，复刻《生存代码 Net.Attack()》的节点体系）。
## 节点分三层：触发层（TRIGGER）/ 动作层（ACTION）/ 修饰层（MOD）。
## 动作层节点通过 requires 挂到某个触发挂钩上，触发挂钩开火时其后继动作一并执行。
## 全部静态纯函数，无实例状态；供 net_host（权威结算）与技能树 UI（展示/解锁）共用。

const Weapons := preload("res://sim/weapons.gd")

# —— 节点分层 ——
const LAYER_TRIGGER := 0
const LAYER_ACTION := 1
const LAYER_MOD := 2
const LAYER_LOGIC := 3  # 条件/循环层：夹在触发与动作之间，回答「什么条件下放 / 放几次」

# —— 条件分支（《生存代码》的 Conditional 节点）——
## 条件在权威侧（net_host）按玩家实时状态判定；不满足则该后继动作整条跳过。
const COND_NONE := 0
const COND_LOW_HP := 1  # 自身生命比例 ≤ count（百分比）
const COND_BYTES := 2  # 持有字节币 ≥ count
const COND_ENEMIES := 3  # 场上敌人 ≥ count
const COND_WAVE := 4  # 波次 ≥ count

# —— 触发事件（对应《生存代码》的 in / OnKill 前缀）——
const TRIG_INTERVAL := 0  # 周期触发（遍历、字节农场）
const TRIG_HIT := 1  # 命中敌人
const TRIG_KILL := 2  # 击杀敌人
const TRIG_PICKUP := 3  # 拾取掉落
const TRIG_HURT := 4  # 自身受伤
const TRIG_FIRE := 5  # 开火

# —— 元素 ——
const ELEM_PHYS := 0
const ELEM_FIRE := 1
const ELEM_FROST := 2
const ELEM_ELEC := 3

# 元素状态挂在敌人身上的持续时长；以及单次稀疏同步的条目上限（元素状态走独立 RPC，不动快照线格式）
const ELEMENT_SECONDS := 3.0
const MAX_ELEMENT_SYNC := 32

# —— 节点效果 ——
const EFF_NONE := 0
const EFF_SPAWN_BYTE := 1  # 字节农场：生成字节币
const EFF_SINGLE_DMG := 2  # 数据弹：单体高伤
const EFF_BYTE_BURST := 3  # 字节爆裂：引爆 1 枚，固定伤害
const EFF_BYTE_STORM := 4  # 字节风暴：引爆全部，固定伤害 + 链式
const EFF_BYTE_PULSE := 5  # 字节脉冲：全屏 AoE
const EFF_NUKE := 6  # 核打击：大范围高伤
const EFF_ORBIT := 7  # 环绕卫星
const EFF_LASER := 8  # 激光扫射
const EFF_SPLIT := 9  # 分叉弹
const EFF_HOMING := 10  # 追踪导弹
const EFF_MINE := 11  # 数据雷
const EFF_SHIELD := 12  # 防火墙（护盾）
const EFF_DRAIN := 13  # 吸血脉冲
const EFF_SUMMON := 14  # 傀儡召唤
const EFF_ADD_DAMAGE := 15  # 修饰：全局伤害 +
const EFF_HASTE := 16  # 修饰：攻速 ×
const EFF_AREA := 17  # 修饰：范围 ×
const EFF_PIERCE := 18  # 修饰：穿透 +
const EFF_BOUNCE := 19  # 修饰：弹射 +
const EFF_ELEM := 20  # 修饰：附加元素
const EFF_CHAIN := 21  # 修饰：链式跳数 +
const EFF_BYTE_GAIN := 22  # 修饰：字节币效益 ×
const EFF_PICKUP := 23  # 修饰：拾取半径 +

# —— 条件/循环层效果 ——
const EFF_CONDITION := 24  # 条件分支：满足 cond 才放后继
const EFF_LOOP := 25  # 循环：后继动作重复 count 次（上限 3）

# —— 标志性节点效果（复刻《生存代码》各 Hacker 的招牌）——
const EFF_SPIKE := 26  # 尖刺数据包：一排尖刺弹
const EFF_CHIP := 27  # 芯片数据包：命中后留下伤害区域
const EFF_BUG := 28  # BUG 机制：击杀后向附近扩散病毒
const EFF_NULL := 29  # 空指针：受伤时近身高额反击
const EFF_WEAKEST := 30  # 最弱协议：定期斩击血量比例最低的敌人
const EFF_GIGA := 31  # 千兆攻击：长冷却超大范围
const EFF_FAULT := 32  # 测试故障：受伤触发全屏故障波
const EFF_SPIN := 33  # 旋转数据包：更大半径的环绕弹群
const EFF_MINE_COPY := 34  # 地雷复制：击杀时连埋多枚数据雷
const EFF_OVERKILL := 35  # 修饰：超杀——击杀时的溢出伤害转化为 AoE
const EFF_EVOLVE := 36  # 修饰：进化脉冲——伤害随波次递增

## 字节币：节点消耗/引爆的资源，也是一种掉落（Combat.LOOT_KIND_BYTE）。
const BYTE_KIND_MAX := 12  # 单玩家当场字节币硬上限（防无上限累积拖垮主机）

## 循环层单次重复上限（防「循环」被叠成无限递归，对齐掉落无上限的历史教训）。
const MAX_LOOPS := 3

## 技能弹丸 kind（供表现层与主机共用同一套 id；kind 0-2 仍属 Weapons）。
const PROJ_DATA := 8  # 数据弹
const PROJ_ORBIT := 9  # 环绕卫星
const PROJ_LASER := 10  # 激光扫射
const PROJ_SPLIT := 11  # 分叉弹
const PROJ_HOMING := 12  # 追踪导弹
const PROJ_MINE := 13  # 数据雷
const PROJ_SPIKE := 14  # 尖刺弹（尖刺数据包）

## 技能弹丸表：kind 8+ 由技能生成；kind 0-2 仍回退 Weapons（零回归）。
const PROJECTILES := {
	PROJ_DATA: {"radius": 9.0, "speed": 600.0, "ttl": 1.4},
	PROJ_ORBIT: {"radius": 8.0, "speed": 0.0, "ttl": 0.0},  # 环绕卫星（由主机自行驱动）
	PROJ_LASER: {"radius": 12.0, "speed": 900.0, "ttl": 0.5},
	PROJ_SPLIT: {"radius": 7.0, "speed": 560.0, "ttl": 1.0},
	PROJ_HOMING: {"radius": 8.0, "speed": 420.0, "ttl": 2.0},
	PROJ_MINE: {"radius": 10.0, "speed": 0.0, "ttl": 3.0},  # 数据雷
	PROJ_SPIKE: {"radius": 5.0, "speed": 760.0, "ttl": 1.1},  # 尖刺弹（窄长、快）
}

## 节点表。字段：id/name/layer/trigger/effect/element/damage/radius/count/interval/ttl/
## speed/tier/requires/cost/desc。requires 为前置节点 id 列表。
const NODES: Array = [
	# —— TRIGGER 触发层（6）——
	{
		"id": 0,
		"name": "遍历",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_NONE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 1.2,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "每 1.2 秒触发一次后继节点"
	},
	{
		"id": 1,
		"name": "字节农场",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_SPAWN_BYTE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 2.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "每 2.0 秒生成 1 枚字节币"
	},
	{
		"id": 2,
		"name": "命中挂钩",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_HIT,
		"effect": EFF_NONE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "命中敌人时触发后继节点"
	},
	{
		"id": 3,
		"name": "击杀挂钩",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_KILL,
		"effect": EFF_NONE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "击杀敌人时触发后继节点"
	},
	{
		"id": 4,
		"name": "拾取挂钩",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_PICKUP,
		"effect": EFF_NONE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "拾取字节币时触发后继节点"
	},
	{
		"id": 5,
		"name": "受击挂钩",
		"layer": LAYER_TRIGGER,
		"trigger": TRIG_HURT,
		"effect": EFF_NONE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 0,
		"requires": [],
		"cost": 1,
		"desc": "自身受伤时触发后继节点"
	},
	# —— ACTION 动作层（13）——
	{
		"id": 8,
		"name": "数据弹",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_SINGLE_DMG,
		"element": ELEM_PHYS,
		"damage": 14,
		"radius": 9.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 1.4,
		"speed": 600.0,
		"tier": 1,
		"requires": [2],
		"cost": 1,
		"desc": "单体高伤弹丸（伤害高、范围小）"
	},
	{
		"id": 9,
		"name": "字节爆裂",
		"layer": LAYER_ACTION,
		"trigger": TRIG_PICKUP,
		"effect": EFF_BYTE_BURST,
		"element": ELEM_PHYS,
		"damage": 20,
		"radius": 70.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [4],
		"cost": 1,
		"desc": "引爆 1 枚字节币，固定伤害 20（不可增幅）"
	},
	{
		"id": 10,
		"name": "字节风暴",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_BYTE_STORM,
		"element": ELEM_PHYS,
		"damage": 24,
		"radius": 90.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [1],
		"cost": 1,
		"desc": "引爆全部字节币，固定伤害 24，击杀后链式再触发"
	},
	{
		"id": 11,
		"name": "字节脉冲",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_BYTE_PULSE,
		"element": ELEM_PHYS,
		"damage": 30,
		"radius": 900.0,
		"count": 1,
		"interval": 8.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [0],
		"cost": 1,
		"desc": "全屏字节脉冲，固定伤害 30，冷却 8 秒"
	},
	{
		"id": 12,
		"name": "核打击",
		"layer": LAYER_ACTION,
		"trigger": TRIG_KILL,
		"effect": EFF_NUKE,
		"element": ELEM_PHYS,
		"damage": 60,
		"radius": 220.0,
		"count": 1,
		"interval": 12.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [3],
		"cost": 1,
		"desc": "大范围高伤 60 并伴随屏幕震动，冷却 12 秒"
	},
	{
		"id": 13,
		"name": "环绕卫星",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_ORBIT,
		"element": ELEM_PHYS,
		"damage": 8,
		"radius": 8.0,
		"count": 3,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [0],
		"cost": 1,
		"desc": "3 枚卫星绕自身旋转持续伤害"
	},
	{
		"id": 14,
		"name": "激光扫射",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_LASER,
		"element": ELEM_PHYS,
		"damage": 10,
		"radius": 12.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.5,
		"speed": 900.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "穿透光束，单发贯穿多个敌人"
	},
	{
		"id": 15,
		"name": "分叉弹",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_SPLIT,
		"element": ELEM_PHYS,
		"damage": 8,
		"radius": 7.0,
		"count": 3,
		"interval": 0.0,
		"ttl": 1.0,
		"speed": 560.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "命中后分裂出 3 枚子弹"
	},
	{
		"id": 16,
		"name": "追踪导弹",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_HOMING,
		"element": ELEM_PHYS,
		"damage": 16,
		"radius": 8.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 2.0,
		"speed": 420.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "自动转向锁定最近的敌人"
	},
	{
		"id": 17,
		"name": "数据雷",
		"layer": LAYER_ACTION,
		"trigger": TRIG_KILL,
		"effect": EFF_MINE,
		"element": ELEM_PHYS,
		"damage": 22,
		"radius": 60.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 3.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [3],
		"cost": 1,
		"desc": "落地定时引爆的范围雷"
	},
	{
		"id": 18,
		"name": "防火墙",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HURT,
		"effect": EFF_SHIELD,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 6.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [5],
		"cost": 1,
		"desc": "每 6 秒生成一层吸收护盾"
	},
	{
		"id": 19,
		"name": "吸血脉冲",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_DRAIN,
		"element": ELEM_PHYS,
		"damage": 6,
		"radius": 70.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "命中敌人时回复少量生命"
	},
	{
		"id": 20,
		"name": "傀儡召唤",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_SUMMON,
		"element": ELEM_PHYS,
		"damage": 10,
		"radius": 0.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 12.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [0],
		"cost": 1,
		"desc": "召唤 1 个持续 12 秒的临时僚机"
	},
	# —— MOD 修饰层（11）——
	{
		"id": 24,
		"name": "溢出伤害",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_ADD_DAMAGE,
		"element": ELEM_PHYS,
		"damage": 4,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [],
		"cost": 1,
		"desc": "全部技能伤害 +4"
	},
	{
		"id": 25,
		"name": "超频",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_HASTE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [],
		"cost": 1,
		"desc": "技能触发间隔 ×0.85（更快开火）"
	},
	{
		"id": 26,
		"name": "范围扩张",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_AREA,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [],
		"cost": 1,
		"desc": "全部 AoE 半径 ×1.25"
	},
	{
		"id": 27,
		"name": "穿透",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_PIERCE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [],
		"cost": 1,
		"desc": "弹丸穿透 +1"
	},
	{
		"id": 28,
		"name": "弹射",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_BOUNCE,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [],
		"cost": 1,
		"desc": "弹丸弹射 +1"
	},
	{
		"id": 29,
		"name": "灼烧",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_ELEM,
		"element": ELEM_FIRE,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [],
		"cost": 1,
		"desc": "攻击附加火元素，命中后持续燃烧"
	},
	{
		"id": 30,
		"name": "冰霜",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_ELEM,
		"element": ELEM_FROST,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [],
		"cost": 1,
		"desc": "攻击附加冰元素，命中后减速"
	},
	{
		"id": 31,
		"name": "电弧",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_ELEM,
		"element": ELEM_ELEC,
		"damage": 0,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [],
		"cost": 1,
		"desc": "攻击附加电元素，命中后跳链导电"
	},
	{
		"id": 32,
		"name": "串联",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_CHAIN,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [],
		"cost": 1,
		"desc": "链式触发跳数 +1（上限 3）"
	},
	{
		"id": 33,
		"name": "字节币效益",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_BYTE_GAIN,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 0.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [],
		"cost": 1,
		"desc": "字节币经验与触发效率 +25%（攻略首选）"
	},
	{
		"id": 34,
		"name": "拾取半径",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_PICKUP,
		"element": ELEM_PHYS,
		"damage": 0,
		"radius": 40.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 1,
		"requires": [],
		"cost": 1,
		"desc": "拾取半径 +40（注意：会打乱输出节奏，攻略建议默认不点）"
	},
	# —— LOGIC 条件/循环层（2）——
	{
		"id": 35,
		"name": "条件分支",
		"layer": LAYER_LOGIC,
		"trigger": -1,
		"effect": EFF_CONDITION,
		"element": ELEM_PHYS,
		"cond": COND_LOW_HP,
		"damage": 0,
		"radius": 0.0,
		"count": 50,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [5],
		"cost": 1,
		"desc": "自身生命 ≤50% 时才放行后继动作（挂在受击挂钩下，濒死反打）"
	},
	{
		"id": 36,
		"name": "循环",
		"layer": LAYER_LOGIC,
		"trigger": -1,
		"effect": EFF_LOOP,
		"element": ELEM_PHYS,
		"cond": COND_NONE,
		"damage": 0,
		"radius": 0.0,
		"count": 2,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [0],
		"cost": 1,
		"desc": "后继动作每次触发执行 2 遍（上限 3，挂在遍历下）"
	},
	# —— ACTION 标志性节点（9）——
	{
		"id": 37,
		"name": "尖刺数据包",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_SPIKE,
		"element": ELEM_PHYS,
		"damage": 10,
		"radius": 5.0,
		"count": 3,
		"interval": 0.0,
		"ttl": 1.1,
		"speed": 760.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "扇形射出 3 枚窄长尖刺，单发伤害低、穿透强"
	},
	{
		"id": 38,
		"name": "芯片数据包",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HIT,
		"effect": EFF_CHIP,
		"element": ELEM_PHYS,
		"damage": 12,
		"radius": 45.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [2],
		"cost": 1,
		"desc": "命中后在原地植入一块持续伤害区域"
	},
	{
		"id": 39,
		"name": "BUG 机制",
		"layer": LAYER_ACTION,
		"trigger": TRIG_KILL,
		"effect": EFF_BUG,
		"element": ELEM_ELEC,
		"damage": 8,
		"radius": 70.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [3],
		"cost": 1,
		"desc": "击杀后把 BUG 病毒扩散给附近的敌人（附带电元素）"
	},
	{
		"id": 40,
		"name": "空指针",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HURT,
		"effect": EFF_NULL,
		"element": ELEM_PHYS,
		"damage": 40,
		"radius": 24.0,
		"count": 1,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [35],
		"cost": 1,
		"desc": "受伤时近身高额反击：对贴身敌人造成 40 伤害（经条件分支放行）"
	},
	{
		"id": 41,
		"name": "最弱协议",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_WEAKEST,
		"element": ELEM_PHYS,
		"damage": 25,
		"radius": 0.0,
		"count": 1,
		"interval": 3.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [36],
		"cost": 1,
		"desc": "每 3 秒锁定血量比例最低的敌人造成 25 伤害（处决，经循环放行）"
	},
	{
		"id": 42,
		"name": "千兆攻击",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_GIGA,
		"element": ELEM_PHYS,
		"damage": 45,
		"radius": 260.0,
		"count": 1,
		"interval": 15.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [36],
		"cost": 1,
		"desc": "冷却 15 秒的超大范围重击（半径 260，经循环放行）"
	},
	{
		"id": 43,
		"name": "测试故障",
		"layer": LAYER_ACTION,
		"trigger": TRIG_HURT,
		"effect": EFF_FAULT,
		"element": ELEM_FIRE,
		"damage": 12,
		"radius": 400.0,
		"count": 1,
		"interval": 10.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [35],
		"cost": 1,
		"desc": "受伤时触发全屏故障波，伤害所有敌人并附带火元素（经条件分支放行）"
	},
	{
		"id": 44,
		"name": "旋转数据包",
		"layer": LAYER_ACTION,
		"trigger": TRIG_INTERVAL,
		"effect": EFF_SPIN,
		"element": ELEM_PHYS,
		"damage": 6,
		"radius": 130.0,
		"count": 6,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [36],
		"cost": 1,
		"desc": "6 枚数据包绕自身旋转，命中半径比环绕卫星更大（经循环放行）"
	},
	{
		"id": 45,
		"name": "地雷复制",
		"layer": LAYER_ACTION,
		"trigger": TRIG_KILL,
		"effect": EFF_MINE_COPY,
		"element": ELEM_PHYS,
		"damage": 22,
		"radius": 60.0,
		"count": 2,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 2,
		"requires": [3],
		"cost": 1,
		"desc": "击杀时连埋 2 枚数据雷（加固版：伤害 22 / 半径 60）"
	},
	# —— MOD 标志性修饰（2）——
	{
		"id": 46,
		"name": "超杀",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_OVERKILL,
		"element": ELEM_PHYS,
		"cond": COND_NONE,
		"damage": 0,
		"radius": 60.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [],
		"cost": 1,
		"desc": "击杀时把溢出伤害炸成半径 60 的 AoE（过量伤害不浪费）"
	},
	{
		"id": 47,
		"name": "进化脉冲",
		"layer": LAYER_MOD,
		"trigger": -1,
		"effect": EFF_EVOLVE,
		"element": ELEM_PHYS,
		"cond": COND_NONE,
		"damage": 10,
		"radius": 0.0,
		"count": 0,
		"interval": 0.0,
		"ttl": 0.0,
		"speed": 0.0,
		"tier": 3,
		"requires": [],
		"cost": 1,
		"desc": "技能伤害每提升 1 个波次额外 +10%（越打越强）"
	},
]

## 初始构筑预设（13 个，替代《生存代码》的 13 个 Hacker 角色专属起手组）。
const PRESETS := [
	{"id": "COIN", "name": "字节币流", "nodes": [0, 1, 9], "desc": "遍历 + 字节农场 + 字节爆裂：靠字节币循环滚雪球"},
	{"id": "BULLET", "name": "弹幕流", "nodes": [2, 8, 25], "desc": "命中挂钩 + 数据弹 + 超频：高频单体输出"},
	{"id": "AOE", "name": "爆破流", "nodes": [1, 10, 26], "desc": "字节农场 + 字节风暴 + 范围扩张：全场范围清怪"},
	{"id": "SPIKE", "name": "尖刺流", "nodes": [2, 37, 27], "desc": "命中挂钩 + 尖刺数据包 + 穿透：窄长尖刺成排贯穿"},
	{"id": "CHIP", "name": "芯片流", "nodes": [2, 38, 26], "desc": "命中挂钩 + 芯片数据包 + 范围扩张：命中即布伤害区"},
	{"id": "BUG", "name": "病毒流", "nodes": [3, 39, 32], "desc": "击杀挂钩 + BUG 机制 + 串联：击杀后病毒连片扩散"},
	{"id": "NULL", "name": "空指针流", "nodes": [5, 40, 18], "desc": "受击挂钩 + 空指针 + 防火墙：挨打就越狠反击越稳"},
	{"id": "WEAK", "name": "猎杀流", "nodes": [0, 41, 24], "desc": "遍历 + 最弱协议 + 溢出伤害：定期处决最弱目标"},
	{"id": "GIGA", "name": "千兆流", "nodes": [0, 42, 26], "desc": "遍历 + 千兆攻击 + 范围扩张：长冷却超大范围重击"},
	{"id": "FAULT", "name": "故障流", "nodes": [5, 43, 18], "desc": "受击挂钩 + 测试故障 + 防火墙：受伤就全场故障波"},
	{"id": "SPIN", "name": "旋转流", "nodes": [0, 44, 13], "desc": "遍历 + 旋转数据包 + 环绕卫星：贴身环绕持续磨血"},
	{"id": "MINE", "name": "布雷流", "nodes": [3, 45, 17], "desc": "击杀挂钩 + 地雷复制 + 数据雷：边打边埋雷封锁走位"},
	{"id": "EVOLVE", "name": "进化流", "nodes": [0, 47, 11], "desc": "遍历 + 进化脉冲 + 字节脉冲：伤害随波次节节攀升"},
]

## 元素反应表（隐藏机制）。键为两个元素的升序对。
const REACTIONS := [
	{
		"a": ELEM_FIRE,
		"b": ELEM_FROST,
		"name": "蒸汽爆裂",
		"radius": 90.0,
		"damage": 25,
		"desc": "半径 90 的蒸汽爆炸"
	},
	{
		"a": ELEM_FROST,
		"b": ELEM_ELEC,
		"name": "超导",
		"radius": 120.0,
		"damage": 15,
		"desc": "传导至半径 120 内全部敌人"
	},
	{"a": ELEM_FIRE, "b": ELEM_ELEC, "name": "等离子", "radius": 0.0, "damage": 50, "desc": "单体高额爆发"},
]


static func count() -> int:
	return NODES.size()


static func all() -> Array:
	return NODES


static func by_id(id: int) -> Dictionary:
	for n in NODES:
		if n["id"] == id:
			return n
	return {}


static func has_node(id: int) -> bool:
	return not by_id(id).is_empty()


static func name_of(id: int) -> String:
	var n := by_id(id)
	return "" if n.is_empty() else str(n["name"])


static func layer_of(id: int) -> int:
	var n := by_id(id)
	return -1 if n.is_empty() else int(n["layer"])


static func nodes_of_layer(layer: int) -> Array:
	var out: Array = []
	for n in NODES:
		if n["layer"] == layer:
			out.append(n)
	return out


static func cost_of(id: int) -> int:
	var n := by_id(id)
	return 0 if n.is_empty() else int(n["cost"])


static func can_unlock(unlocked: Array, id: int, points: int) -> bool:
	## 解锁门禁：未知节点 / 已解锁 / 技能点不足 → 否；
	## 动作层需其全部前置触发挂钩已解锁；修饰层需至少解锁任一动作。
	var node := by_id(id)
	if node.is_empty():
		return false
	if unlocked.has(id):
		return false
	if points < int(node["cost"]):
		return false
	var layer := int(node["layer"])
	if layer == LAYER_ACTION or layer == LAYER_LOGIC:
		var reqs: Array = node["requires"]
		for r in reqs:
			if not unlocked.has(int(r)):
				return false
	if layer == LAYER_MOD:
		if _first_action(unlocked) < 0:
			return false
	return true


static func unlock(unlocked: Array, id: int) -> Array:
	## 纯函数：返回追加该节点后的新数组（不修改入参，不去重由 can_unlock 负责）。
	var out := unlocked.duplicate()
	out.append(id)
	return out


static func grant(unlocked: Array, ids: Array) -> Array:
	## 初始构筑直接授予一组节点（跳过 can_unlock 的前置校验）。
	var out := unlocked.duplicate()
	for id in ids:
		if not out.has(int(id)):
			out.append(int(id))
	return out


static func triggers_of(unlocked: Array) -> Array:
	var out: Array = []
	for id in unlocked:
		if layer_of(int(id)) == LAYER_TRIGGER:
			out.append(int(id))
	return out


static func actions_of(unlocked: Array) -> Array:
	var out: Array = []
	for id in unlocked:
		if layer_of(int(id)) == LAYER_ACTION:
			out.append(int(id))
	return out


static func mods_of(unlocked: Array) -> Array:
	var out: Array = []
	for id in unlocked:
		if layer_of(int(id)) == LAYER_MOD:
			out.append(int(id))
	return out


static func trigger_nodes_for(event: int) -> Array:
	## 事件 → 可能响应的触发节点。同一事件可有多个（遍历与字节农场同为周期触发）。
	var out: Array = []
	for n in NODES:
		if n["layer"] == LAYER_TRIGGER and int(n["trigger"]) == event:
			out.append(int(n["id"]))
	return out


static func actions_for(unlocked: Array, trigger_id: int) -> Array:
	## 挂在某触发挂钩下的（已解锁）动作节点。
	var out: Array = []
	for id in unlocked:
		var node := by_id(int(id))
		if node.is_empty() or int(node["layer"]) != LAYER_ACTION:
			continue
		if (node["requires"] as Array).has(trigger_id):
			out.append(int(id))
	return out


static func logic_for(unlocked: Array, trigger_id: int) -> Array:
	## 挂在某触发挂钩下的（已解锁）条件/循环节点。
	var out: Array = []
	for id in unlocked:
		var node := by_id(int(id))
		if node.is_empty() or int(node["layer"]) != LAYER_LOGIC:
			continue
		if (node["requires"] as Array).has(trigger_id):
			out.append(int(id))
	return out


static func chain_for(unlocked: Array, trigger_id: int) -> Array:
	## 把「触发 →（可选 条件/循环）→ 动作」解成可执行步骤列表。
	## 每步 = {node, cond, cond_value, loops}：直连触发的动作 cond=COND_NONE、loops=1；
	## 绕过条件/循环节点的动作带上该节点的条件与重复次数。
	## 条件语义留给权威侧（net_host）按玩家实时状态裁决，runtime 保持纯逻辑。
	var out: Array = []
	for id in actions_for(unlocked, trigger_id):
		out.append({"node": id, "cond": COND_NONE, "cond_value": 0, "loops": 1})
	for lid in logic_for(unlocked, trigger_id):
		var lnode := by_id(lid)
		var cond := int(lnode.get("cond", COND_NONE))
		var loops := 1
		if int(lnode["effect"]) == EFF_LOOP:
			loops = clampi(int(lnode["count"]), 1, MAX_LOOPS)
		for id in unlocked:
			var node := by_id(int(id))
			if node.is_empty() or int(node["layer"]) != LAYER_ACTION:
				continue
			if not (node["requires"] as Array).has(lid):
				continue
			(
				out
				. append(
					{
						"node": int(id),
						"cond": cond,
						"cond_value": int(lnode["count"]),
						"loops": loops,
					}
				)
			)
	return out


static func modifiers(unlocked: Array) -> Dictionary:
	## 聚合修饰层效果为一份数值表，供 skill_runtime 叠加到动作指令上。
	var m := {
		"damage_add": 0,
		"cooldown_scale": 1.0,
		"radius_scale": 1.0,
		"pierce": 0,
		"bounce": 0,
		"chain_bonus": 0,
		"byte_gain": 1.0,
		"pickup_add": 0.0,
		"elements": [],
		"wave_damage": 0,
		"overkill_radius": 0.0,
	}
	for id in unlocked:
		var node := by_id(int(id))
		if node.is_empty() or int(node["layer"]) != LAYER_MOD:
			continue
		match int(node["effect"]):
			EFF_ADD_DAMAGE:
				m["damage_add"] = int(m["damage_add"]) + int(node["damage"])
			EFF_HASTE:
				m["cooldown_scale"] = float(m["cooldown_scale"]) * 0.85
			EFF_AREA:
				m["radius_scale"] = float(m["radius_scale"]) * 1.25
			EFF_PIERCE:
				m["pierce"] = int(m["pierce"]) + int(node["count"])
			EFF_BOUNCE:
				m["bounce"] = int(m["bounce"]) + int(node["count"])
			EFF_CHAIN:
				m["chain_bonus"] = int(m["chain_bonus"]) + int(node["count"])
			EFF_BYTE_GAIN:
				m["byte_gain"] = float(m["byte_gain"]) * 1.25
			EFF_PICKUP:
				m["pickup_add"] = float(m["pickup_add"]) + float(node["radius"])
			EFF_ELEM:
				var elems: Array = m["elements"]
				if not elems.has(int(node["element"])):
					elems.append(int(node["element"]))
			EFF_OVERKILL:
				m["overkill_radius"] = maxf(float(m["overkill_radius"]), float(node["radius"]))
			EFF_EVOLVE:
				m["wave_damage"] = int(m["wave_damage"]) + int(node["damage"])
	return m


static func projectile_radius(kind: int) -> float:
	## 统一弹丸半径查询：技能弹（kind 8+）走本表，武器弹（0-2）回退 Weapons。
	if PROJECTILES.has(kind):
		return float(PROJECTILES[kind]["radius"])
	return Weapons.radius(kind)


static func projectile(kind: int) -> Dictionary:
	if PROJECTILES.has(kind):
		return PROJECTILES[kind]
	return {}


static func reaction(a: int, b: int) -> Dictionary:
	## 元素反应查询；无反应（含纯物理）返回空字典。
	for r in REACTIONS:
		var match_ab: bool = int(r["a"]) == a and int(r["b"]) == b
		var match_ba: bool = int(r["a"]) == b and int(r["b"]) == a
		if match_ab or match_ba:
			return r
	return {}


static func presets() -> Array:
	return PRESETS


static func preset(id: String) -> Dictionary:
	for p in PRESETS:
		if String(p["id"]) == id:
			return p
	return {}


static func default_preset() -> String:
	return String(PRESETS[0]["id"])


static func preset_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in PRESETS:
		out.append(String(p["id"]))
	return out


static func _first_action(unlocked: Array) -> int:
	for id in unlocked:
		if layer_of(int(id)) == LAYER_ACTION:
			return int(id)
	return -1

# gdlint:ignore=max-file-lines
