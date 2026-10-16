extends RefCounted  # gdlint:ignore=max-public-methods
## 技能运行时执行器（子项目 5）：把「触发事件」翻译成一串「动作指令」。
## 纯逻辑、可无头单测；由 net_host 在权威侧驱动，主机决定这些指令如何落地。
##
## 设计要点（对齐《生存代码》拖拽节点的链式手感，并防爆）：
##   - 触发链：事件 → 触发挂钩 → 其后继动作；部分动作（字节风暴）会再次发出事件形成链式；
##   - 跳数上限 MAX_CHAIN_JUMPS（默认 2，解锁「串联」后 3），杜绝无限递归；
##   - 每个触发节点每秒最多开火 1 次（NODE_FIRE_COOLDOWN），
##     避免「掉落无上限累积拖垮主机」的历史教训在技能链上重演。

const Skills := preload("res://sim/skills.gd")

const BASE_CHAIN_JUMPS := 2
const MAX_CHAIN_JUMPS := 3
const NODE_FIRE_COOLDOWN := 1.0


static func new_state() -> Dictionary:
	## 每位玩家一份：acc = 周期触发节点的计时器；cd = 触发节点下次可开火时刻（秒）。
	return {"acc": {}, "cd": {}}


static func chain_jumps(unlocked: Array) -> int:
	## 允许的链式跳数上限：基础 2，解锁「串联」+1，硬上限 3。
	var m := Skills.modifiers(unlocked)
	return mini(MAX_CHAIN_JUMPS, BASE_CHAIN_JUMPS + int(m["chain_bonus"]))


static func tick(state: Dictionary, unlocked: Array, delta: float, now: float) -> Array:
	## 周期推进一步：为每个已解锁的周期触发节点累计计时，到点即开火。
	var out: Array = []
	var acc: Dictionary = state["acc"]
	for id in unlocked:
		var node := Skills.by_id(int(id))
		if node.is_empty() or int(node["trigger"]) != Skills.TRIG_INTERVAL:
			continue
		var period := float(node["interval"]) / _haste(unlocked)
		if period <= 0.0:
			continue
		var cur: float = float(acc.get(int(id), 0.0)) + delta
		if cur >= period:
			cur -= period
			_fire(state, unlocked, int(id), now, 0, out)
		acc[int(id)] = cur
	return out


static func dispatch(state: Dictionary, unlocked: Array, event: int, now: float) -> Array:
	## 事件驱动的即时触发（命中/击杀/拾取/受伤）。
	var out: Array = []
	_fire_event(state, unlocked, event, now, 0, out)
	return out


static func _fire_event(
	state: Dictionary, unlocked: Array, event: int, now: float, jump: int, out: Array
) -> void:
	for id in Skills.trigger_nodes_for(event):
		if not unlocked.has(int(id)):
			continue
		_fire(state, unlocked, int(id), now, jump, out)


static func _fire(
	state: Dictionary, unlocked: Array, trigger_id: int, now: float, jump: int, out: Array
) -> void:
	if jump > chain_jumps(unlocked):
		return
	var cd: Dictionary = state["cd"]
	if float(cd.get(trigger_id, -INF)) > now:
		return
	cd[trigger_id] = now + NODE_FIRE_COOLDOWN
	var node := Skills.by_id(trigger_id)
	var mods := Skills.modifiers(unlocked)
	if int(node["effect"]) == Skills.EFF_SPAWN_BYTE:
		(
			out
			. append(
				{
					"node": trigger_id,
					"effect": Skills.EFF_SPAWN_BYTE,
					"element": Skills.ELEM_PHYS,
					"damage": 0,
					"radius": 0.0,
					"count": int(node["count"]),
					"chained": jump > 0,
				}
			)
		)
	for step in Skills.chain_for(unlocked, trigger_id):
		var anode := Skills.by_id(int(step["node"]))
		out.append(
			_command(
				anode, mods, jump, int(step["cond"]), int(step["cond_value"]), int(step["loops"])
			)
		)
		if int(anode["effect"]) == Skills.EFF_BYTE_STORM:
			# 字节风暴「引爆全部 → 击杀 → 再触发」的链式手感
			_fire_event(state, unlocked, Skills.TRIG_KILL, now + 0.0001, jump + 1, out)


static func _command(
	node: Dictionary, mods: Dictionary, jump: int, cond: int, cond_value: int, loops: int
) -> Dictionary:
	var elems: Array = []
	var base := int(node["element"])
	if base != Skills.ELEM_PHYS:
		elems.append(base)
	for e in mods["elements"]:
		if not elems.has(int(e)):
			elems.append(int(e))
	if elems.is_empty():
		elems.append(Skills.ELEM_PHYS)
	return {
		"node": int(node["id"]),
		"effect": int(node["effect"]),
		"element": elems[0],
		"elements": elems,
		"damage": int(node["damage"]) + int(mods["damage_add"]),
		"damage_base": int(node["damage"]),  # 固定伤害类效果（字节爆裂/风暴/脉冲）用此值
		"radius": float(node["radius"]) * float(mods["radius_scale"]),
		"count": int(node["count"]),
		"interval": float(node["interval"]),
		"ttl": float(node["ttl"]),
		"speed": float(node["speed"]),
		"pierce": int(mods["pierce"]),
		"bounce": int(mods["bounce"]),
		"chained": jump > 0,
		"cond": cond,  # 条件分支门禁（由权威侧按玩家实时状态裁决）
		"cond_value": cond_value,
		"loops": loops,  # 循环层重复次数（上限 Skills.MAX_LOOPS）
		"wave_damage": int(mods["wave_damage"]),  # 进化脉冲：每波次额外伤害
	}


static func _haste(unlocked: Array) -> float:
	return float(Skills.modifiers(unlocked)["cooldown_scale"])
