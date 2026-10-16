extends RefCounted
## 动态特效种类测试（子项目 5）：kind 枚举完整性、工厂档位门禁、非法 kind 兜底。

const Harness := preload("res://tools/tests/harness.gd")
const Combat := preload("res://sim/combat.gd")
const Fx := preload("res://scripts/fx.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(Combat.FX_MAX, 20, "共 20 种特效")
	var kinds: Array = [
		Combat.FX_HIT,
		Combat.FX_CHAIN,
		Combat.FX_BURST,
		Combat.FX_PULSE,
		Combat.FX_NUKE,
		Combat.FX_LASER,
		Combat.FX_FROST,
		Combat.FX_BURN,
		Combat.FX_SHIELD,
		Combat.FX_DRAIN,
		Combat.FX_COIN,
		Combat.FX_LEVELUP,
		Combat.FX_REACTION,
		Combat.FX_SPIKE,
		Combat.FX_CHIP,
		Combat.FX_BUG,
		Combat.FX_NULL,
		Combat.FX_SPIN,
		Combat.FX_GIGA,
		Combat.FX_FAULT,
	]
	var uniq := {}
	for k in kinds:
		t.check(int(k) >= 0 and int(k) < Combat.FX_MAX, "kind 落在 0..19 内")
		uniq[k] = true
	t.eq(uniq.size(), 20, "20 个 kind 互不相同")

	# 时长表覆盖全部 kind
	for k in kinds:
		t.check(Fx.duration_of(int(k)) > 0.0, "kind %d 有正时长" % int(k))

	# 档位门禁
	Fx.set_level(Fx.LEVEL_STRONG)
	t.check(Fx.enabled(), "强档默认开启")
	t.eq(Fx.cap(), 24, "强档上限 24")
	var strong := Fx.make(Combat.FX_HIT, Vector2(10, 20), Vector2.RIGHT, 0.0)
	t.check(strong != null, "强档可生成特效节点")
	if strong != null:
		t.eq(strong.kind, Combat.FX_HIT, "生成节点 kind 正确")
		t.check(strong.position == Vector2(10, 20), "生成节点位置正确")
		strong.free()

	Fx.set_level(Fx.LEVEL_MID)
	t.eq(Fx.cap(), 6, "中档上限 6")
	Fx.set_level(Fx.LEVEL_OFF)
	t.check(not Fx.enabled(), "关闭档不再生成")
	t.eq(Fx.cap(), 0, "关闭档上限 0")
	t.check(Fx.make(Combat.FX_HIT, Vector2.ZERO) == null, "关闭档 make 返回 null")

	# 非法 kind 兜底
	Fx.set_level(Fx.LEVEL_STRONG)
	t.check(Fx.make(Combat.FX_MAX, Vector2.ZERO) == null, "越界 kind 返回 null")
	t.check(Fx.make(-1, Vector2.ZERO) == null, "负 kind 返回 null")

	Fx.set_level(Fx.LEVEL_STRONG)  # 复位，避免影响后续套件
	return t.report("FxFinds")
