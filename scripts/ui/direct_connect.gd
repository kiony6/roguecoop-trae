extends Control
## 局域网直连（P2 通道，免登录、不入榜）：旧 scenes/main.tscn 的表单原样迁移。
## 支持 --ip= / --port= / --transport= 命令行预填；--auto=join 免点击直接加入（M5/M5.1 验收协议）。

const Protocol := preload("res://net/protocol.gd")

var _auto_join := false

@onready var _ip: LineEdit = $Panel/IpField
@onready var _port: LineEdit = $Panel/PortField
@onready var _transport: OptionButton = $Panel/TransportOption
@onready var _status: Label = $Panel/Status


func _ready() -> void:
	# 启动期「直达直连」意图若已由本页就地满足，则在此消费掉，
	# 避免此后点「← 返回主菜单」又被主菜单弹回本页。
	@warning_ignore("return_value_discarded")
	Boot.take_auto_join_pending()
	$BackButton.pressed.connect(_on_back_pressed)
	$Panel/HostButton.pressed.connect(_on_host_pressed)
	$Panel/JoinButton.pressed.connect(_on_join_pressed)
	Net.connected_ok.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_connection_failed)
	_transport.clear()
	_transport.add_item("UDP（直连 / 局域网）")
	_transport.add_item("TCP（WebSocket / 穿透服务器）")
	_transport.selected = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ip="):
			_ip.text = a.substr(5)
		elif a.begins_with("--port="):
			_port.text = a.substr(7)
		elif a.begins_with("--transport="):
			_transport.selected = 1 if a.substr(12) == "ws" else 0
		elif a.begins_with("--auto="):
			_auto_join = a.substr(7) == "join"
	if _auto_join:
		print("[DirectConnect] 命令行透传生效，auto-join 免点击加入")
		_on_join_pressed.call_deferred()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_host_pressed() -> void:
	Account.disconnect_lobby()
	Net.set_role(Protocol.ROLE_PLAYER)
	Net.set_websocket(_transport.selected == 1)
	var err := Net.host_start(Protocol.DEFAULT_PORT)
	if err != OK:
		_status.text = "建立主机失败：错误码 %d" % err
		return
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_join_pressed() -> void:
	var ip := _ip.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port := _port.text.strip_edges().to_int()
	if port <= 0 or port > 65535:
		port = Protocol.DEFAULT_PORT
	Account.disconnect_lobby()
	Net.set_role(Protocol.ROLE_PLAYER)
	Net.set_websocket(_transport.selected == 1)
	var err := Net.client_connect(ip, port)
	if err != OK:
		_status.text = "发起连接失败：错误码 %d" % err
		return
	_status.text = "正在连接 %s:%d（%s）…" % [ip, port, "TCP" if Net.transport_ws else "UDP"]


func _on_connected(_local_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_connection_failed() -> void:
	_status.text = "连接失败（主机未开或网络不通）"
