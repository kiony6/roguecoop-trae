extends RefCounted
## 波次难度曲线纯逻辑（M4）。
## 波次 = 按存活时长推进的难度档位（每 WAVE_DURATION 秒 +1）。
## 第 1 档所有倍率均为 1，保证与 M3 行为一致（零回归）。

const Combat := preload("res://sim/combat.gd")

const WAVE_DURATION := 25.0
const SPAWN_INTERVAL_DECAY := 0.9
const SPAWN_INTERVAL_MIN := 0.4
const MAX_ENEMIES_STEP := 2
const MAX_ENEMIES_CAP := 60
const HP_MUL_STEP := 0.15
const SPEED_MUL_STEP := 0.05
const SPEED_MUL_CAP := 1.6


static func wave_index(elapsed: float) -> int:
	return int(floorf(maxf(elapsed, 0.0) / WAVE_DURATION)) + 1


static func spawn_interval(wave: int) -> float:
	var w := maxi(wave, 1) - 1
	var decay := pow(SPAWN_INTERVAL_DECAY, float(w))
	return maxf(SPAWN_INTERVAL_MIN, Combat.SPAWN_INTERVAL * decay)


static func max_enemies(wave: int) -> int:
	return mini(MAX_ENEMIES_CAP, Combat.MAX_ENEMIES + (maxi(wave, 1) - 1) * MAX_ENEMIES_STEP)


static func hp_mul(wave: int) -> float:
	return 1.0 + float(maxi(wave, 1) - 1) * HP_MUL_STEP


static func speed_mul(wave: int) -> float:
	return minf(SPEED_MUL_CAP, 1.0 + float(maxi(wave, 1) - 1) * SPEED_MUL_STEP)


static func enemy_hp(kind: int, wave: int) -> int:
	return roundi(float(Combat.enemy_max_hp(kind)) * hp_mul(wave))


static func enemy_speed(kind: int, wave: int) -> float:
	return Combat.enemy_speed(kind) * speed_mul(wave)
