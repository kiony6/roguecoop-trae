extends RefCounted
## 插值器测试：空缓冲、单采样、越界回退、线性中点。

const Harness := preload("res://tools/tests/harness.gd")
const Interp := preload("res://net/interp.gd")


func run() -> int:
	var t := Harness.new()

	var it := Interp.new()
	t.eq(it.sample(1000.0), Vector2.ZERO, "空缓冲返回零向量")

	it.push(Vector2(0, 0), 0.0)
	t.eq(it.sample(500.0), Vector2.ZERO, "单采样返回该采样点")

	it.push(Vector2(100, 0), 200.0)
	# DELAY_MS=100 → sample(200) 目标时刻 = 100，落在 0..200 中点
	var mid := it.sample(200.0)
	t.check(absf(mid.x - 50.0) < 0.001, "中点线性插值 x = 50")

	# sample(100) 目标时刻 = 0 → 早于/等于首个采样，返回首个
	var early := it.sample(100.0)
	t.check((early - Vector2(0, 0)).length() < 0.001, "目标早于首个采样 → 返回首个")

	# sample(1000) 目标时刻 = 900 → 晚于末个采样，返回末个
	var late := it.sample(1000.0)
	t.check((late - Vector2(100, 0)).length() < 0.001, "目标晚于末个采样 → 返回末个")

	# 采样数上限：压入 64 个后不超过 MAX_SAMPLES
	for i in range(64):
		it.push(Vector2(float(i), 0.0), float(i))
	t.eq(it.sample_count(), Interp.MAX_SAMPLES, "采样数被裁剪到 MAX_SAMPLES")

	# delay_ms 由常量改为实例字段：表现层可在高延迟下抬升回放延迟
	var it2 := Interp.new()
	it2.delay_ms = 200.0
	it2.push(Vector2(0, 0), 0.0)
	it2.push(Vector2(100, 0), 200.0)
	var mid2 := it2.sample(200.0)
	t.check(absf(mid2.x) < 0.001, "delay_ms=200 时目标时刻回退到首个采样")
	t.check(absf(it2.delay_ms - 200.0) < 0.001, "delay_ms 可被外部覆盖")

	return t.report("Interp")
