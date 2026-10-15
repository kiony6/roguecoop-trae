extends RefCounted
## 武器纯逻辑测试（M4）：武器表、按修饰派生伤害/冷却/弹丸数。

const Harness := preload("res://tools/tests/harness.gd")
const Weapons := preload("res://sim/weapons.gd")
const Progression := preload("res://sim/progression.gd")


func run() -> int:
	var t := Harness.new()
	var m := Progression.default_modifiers()

	t.eq(Weapons.default_id(), Weapons.KIND_PISTOL, "默认武器为手枪")
	t.eq(Weapons.count(), 3, "共 3 种武器")
	t.check(Weapons.MAX_PROJECTILES > 0, "弹丸总数有上限")

	t.eq(Weapons.damage(Weapons.KIND_PISTOL, m), 12, "手枪基础伤害 12")
	var cd1 := Weapons.cooldown(Weapons.KIND_PISTOL, m)
	t.check(absf(cd1 - 0.22) < 0.0001, "手枪冷却 0.22")
	t.eq(Weapons.projectile_count(Weapons.KIND_SHOTGUN, m), 5, "霰弹枪基础 5 弹丸")
	t.eq(Weapons.projectile_count(Weapons.KIND_PISTOL, m), 1, "手枪基础 1 弹丸")

	var m2 := Progression.apply_card(m, Progression.card_by_id(0))
	t.eq(Weapons.damage(Weapons.KIND_PISTOL, m2), 16, "伤害修饰叠加到武器伤害")
	var m3 := Progression.apply_card(m, Progression.card_by_id(4))
	t.eq(Weapons.projectile_count(Weapons.KIND_PISTOL, m3), 2, "散射修饰叠加到弹丸数")
	var m4 := Progression.apply_card(m, Progression.card_by_id(1))
	var cd2 := Weapons.cooldown(Weapons.KIND_RIFLE, m4)
	t.check(absf(cd2 - 0.11 * 0.85) < 0.0001, "冷却修饰叠加到武器冷却")

	t.eq(Weapons.name_of(Weapons.KIND_RIFLE), "步枪", "武器名查询")
	t.check(absf(Weapons.speed(Weapons.KIND_RIFLE) - 760.0) < 0.0001, "步枪弹速 760")
	t.check(absf(Weapons.radius(Weapons.KIND_SHOTGUN) - 7.0) < 0.0001, "霰弹枪弹丸半径 7")
	t.check(Weapons.spread(Weapons.KIND_SHOTGUN) > 0.0, "霰弹枪有散布")
	t.check(absf(Weapons.spread(Weapons.KIND_PISTOL)) < 0.0001, "手枪无散布")

	return t.report("Weapons")
