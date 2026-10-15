extends RefCounted
## 传输层选择（UDP/ENet 与 TCP/WebSocket）的纯逻辑测试。

const Harness := preload("res://tools/tests/harness.gd")


func run() -> int:
	var t := Harness.new()

	# (1) WebSocket URL 构造：create_client 需要带 scheme 的完整地址
	t.eq(
		Net.ws_url("play.simpfun.cn", 30470), "ws://play.simpfun.cn:30470", "ws_url 拼出带 scheme 的地址"
	)
	t.eq(Net.ws_url("127.0.0.1", 25600), "ws://127.0.0.1:25600", "ws_url 支持回环地址")
	t.eq(Net.ws_url("0.0.0.0", 65535), "ws://0.0.0.0:65535", "ws_url 支持端口上界 65535")

	# (2) 默认传输必须是 UDP：保证 M5 既有行为与三项冒烟零回归
	t.eq(Net.transport_ws, false, "默认传输为 UDP/ENet")

	# (3) 开关可切换且可复位（用例内复位，避免污染其它套件）
	Net.set_websocket(true)
	t.eq(Net.transport_ws, true, "set_websocket(true) 生效")
	Net.set_websocket(false)
	t.eq(Net.transport_ws, false, "set_websocket(false) 复位")

	return t.report("NetTransport")
