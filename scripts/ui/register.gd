extends Control
## 注册页：本地派生 verifier，密码不过网线（注册只上传 salt + verifier）。

const Palette := preload("res://scripts/ui/theme/palette.gd")

@onready var _user: LineEdit = $Center/Card/Box/UserName
@onready var _password: LineEdit = $Center/Card/Box/Password
@onready var _confirm: LineEdit = $Center/Card/Box/ConfirmPassword
@onready var _register: Button = $Center/Card/Box/RegisterButton
@onready var _status: Label = $Center/Card/Box/Status
@onready var _error: Label = $Center/Card/Box/Error


func _ready() -> void:
	$BackButton.pressed.connect(_goto_login)
	$Center/Card/Box/BackToLogin.pressed.connect(_goto_login)
	_register.pressed.connect(_on_register_pressed)
	Account.lobby_connecting.connect(_on_lobby_connecting)
	Account.lobby_connected.connect(_on_lobby_connected)
	Account.lobby_failed.connect(_on_lobby_failed)
	Account.register_ok.connect(_on_register_ok)
	Account.register_failed.connect(_on_register_failed)
	_error.add_theme_color_override("font_color", Palette.DANGER)
	_error.text = ""
	if Account.lobby_open:
		_on_lobby_connected()
	else:
		_status.text = "正在连接联机大厅…"
		_register.disabled = true
		Account.connect_lobby()


func _on_lobby_connecting() -> void:
	_status.text = "正在连接联机大厅…"
	_error.text = ""
	_register.disabled = true


func _on_lobby_connected() -> void:
	_status.text = "已连接联机大厅"
	_error.text = ""
	_register.disabled = false


func _on_lobby_failed(reason: String) -> void:
	_status.text = ""
	_error.text = reason
	_register.disabled = true


func _on_register_pressed() -> void:
	_error.text = ""
	var u := _user.text.strip_edges()
	var p := _password.text
	if p != _confirm.text:
		_error.text = "两次输入的密码不一致"
		return
	_register.disabled = true
	_status.text = "正在注册…"
	Account.register(u, p)


func _on_register_ok(_uname: String) -> void:
	_status.text = "注册成功，请返回登录"
	_password.text = ""
	_confirm.text = ""
	_register.disabled = false


func _on_register_failed(reason: String) -> void:
	_status.text = ""
	_error.text = reason
	_register.disabled = false


func _goto_login() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/login.tscn")
