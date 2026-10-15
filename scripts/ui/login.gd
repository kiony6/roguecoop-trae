extends Control
## 登录页：连大厅 → 领挑战（salt + nonce）→ 本地派生 verifier → 提交 proof。

const Palette := preload("res://scripts/ui/theme/palette.gd")

@onready var _user: LineEdit = $Center/Card/Box/UserName
@onready var _password: LineEdit = $Center/Card/Box/Password
@onready var _login: Button = $Center/Card/Box/LoginButton
@onready var _status: Label = $Center/Card/Box/Status
@onready var _error: Label = $Center/Card/Box/Error
@onready var _retry: Button = $Center/Card/Box/RetryButton


func _ready() -> void:
	$BackButton.pressed.connect(_on_back)
	$Center/Card/Box/RegisterButton.pressed.connect(_goto_register)
	_login.pressed.connect(_on_login_pressed)
	_retry.pressed.connect(_on_retry_pressed)
	Account.lobby_connecting.connect(_on_lobby_connecting)
	Account.lobby_connected.connect(_on_lobby_connected)
	Account.lobby_failed.connect(_on_lobby_failed)
	Account.login_ok.connect(_on_login_ok)
	Account.login_failed.connect(_on_login_failed)
	Account.version_mismatch_detected.connect(_on_version_mismatch)
	_error.add_theme_color_override("font_color", Palette.DANGER)
	_error.text = ""
	_retry.visible = false
	if Account.lobby_open:
		_on_lobby_connected()
	else:
		_status.text = "正在连接联机大厅…"
		_set_enabled(false)
		Account.connect_lobby()


func _set_enabled(on: bool) -> void:
	_login.disabled = not on
	_user.editable = on
	_password.editable = on


func _on_lobby_connecting() -> void:
	_status.text = "正在连接联机大厅…"
	_error.text = ""
	_retry.visible = false
	_set_enabled(false)


func _on_lobby_connected() -> void:
	_status.text = "已连接联机大厅"
	_error.text = ""
	_retry.visible = false
	_set_enabled(true)


func _on_lobby_failed(reason: String) -> void:
	_status.text = ""
	_error.text = reason
	_retry.visible = true
	_set_enabled(false)


func _on_retry_pressed() -> void:
	Account.connect_lobby()


func _on_login_pressed() -> void:
	_error.text = ""
	_status.text = "正在登录…"
	_set_enabled(false)
	Account.login(_user.text.strip_edges(), _password.text)


func _on_login_ok(_uname: String) -> void:
	_password.text = ""
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_login_failed(reason: String) -> void:
	_status.text = ""
	_error.text = reason
	_set_enabled(true)


func _on_version_mismatch() -> void:
	_status.text = ""
	_error.text = "客户端与服务端版本不一致，请更新后再试"
	_retry.visible = true
	_set_enabled(false)


func _goto_register() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/register.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
