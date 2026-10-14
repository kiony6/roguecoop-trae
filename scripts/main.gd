extends Control
## 主菜单：建立主机 / 加入主机。

const Protocol := preload("res://net/protocol.gd")

@onready var _ip: LineEdit = $Panel/IpField
@onready var _status: Label = $Panel/Status


func _ready() -> void:
	$Panel/HostButton.pressed.connect(_on_host_pressed)
	$Panel/JoinButton.pressed.connect(_on_join_pressed)
	Net.connected_ok.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_connection_failed)


func _on_host_pressed() -> void:
	var err := Net.host_start(Protocol.DEFAULT_PORT)
	if err != OK:
		_status.text = "建立主机失败：错误码 %d" % err
		return
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_join_pressed() -> void:
	var ip := _ip.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var err := Net.client_connect(ip, Protocol.DEFAULT_PORT)
	if err != OK:
		_status.text = "发起连接失败：错误码 %d" % err
		return
	_status.text = "正在连接 %s:%d …" % [ip, Protocol.DEFAULT_PORT]


func _on_connected(_local_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_connection_failed() -> void:
	_status.text = "连接失败（主机未开或网络不通）"
