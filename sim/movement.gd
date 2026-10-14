extends RefCounted
## 权威移动步进。主机是唯一裁决方，客户端预测复用同一份实现以保持一致。

const SPEED := 220.0


static func step(pos: Vector2, move: Vector2, delta: float, speed: float = SPEED) -> Vector2:
	var dir := move
	var len := dir.length()
	if len > 1.0:
		dir = dir / len
	return pos + dir * speed * delta
