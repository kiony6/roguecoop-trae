extends RefCounted
## 远端玩家插值器。按到达时间缓存采样点，回放 (now - delay_ms) 时刻的位置，
## 从而把网络抖动从视觉上抹平。

const MAX_SAMPLES := 32
var delay_ms := 100.0  # 回放延迟（毫秒）：默认 100，广域网下由表现层按 Net.interp_delay_ms() 抬升

var _times: Array[float] = []
var _points: Array[Vector2] = []


func push(pos: Vector2, now_ms: float) -> void:
	_times.append(now_ms)
	_points.append(pos)
	while _times.size() > MAX_SAMPLES:
		_times.remove_at(0)
		_points.remove_at(0)


func sample_count() -> int:
	return _times.size()


func sample(now_ms: float) -> Vector2:
	var n := _times.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return _points[0]

	var target := now_ms - delay_ms
	if target <= _times[0]:
		return _points[0]
	if target >= _times[n - 1]:
		return _points[n - 1]

	var result := _points[n - 1]
	for i in range(n - 1):
		if target >= _times[i] and target <= _times[i + 1]:
			var span := _times[i + 1] - _times[i]
			if span <= 0.0:
				result = _points[i]
			else:
				result = _points[i].lerp(_points[i + 1], (target - _times[i]) / span)
			break
	return result
