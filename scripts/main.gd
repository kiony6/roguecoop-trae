extends Control
## 主菜单：建立主机 / 加入主机（支持 --ip= / --port= / --transport= 命令行预填）。

const Protocol := preload("res://net/protocol.gd")

@onready var _ip: LineEdit = $Panel/IpField
@onready var _port: LineEdit = $Panel/PortField
@onready var _transport: OptionButton = $Panel/TransportOption
@onready var _status: Label = $Panel/Status


func _ready() -> void:
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


func _on_host_pressed() -> void:
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
