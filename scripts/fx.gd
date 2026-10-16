extends RefCounted
## 动态特效工厂（子项目 5）：把「特效事件」变成可见的临场节点。
## 纯 Node2D 自绘、零资源，沿用工程既有表现层风格；设置档位可整体关闭或降档。

const FxNode := preload("res://scripts/fx_node.gd")
const Combat := preload("res://sim/combat.gd")

const LEVEL_OFF := 0
const LEVEL_MID := 1
const LEVEL_STRONG := 2

## 各档位单帧允许生成的特效数上限（防刷屏、防卡顿；对齐「掉落无上限累积」的历史教训）。
const CAP := {LEVEL_OFF: 0, LEVEL_MID: 6, LEVEL_STRONG: 24}

static var level := LEVEL_STRONG  # 由设置项调整；默认全开


static func set_level(v: int) -> void:
	level = clampi(v, LEVEL_OFF, LEVEL_STRONG)


static func enabled() -> bool:
	return level != LEVEL_OFF


static func cap() -> int:
	return int(CAP.get(level, LEVEL_OFF))


static func duration_of(kind: int) -> float:
	match kind:
		Combat.FX_NUKE:
			return 0.55
		Combat.FX_REACTION:
			return 0.4
		Combat.FX_PULSE:
			return 0.5
		Combat.FX_LEVELUP:
			return 0.8
		Combat.FX_BURST:
			return 0.35
		Combat.FX_SHIELD:
			return 0.3
		Combat.FX_COIN:
			return 0.45
		Combat.FX_DRAIN:
			return 0.3
		Combat.FX_BURN:
			return 0.4
		Combat.FX_FROST:
			return 0.4
		Combat.FX_LASER:
			return 0.22
		Combat.FX_SPIKE:
			return 0.25
		Combat.FX_CHIP:
			return 0.38
		Combat.FX_BUG:
			return 0.45
		Combat.FX_NULL:
			return 0.28
		Combat.FX_SPIN:
			return 0.5
		Combat.FX_GIGA:
			return 0.6
		Combat.FX_FAULT:
			return 0.5
	return 0.28


static func make(
	kind: int, pos: Vector2, dir: Vector2 = Vector2.ZERO, radius: float = 0.0
) -> Node2D:
	## 生成一个特效节点；关闭档位或非法 kind 返回 null（调用方需判空）。
	if not enabled():
		return null
	if kind < 0 or kind >= Combat.FX_MAX:
		return null
	var n := FxNode.new()
	n.name = "Fx%d" % kind
	n.setup(kind, pos, dir, radius, duration_of(kind))
	return n
