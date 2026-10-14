extends RefCounted
## 兴趣范围（AOI）裁剪：只把玩家周围 radius 内的实体放进发给该玩家的快照。
## M2 实体数量在两位数级别，直接线性扫描即可（YAGNI：暂不做网格广相）。

const AOI_RADIUS := 720.0


static func cull(center: Vector2, radius: float, entities: Array) -> Array:
	var out: Array = []
	for e in entities:
		if center.distance_to(e["pos"]) <= radius:
			out.append(e)
	return out
