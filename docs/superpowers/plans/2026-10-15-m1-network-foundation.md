# M1 联机地基 实现计划

> **给自动化执行者：** 本计划的每一步都用复选框（`- [x]`）跟踪。按任务顺序逐条执行，不要跳步。

**目标：** 在 `D:\games\RogueCoop`（Godot 4.7 + GDScript）中落地 M1 联机地基——房主创建房间、客户端加入、客户端 30Hz 上报输入、主机权威模拟、快照广播、玩家位置同步与远端插值，并用「1 主机 + 1 客户端」双 headless 实例做自动化联机断言。

**架构：** 主机权威（host-authoritative）+ 自研紧凑二进制快照，**不使用** `MultiplayerSynchronizer`。传输用 `ENetMultiplayerPeer`；所有 `@rpc` 方法集中在 autoload `Net` 单一节点上（保证主机/客户端 RPC 路径一致），传输与模拟细节拆到 `net/net_host.gd`（纯逻辑）与 `net/net_client.gd`（纯逻辑）。客户端本地玩家走「预测 + 软校正」，客户端远端玩家走「按到达时间回放的插值」。

**技术栈：** Godot 4.7.2 / GDScript / ENetMultiplayerPeer / gdtoolkit（gdlint + gdformat）/ PowerShell 测试编排。

**已确认的默认参数（用户已拍板）：**
1. 人数上限：M1 实际按 **2 人** 验收，协议常量按 **4 人** 设计（`MAX_PLAYERS = 4`）。
2. 升级方式：共享经验池 + 每人独立选卡（M1 不实现，仅确认不影响本阶段架构）。
3. 首个可玩里程碑：M1 + M2（本计划只覆盖 M1；M2 另立计划）。

**环境事实（务必复用，已实测）：**
- Godot：`D:\Godot\Godot_v4.7.2-stable_win64_console.exe`（console 版，可捕获 stdout；另有非 console 版）。
- 运行场景的正确姿势（已实测通过，exit 0）：
  `& $GODOT --headless --path D:\games\RogueCoop res://<scene>.tscn`
- 工程已 `git init`，**无任何提交**，当前 `master` 分支。
- **禁止执行 `git lfs install`**（会改全局 git 配置）；如确需用，只能 `git lfs install --local`。
- 本机 PowerShell 为 elevated。

---

## 文件结构（本阶段新增/修改）

| 文件 | 职责 |
| --- | --- |
| `net/protocol.gd` | 协议常量 + 二进制编解码（输入帧、快照）。纯静态方法。 |
| `net/net_host.gd` | 主机权威模拟纯逻辑（`RefCounted`，无传输）。 |
| `net/net_client.gd` | 客户端状态纯逻辑（`RefCounted`，无传输）。 |
| `net/interp.gd` | 远端玩家插值器（按到达时间回放）。 |
| `sim/movement.gd` | 权威移动步进，主机与客户端预测共用。 |
| `autoload/boot.gd` | 运行期注册 InputMap（避免手写 project.godot 冗长事件字面量）。 |
| `autoload/net.gd` | 网络门面：**唯一** `@rpc` 入口 + 生命周期 + 信号。 |
| `scripts/main.gd` / `scenes/main.tscn` | 主菜单：建立主机 / 加入主机。 |
| `scripts/world.gd` / `scenes/world.tscn` | 世界场景：按 `world_state` 渲染玩家。 |
| `scripts/player.gd` | 玩家表现节点：本地预测 / 远端插值 / 主机权威直连。 |
| `tools/tests/harness.gd` | 极简断言器。 |
| `tools/tests/run_tests.gd` + `run_tests.tscn` | 单元测试入口（场景方式运行）。 |
| `tools/tests/test_*.gd` | 四个套件：输入帧、快照、移动、插值。 |
| `tools/net_test/net_test_host.gd|.tscn` | 联机冒烟测试主机端。 |
| `tools/net_test/net_test_client.gd|.tscn` | 联机冒烟测试客户端。 |
| `tools/net_test/run_net_test.ps1` | 双实例编排 + 断言。 |
| `project.godot` | 追加 `[autoload]` 段。 |
| `.gitignore` | 追加测试产物忽略。 |

---

## Task 1：单元测试脚手架

**Files:**
- Create: `tools/tests/harness.gd`
- Create: `tools/tests/run_tests.gd`
- Create: `tools/tests/run_tests.tscn`

- [x] **Step 1: 写断言器 `tools/tests/harness.gd`**

```gdscript
extends RefCounted
## 极简断言器：累计通过/失败计数，套件结束返回失败数。

var passed := 0
var failed := 0
var _failures: Array = []


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		_failures.append(label)
		printerr("  FAIL: %s" % label)


func eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s (got=%s want=%s)" % [label, actual, expected])


func report(suite: String) -> int:
	print("[%s] passed=%d failed=%d" % [suite, passed, failed])
	for f in _failures:
		print("    - %s" % f)
	return failed
```

- [x] **Step 2: 写测试入口 `tools/tests/run_tests.gd`**

```gdscript
extends Node
## 单元测试入口。以场景方式运行，避免 --script 与 autoload 的兼容性问题。

const SUITES: Array = [
	preload("res://tools/tests/test_protocol_input.gd"),
	preload("res://tools/tests/test_protocol_snapshot.gd"),
	preload("res://tools/tests/test_movement.gd"),
	preload("res://tools/tests/test_interp.gd"),
]


func _ready() -> void:
	var failed := 0
	for suite_script in SUITES:
		failed += suite_script.new().run()
	if failed == 0:
		print("[UnitTests] ALL PASS")
		get_tree().quit(0)
	else:
		printerr("[UnitTests] FAILED=%d" % failed)
		get_tree().quit(1)
```

- [x] **Step 3: 写测试入口场景 `tools/tests/run_tests.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/tests/run_tests.gd" id="1_run"]

[node name="RunTests" type="Node"]
script = ExtResource("1_run")
```

- [x] **Step 4: 暂缺套件时先跑一次（预期失败）**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: 报错（`preload` 找不到 `test_*.gd`），exit 非 0。这证明入口已生效。

- [x] **Step 5: 提交**

```powershell
git -C D:\games\RogueCoop add tools/tests
git -C D:\games\RogueCoop commit -m "test: 加入极简单元测试脚手架"
```

---

## Task 2：协议常量与输入帧编解码

**Files:**
- Create: `net/protocol.gd`
- Create: `tools/tests/test_protocol_input.gd`

- [x] **Step 1: 写失败测试 `tools/tests/test_protocol_input.gd`**

```gdscript
extends RefCounted
## 输入帧编解码测试：长度固定、往返精度、越界夹紧。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()

	t.eq(
		Protocol.encode_input(Vector2.ZERO, Vector2.RIGHT, 0).size(),
		Protocol.INPUT_BYTES,
		"输入帧长度 = 5"
	)

	var f := Protocol.decode_input(Protocol.encode_input(Vector2(1, 0), Vector2(0, -1), 3))
	t.check(absf(f["move"].x - 1.0) < 0.01, "move.x 往返 ≈ 1.0")
	t.check(absf(f["move"].y) < 0.01, "move.y 往返 ≈ 0.0")
	t.check(absf(f["aim"].y + 1.0) < 0.01, "aim.y 往返 ≈ -1.0")
	t.eq(f["buttons"], 3, "buttons 往返")

	var g := Protocol.decode_input(Protocol.encode_input(Vector2(9.0, -9.0), Vector2.ZERO, 0))
	t.check(g["move"].x > 0.99, "超范围 move.x 夹到 +1")
	t.check(g["move"].y < -0.99, "超范围 move.y 夹到 -1")

	return t.report("ProtocolInput")
```

- [x] **Step 2: 跑测试确认失败**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: FAIL —— `res://net/protocol.gd` 无法解析。

- [x] **Step 3: 实现 `net/protocol.gd`**

```gdscript
extends RefCounted
## 网络协议常量与二进制编解码（M1）。全部静态方法，无实例状态。
## 输入帧：5 字节。快照：5 + N*10 字节。

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 25600
const MAX_PLAYERS := 4        # 协议上限（M1 实际按 2 人验收）
const INPUT_RATE := 30        # 客户端输入上报 Hz
const SNAPSHOT_RATE := 20     # 主机快照广播 Hz
const CH_CONTROL := 0         # 可靠通道
const CH_DATA := 1            # 不可靠有序通道

const INPUT_BYTES := 5
const PLAYER_BYTES := 10


# ---------------- 输入帧 ----------------
# 布局: i8 move_x | i8 move_y | i8 aim_x | i8 aim_y | u8 buttons

static func encode_input(move: Vector2, aim: Vector2, buttons: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(INPUT_BYTES)
	b[0] = _quant8(move.x)
	b[1] = _quant8(move.y)
	b[2] = _quant8(aim.x)
	b[3] = _quant8(aim.y)
	b[4] = buttons & 0xFF
	return b


static func decode_input(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= INPUT_BYTES, "input frame too short")
	return {
		"move": Vector2(_dequant8(b[0]), _dequant8(b[1])),
		"aim": Vector2(_dequant8(b[2]), _dequant8(b[3])),
		"buttons": b[4],
	}


# ---------------- 快照 ----------------
# 布局: u32 tick | u8 count | count * (u16 id | f32 x | f32 y)

static func encode_snapshot(tick: int, players: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(snapshot_size(players.size()))
	b.encode_u32(0, tick)
	b[4] = players.size()
	var o := 5
	for p in players:
		b.encode_u16(o, int(p["id"]))
		b.encode_float(o + 2, float(p["pos"].x))
		b.encode_float(o + 6, float(p["pos"].y))
		o += PLAYER_BYTES
	return b


static func decode_snapshot(b: PackedByteArray) -> Dictionary:
	assert(b.size() >= 5, "snapshot too short")
	var out: Array = []
	var count: int = b[4]
	var o := 5
	for _i in count:
		if o + PLAYER_BYTES > b.size():
			break
		out.append({
			"id": b.decode_u16(o),
			"pos": Vector2(b.decode_float(o + 2), b.decode_float(o + 6)),
		})
		o += PLAYER_BYTES
	return {"tick": b.decode_u32(0), "players": out}


static func snapshot_size(count: int) -> int:
	return 5 + count * PLAYER_BYTES


# ---------------- 量化辅助 ----------------

static func _quant8(v: float) -> int:
	# [-1, 1] -> [-127, 127]，再取低 8 位（PackedByteArray 为无符号）
	return clampi(roundi(clampf(v, -1.0, 1.0) * 127.0), -127, 127) & 0xFF


static func _dequant8(raw: int) -> float:
	var v: int = raw
	if v > 127:
		v -= 256
	return float(v) / 127.0
```

- [x] **Step 4: 跑测试确认通过**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: 含 `[ProtocolInput] passed=8 failed=0`（其余套件此时仍缺，先忽略）。

- [x] **Step 5: 提交**

```powershell
git -C D:\games\RogueCoop add net/protocol.gd tools/tests/test_protocol_input.gd
git -C D:\games\RogueCoop commit -m "feat(net): 协议常量与输入帧二进制编解码"
```

---

## Task 3：快照编解码

**Files:**
- Modify: `net/protocol.gd`（Task 2 已写入快照部分，本任务只补测试）
- Create: `tools/tests/test_protocol_snapshot.gd`

- [x] **Step 1: 写失败测试 `tools/tests/test_protocol_snapshot.gd`**

```gdscript
extends RefCounted
## 快照编解码测试：长度公式、tick/id 往返、浮点位置往返。

const Harness := preload("res://tools/tests/harness.gd")
const Protocol := preload("res://net/protocol.gd")


func run() -> int:
	var t := Harness.new()

	var players: Array = [
		{"id": 1, "pos": Vector2(10.5, -20.25)},
		{"id": 3, "pos": Vector2(0.0, 0.0)},
	]

	var bytes := Protocol.encode_snapshot(42, players)
	t.eq(bytes.size(), Protocol.snapshot_size(2), "快照长度 = 5 + 2*10")
	t.eq(bytes.size(), 25, "快照长度硬校验 = 25")

	var d := Protocol.decode_snapshot(bytes)
	t.eq(d["tick"], 42, "tick 往返")
	t.eq(d["players"].size(), 2, "玩家数往返")
	t.eq(d["players"][0]["id"], 1, "id[0] 往返")
	t.check((d["players"][0]["pos"] - Vector2(10.5, -20.25)).length() < 0.001, "pos[0] 往返")
	t.eq(d["players"][1]["id"], 3, "id[1] 往返")

	var empty := Protocol.decode_snapshot(Protocol.encode_snapshot(7, []))
	t.eq(empty["players"].size(), 0, "空快照玩家数 = 0")
	t.eq(empty["tick"], 7, "空快照 tick 往返")

	return t.report("ProtocolSnapshot")
```

- [x] **Step 2: 跑测试**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: `[ProtocolSnapshot] passed=9 failed=0`。

- [x] **Step 3: 提交**

```powershell
git -C D:\games\RogueCoop add tools/tests/test_protocol_snapshot.gd
git -C D:\games\RogueCoop commit -m "test(net): 快照编解码用例"
```

---

## Task 4：权威移动步进

**Files:**
- Create: `sim/movement.gd`
- Create: `tools/tests/test_movement.gd`

- [x] **Step 1: 写失败测试 `tools/tests/test_movement.gd`**

```gdscript
extends RefCounted
## 移动步进测试：直线位移、斜向归一化、零输入静止。

const Harness := preload("res://tools/tests/harness.gd")
const Movement := preload("res://sim/movement.gd")


func run() -> int:
	var t := Harness.new()

	var p := Movement.step(Vector2.ZERO, Vector2(1, 0), 0.5)
	t.check(absf(p.x - Movement.SPEED * 0.5) < 0.001, "右移一步 x = SPEED*dt")
	t.check(absf(p.y) < 0.001, "右移一步 y 不变")

	var q := Movement.step(Vector2.ZERO, Vector2(1, 1), 1.0)
	t.check(absf(q.length() - Movement.SPEED) < 0.001, "斜向输入被归一化")

	var z := Movement.step(Vector2(5, 5), Vector2.ZERO, 1.0)
	t.eq(z, Vector2(5, 5), "零输入原地不动")

	var half := Movement.step(Vector2.ZERO, Vector2(0.5, 0), 1.0)
	t.check(absf(half.x - Movement.SPEED * 0.5) < 0.001, "半速输入不被放大")

	return t.report("Movement")
```

- [x] **Step 2: 跑测试确认失败**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: FAIL —— `res://sim/movement.gd` 无法解析。

- [x] **Step 3: 实现 `sim/movement.gd`**

```gdscript
extends RefCounted
## 权威移动步进。主机是唯一裁决方，客户端预测复用同一份实现以保持一致。

const SPEED := 220.0


static func step(pos: Vector2, move: Vector2, delta: float) -> Vector2:
	var dir := move
	var len := dir.length()
	if len > 1.0:
		dir = dir / len
	return pos + dir * SPEED * delta
```

- [x] **Step 4: 跑测试确认通过**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: `[Movement] passed=6 failed=0`。

- [x] **Step 5: 提交**

```powershell
git -C D:\games\RogueCoop add sim/movement.gd tools/tests/test_movement.gd
git -C D:\games\RogueCoop commit -m "feat(sim): 权威移动步进与用例"
```

---

## Task 5：远端插值器

**Files:**
- Create: `net/interp.gd`
- Create: `tools/tests/test_interp.gd`

- [x] **Step 1: 写失败测试 `tools/tests/test_interp.gd`**

```gdscript
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

	return t.report("Interp")
```

- [x] **Step 2: 跑测试确认失败**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: FAIL —— `res://net/interp.gd` 无法解析。

- [x] **Step 3: 实现 `net/interp.gd`**

```gdscript
extends RefCounted
## 远端玩家插值器。按到达时间缓存采样点，回放 (now - DELAY_MS) 时刻的位置，
## 从而把网络抖动从视觉上抹平。

const DELAY_MS := 100.0
const MAX_SAMPLES := 32

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

	var target := now_ms - DELAY_MS
	if target <= _times[0]:
		return _points[0]
	if target >= _times[n - 1]:
		return _points[n - 1]

	for i in range(n - 1):
		if target >= _times[i] and target <= _times[i + 1]:
			var span := _times[i + 1] - _times[i]
			if span <= 0.0:
				return _points[i]
			return _points[i].lerp(_points[i + 1], (target - _times[i]) / span)
	return _points[n - 1]
```

- [x] **Step 4: 跑测试确认通过**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
```
Expected: `[Interp] passed=6 failed=0`，且末尾 `[UnitTests] ALL PASS`，exit 0。

- [x] **Step 5: 提交**

```powershell
git -C D:\games\RogueCoop add net/interp.gd tools/tests/test_interp.gd
git -C D:\games\RogueCoop commit -m "feat(net): 远端玩家插值器与用例"
```

---

## Task 6：主机/客户端纯逻辑类

**Files:**
- Create: `net/net_host.gd`
- Create: `net/net_client.gd`

- [x] **Step 1: 实现 `net/net_host.gd`**

```gdscript
extends RefCounted
## 主机权威模拟（纯逻辑，不含传输）。由 autoload Net 驱动。

const Movement := preload("res://sim/movement.gd")

var tick := 0
var snapshot_count := 0
var local_move := Vector2.ZERO
var local_buttons := 0
var players := {}   # id:int -> {pos:Vector2, move:Vector2, buttons:int}


func reset() -> void:
	tick = 0
	snapshot_count = 0
	local_move = Vector2.ZERO
	local_buttons = 0
	players = {1: _new_player()}


func add_player(id: int) -> void:
	players[id] = _new_player()


func remove_player(id: int) -> void:
	players.erase(id)


func has_player(id: int) -> bool:
	return players.has(id)


func set_remote_input(id: int, move: Vector2, buttons: int) -> void:
	if players.has(id):
		players[id]["move"] = move
		players[id]["buttons"] = buttons


func physics_step(delta: float) -> void:
	tick += 1
	if players.has(1):
		players[1]["move"] = local_move
		players[1]["buttons"] = local_buttons
	for id in players:
		var p: Dictionary = players[id]
		p["pos"] = Movement.step(p["pos"], p["move"], delta)


func player_states() -> Array:
	var out: Array = []
	for id in peer_ids():
		out.append({"id": id, "pos": players[id]["pos"]})
	return out


func peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	var keys := players.keys()
	keys.sort()
	for k in keys:
		ids.append(int(k))
	return ids


func _new_player() -> Dictionary:
	return {"pos": Vector2.ZERO, "move": Vector2.ZERO, "buttons": 0}
```

- [x] **Step 2: 实现 `net/net_client.gd`**

```gdscript
extends RefCounted
## 客户端状态（纯逻辑，不含传输）。由 autoload Net 驱动。

var tick := 0
var last_snapshot_tick := 0
var last_players: Array = []
var pending_move := Vector2.ZERO
var pending_buttons := 0


func reset() -> void:
	tick = 0
	last_snapshot_tick = 0
	last_players = []
	pending_move = Vector2.ZERO
	pending_buttons = 0
```

- [x] **Step 3: 语法自检**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop --check-only --script res://net/net_host.gd
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop --check-only --script res://net/net_client.gd
```
Expected: 两条均无输出错误，exit 0。

- [x] **Step 4: 提交**

```powershell
git -C D:\games\RogueCoop add net/net_host.gd net/net_client.gd
git -C D:\games\RogueCoop commit -m "feat(net): 主机权威模拟与客户端状态纯逻辑"
```

---

## Task 7：Net 门面 + 输入映射 + autoload 装配

**Files:**
- Create: `autoload/net.gd`
- Create: `autoload/boot.gd`
- Modify: `project.godot`

> **关键设计约束：** 所有 `@rpc` 方法只挂在 autoload `Net` 这一棵节点上。Godot 的 RPC 按 **节点路径** 解析，主机与客户端的 `/root/Net` 路径一致，才能互相解析到方法。不要把 `@rpc` 分散到 `net_host.gd` / `net_client.gd`（它们是 `RefCounted`，不是节点）。

- [x] **Step 1: 实现 `autoload/boot.gd`**

```gdscript
extends Node
## 启动引导：运行期注册 InputMap。
## 这样可避免手写 project.godot 里冗长的 InputEventKey 字面量。

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"fire": [KEY_J],
	"dash": [KEY_K],
}


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	if not InputMap.has_action("fire"):
		InputMap.add_action("fire", 0.2)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)
```

- [x] **Step 2: 实现 `autoload/net.gd`**

```gdscript
extends Node
## 网络门面（autoload 名 "Net"）。
## 唯一的 @rpc 入口：所有 RPC 方法都挂在本节点上，保证主机/客户端 RPC 路径一致。
## 传输与模拟细节分别委托给 net/net_host.gd 与 net/net_client.gd。

signal player_joined(player_id: int)
signal player_left(player_id: int)
signal input_received(player_id: int)
signal world_state(tick: int, players: Array)
signal connected_ok(local_id: int)
signal connection_failed()
signal disconnected()

const Protocol := preload("res://net/protocol.gd")
const NetHostLogic := preload("res://net/net_host.gd")
const NetClientLogic := preload("res://net/net_client.gd")

enum Mode { NONE, HOST, CLIENT }

var mode: Mode = Mode.NONE
var local_id := 0

var _host := NetHostLogic.new()
var _client := NetClientLogic.new()
var _send_accum := 0.0
var _snap_accum := 0.0
var _known_peers: Array = []


func _ready() -> void:
	# 保证本地输入在 Player 采样之后再被消费（autoload 默认排在场景节点之前）
	process_physics_priority = 100
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


# ---------------- 主机 ----------------

func host_start(port: int) -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Protocol.MAX_PLAYERS - 1, 2)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_host.reset()
	_known_peers.clear()
	mode = Mode.HOST
	local_id = 1
	_send_accum = 0.0
	_snap_accum = 0.0
	set_physics_process(true)
	player_joined.emit(1)
	return OK


func host_stop() -> void:
	if mode != Mode.HOST:
		return
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_host.reset()
	local_id = 0


# ---------------- 客户端 ----------------

func client_connect(address: String, port: int) -> Error:
	if mode != Mode.NONE:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_client.reset()
	_known_peers.clear()
	mode = Mode.CLIENT
	local_id = 0
	_send_accum = 0.0
	set_physics_process(true)
	return OK


func client_disconnect() -> void:
	if mode != Mode.CLIENT:
		return
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	_client.reset()
	local_id = 0


# ---------------- 对外输入 ----------------

func send_local_input(move: Vector2, buttons: int) -> void:
	var dir := move
	if dir.length() > 1.0:
		dir = dir.normalized()
	if mode == Mode.HOST:
		_host.local_move = dir
		_host.local_buttons = buttons
	elif mode == Mode.CLIENT:
		_client.pending_move = dir
		_client.pending_buttons = buttons


# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	if mode == Mode.HOST:
		_host.physics_step(delta)
		# 本机渲染每物理帧刷新（60Hz），网络快照另行降频
		world_state.emit(_host.tick, _host.player_states())
		_snap_accum += delta
		if _snap_accum >= 1.0 / float(Protocol.SNAPSHOT_RATE):
			_snap_accum = 0.0
			_send_snapshot()
	elif mode == Mode.CLIENT:
		_send_accum += delta
		if _send_accum >= 1.0 / float(Protocol.INPUT_RATE):
			_send_accum = 0.0
			_client.tick += 1
			_rpc_input.rpc_id(1, _client.tick, Protocol.encode_input(
				_client.pending_move, Vector2.RIGHT, _client.pending_buttons))


func _send_snapshot() -> void:
	var payload := Protocol.encode_snapshot(_host.tick, _host.player_states())
	_host.snapshot_count += 1
	_rpc_snapshot.rpc(_host.tick, payload)


# ---------------- 连接事件 ----------------

func _on_peer_connected(id: int) -> void:
	if mode != Mode.HOST:
		return
	_host.add_player(id)
	player_joined.emit(id)
	_broadcast_peer_list()


func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.HOST:
		return
	_host.remove_player(id)
	player_left.emit(id)
	_broadcast_peer_list()


func _on_connected_to_server() -> void:
	local_id = multiplayer.get_unique_id()
	connected_ok.emit(local_id)


func _on_connection_failed() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	mode = Mode.NONE
	set_physics_process(false)
	multiplayer.multiplayer_peer = null
	disconnected.emit()


func _broadcast_peer_list() -> void:
	_rpc_peer_list.rpc(_host.peer_ids())


# ---------------- RPC ----------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(_tick_in: int, payload: PackedByteArray) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return
	if not _host.has_player(sender):
		return
	var f := Protocol.decode_input(payload)
	_host.set_remote_input(sender, f["move"], f["buttons"])
	input_received.emit(sender)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(tick_in: int, payload: PackedByteArray) -> void:
	if mode != Mode.CLIENT:
		return
	var snap := Protocol.decode_snapshot(payload)
	_client.last_snapshot_tick = snap["tick"]
	_client.last_players = snap["players"]
	world_state.emit(snap["tick"], snap["players"])


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_peer_list(ids: PackedInt32Array) -> void:
	if mode != Mode.CLIENT:
		return
	var my_id := multiplayer.get_unique_id()
	for id in ids:
		if id == my_id:
			continue
		if not _known_peers.has(id):
			_known_peers.append(id)
			player_joined.emit(id)
	for id in _known_peers.duplicate():
		if not ids.has(id):
			_known_peers.erase(id)
			player_left.emit(id)
```

- [x] **Step 3: 语法自检**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop --check-only --script res://autoload/net.gd
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop --check-only --script res://autoload/boot.gd
```
Expected: 均无错误，exit 0。

- [x] **Step 4: 在 `project.godot` 追加 autoload 段**

用编辑器打开 `D:\games\RogueCoop\project.godot`，在 `[application]` 段之后插入：

```
[autoload]

Boot="*res://autoload/boot.gd"
Net="*res://autoload/net.gd"
```

> 前缀 `*` 表示启用（单例）。`Boot` 必须排在 `Net` 之前。

- [x] **Step 5: 验证 autoload 生效**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://scenes/main.tscn --quit-after 10
```
Expected: 打印 `[RogueCoop] boot ok ...`，exit 0，且无 autoload 报错。

- [x] **Step 6: 提交**

```powershell
git -C D:\games\RogueCoop add autoload/net.gd autoload/boot.gd project.godot
git -C D:\games\RogueCoop commit -m "feat(net): Net 门面（RPC/信号/生命周期）+ 运行期输入映射 + autoload 装配"
```

---

## Task 8：表现层（玩家节点 / 世界场景 / 主菜单）

**Files:**
- Create: `scripts/player.gd`
- Create: `scripts/world.gd`
- Create: `scenes/world.tscn`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`

- [x] **Step 1: 实现 `scripts/player.gd`**

```gdscript
extends Node2D
## 玩家表现节点。状态全部来自 Net 的 world_state 推送：
## - 主机端：一切权威直连（自己 + 远端都直接读权威位置）
## - 客户端：本地玩家「预测 + 软校正」，远端玩家「按到达时间插值」

const Interp := preload("res://net/interp.gd")
const Movement := preload("res://sim/movement.gd")

const CORRECT_RATE := 10.0   # 软校正速率
const SNAP_DIST := 140.0     # 误差超过该距离直接硬吸附
const RADIUS := 14.0

var player_id := 0
var is_local := false
var color := Color.WHITE

var _interp := Interp.new()
var _auth := Vector2.ZERO
var _has_auth := false
var _predicted := Vector2.ZERO


func setup(id: int, local: bool, c: Color) -> void:
	player_id = id
	is_local = local
	color = c
	_predicted = position
	z_index = 1 if local else 0
	queue_redraw()


func push_authoritative(pos: Vector2) -> void:
	if not _has_auth:
		_has_auth = true
		_auth = pos
		_predicted = pos
		position = pos
	_auth = pos
	_interp.push(pos, float(Time.get_ticks_msec()))


func _physics_process(delta: float) -> void:
	if not _has_auth:
		return
	if is_local and Net.is_client():
		_local_tick(delta)
	elif Net.is_client():
		position = _interp.sample(float(Time.get_ticks_msec()))
	else:
		position = _auth


func _local_tick(delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_predicted = Movement.step(_predicted, move, delta)
	Net.send_local_input(move, _read_buttons())

	var err := _auth - _predicted
	if err.length() > SNAP_DIST:
		_predicted = _auth
	else:
		_predicted += err * (1.0 - exp(-CORRECT_RATE * delta))
	position = _predicted


func _read_buttons() -> int:
	var b := 0
	if Input.is_action_pressed("fire"):
		b |= 1
	if Input.is_action_pressed("dash"):
		b |= 2
	return b


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, color.darkened(0.35), 2.0)
	if is_local:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 24, color.lightened(0.4), 1.0)
```

- [x] **Step 2: 实现 `scripts/world.gd`**

```gdscript
extends Node2D
## 世界场景：只负责按 Net 广播的 world_state 渲染玩家，不参与任何权威裁决。

const PlayerScript := preload("res://scripts/player.gd")

const COLORS: Array[Color] = [
	Color("4aa3ff"), Color("ff7a59"), Color("ffd93d"), Color("7be07b"),
]

@onready var _info: Label = $Hud/Info

var _nodes := {}


func _ready() -> void:
	Net.world_state.connect(_on_world_state)
	Net.player_left.connect(_on_player_left)
	_update_info()


func _process(_delta: float) -> void:
	_update_info()


func _on_world_state(_tick: int, players: Array) -> void:
	for p in players:
		var id: int = p["id"]
		var node: Node2D = _nodes.get(id)
		if node == null:
			node = _spawn(id)
		node.push_authoritative(p["pos"])


func _on_player_left(id: int) -> void:
	var node: Node2D = _nodes.get(id)
	if node != null:
		node.queue_free()
		_nodes.erase(id)


func _spawn(id: int) -> Node2D:
	var node := PlayerScript.new()
	node.name = "Player%d" % id
	node.setup(id, id == Net.local_id, COLORS[(id - 1) % COLORS.size()])
	add_child(node)
	_nodes[id] = node
	return node


func _update_info() -> void:
	var role := "未连接"
	if Net.is_host():
		role = "主机 id=%d" % Net.local_id
	elif Net.is_client():
		role = "客户端 id=%d" % Net.local_id
	_info.text = "%s | 在线 %d 人 | WASD 移动" % [role, _nodes.size()]
```

- [x] **Step 3: 写 `scenes/world.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world.gd" id="1_world"]

[node name="World" type="Node2D"]
script = ExtResource("1_world")

[node name="Camera2D" type="Camera2D" parent="."]

[node name="Hud" type="CanvasLayer" parent="."]

[node name="Info" type="Label" parent="Hud"]
offset_left = 16.0
offset_top = 12.0
offset_right = 480.0
offset_bottom = 40.0
text = ""
```

- [x] **Step 4: 覆写 `scripts/main.gd`**

```gdscript
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
```

- [x] **Step 5: 覆写 `scenes/main.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[node name="Main" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_main")

[node name="Panel" type="VBoxContainer" parent="."]
offset_left = 480.0
offset_top = 280.0
offset_right = 800.0
offset_bottom = 460.0

[node name="Title" type="Label" parent="Panel"]
text = "RogueCoop · 肉鸽多人联机"

[node name="IpField" type="LineEdit" parent="Panel"]
text = "127.0.0.1"
placeholder_text = "主机 IP"

[node name="HostButton" type="Button" parent="Panel"]
text = "建立主机"

[node name="JoinButton" type="Button" parent="Panel"]
text = "加入主机"

[node name="Status" type="Label" parent="Panel"]
text = ""
```

- [x] **Step 6: 冒烟验证主菜单可启动**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://scenes/main.tscn --quit-after 20
```
Expected: 无脚本报错，exit 0。

- [x] **Step 7: 提交**

```powershell
git -C D:\games\RogueCoop add scripts/player.gd scripts/world.gd scenes/world.tscn scripts/main.gd scenes/main.tscn
git -C D:\games\RogueCoop commit -m "feat(game): 主菜单/世界场景与玩家表现节点（预测+插值）"
```

---

## Task 9：双实例 headless 联机自动化测试

**Files:**
- Create: `tools/net_test/net_test_host.gd`
- Create: `tools/net_test/net_test_host.tscn`
- Create: `tools/net_test/net_test_client.gd`
- Create: `tools/net_test/net_test_client.tscn`
- Create: `tools/net_test/run_net_test.ps1`

**断言设计：** 客户端持续上报 `move = Vector2.RIGHT`。
- 主机侧断言：① 收到远端输入（`input_received`）；② 快照里出现 2 个玩家；③ 远端玩家 x 坐标相对首个采样右移 > 30px。
- 客户端侧断言：① 连上并拿到 `local_id`；② 收到 ≥ 10 个快照；③ 快照含 2 名玩家；④ 快照含自己；⑤ 自己的权威 x 相对首个采样右移 > 30px。

- [x] **Step 1: 实现 `tools/net_test/net_test_host.gd`**

```gdscript
extends Node
## M1 联机冒烟测试 —— 主机端。由 run_net_test.ps1 与客户端实例并行启动。

const Protocol := preload("res://net/protocol.gd")

var _t := 0.0
var _remote_input := false
var _saw_two := false
var _start_captured := false
var _client_start := Vector2.ZERO
var _client_moved := false


func _ready() -> void:
	Net.input_received.connect(_on_input)
	Net.world_state.connect(_on_state)
	var err := Net.host_start(Protocol.DEFAULT_PORT)
	if err != OK:
		printerr("[NetTest-Host] FAIL start_server err=%d" % err)
		get_tree().quit(1)


func _on_input(pid: int) -> void:
	if pid != 1:
		_remote_input = true


func _on_state(_tick: int, players: Array) -> void:
	_saw_two = players.size() >= 2
	for p in players:
		if p["id"] == 1:
			continue
		if not _start_captured:
			_client_start = p["pos"]
			_start_captured = true
		elif p["pos"].x - _client_start.x > 30.0:
			_client_moved = true


func _process(delta: float) -> void:
	_t += delta
	if _remote_input and _saw_two and _client_moved:
		print("[NetTest-Host] PASS remote_input=1 two_players=1 client_moved=1")
		get_tree().quit(0)
	elif _t > 20.0:
		printerr("[NetTest-Host] FAIL timeout remote_input=%s two_players=%s moved=%s"
			% [_remote_input, _saw_two, _client_moved])
		get_tree().quit(1)
```

- [x] **Step 2: 写 `tools/net_test/net_test_host.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/net_test/net_test_host.gd" id="1_host"]

[node name="NetTestHost" type="Node"]
script = ExtResource("1_host")
```

- [x] **Step 3: 实现 `tools/net_test/net_test_client.gd`**

```gdscript
extends Node
## M1 联机冒烟测试 —— 客户端端。由 run_net_test.ps1 与主机实例并行启动。

const Protocol := preload("res://net/protocol.gd")

var _t := 0.0
var _connected := false
var _snapshots := 0
var _saw_two := false
var _self_seen := false
var _self_start_captured := false
var _self_start := Vector2.ZERO
var _self_moved := false
var _ip := "127.0.0.1"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ip="):
			_ip = a.substr(5)

	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.world_state.connect(_on_state)

	var err := Net.client_connect(_ip, Protocol.DEFAULT_PORT)
	if err != OK:
		printerr("[NetTest-Client] FAIL connect err=%d" % err)
		get_tree().quit(1)


func _physics_process(_delta: float) -> void:
	# 持续向右移动，让主机侧观察到位移
	Net.send_local_input(Vector2.RIGHT, 0)


func _on_connected(local_id: int) -> void:
	_connected = true
	print("[NetTest-Client] connected local_id=%d" % local_id)


func _on_failed() -> void:
	printerr("[NetTest-Client] FAIL connection_failed")
	get_tree().quit(1)


func _on_state(_tick: int, players: Array) -> void:
	_snapshots += 1
	_saw_two = players.size() >= 2
	for p in players:
		if p["id"] != Net.local_id:
			continue
		_self_seen = true
		if not _self_start_captured:
			_self_start = p["pos"]
			_self_start_captured = true
		elif p["pos"].x - _self_start.x > 30.0:
			_self_moved = true


func _process(delta: float) -> void:
	_t += delta
	if _connected and _snapshots >= 10 and _saw_two and _self_seen and _self_moved:
		print("[NetTest-Client] PASS local_id=%d snapshots=%d two_players=1 moved=1"
			% [Net.local_id, _snapshots])
		get_tree().quit(0)
	elif _t > 20.0:
		printerr("[NetTest-Client] FAIL timeout connected=%s snapshots=%d two=%s self=%s moved=%s"
			% [_connected, _snapshots, _saw_two, _self_seen, _self_moved])
		get_tree().quit(1)
```

- [x] **Step 4: 写 `tools/net_test/net_test_client.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/net_test/net_test_client.gd" id="1_client"]

[node name="NetTestClient" type="Node"]
script = ExtResource("1_client")
```

- [x] **Step 5: 实现 `tools/net_test/run_net_test.ps1`**

```powershell
$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$out   = Join-Path $env:TEMP "roguecoop_nettest"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$hostOut = Join-Path $out "host.log"
$hostErr = Join-Path $out "host.err"
$cliOut  = Join-Path $out "client.log"
$cliErr  = Join-Path $out "client.err"

$host = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_host.tscn") `
    -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr

Start-Sleep -Milliseconds 1500

$client = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_client.tscn") `
    -RedirectStandardOutput $cliOut -RedirectStandardError $cliErr

$client.WaitForExit(30000) | Out-Null
$host.WaitForExit(30000) | Out-Null

$hostExit = $host.ExitCode
$cliExit  = $client.ExitCode

if (Test-Path $hostOut) { Write-Host "--- host.log ---"; Get-Content $hostOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $cliOut)  { Write-Host "--- client.log ---"; Get-Content $cliOut | ForEach-Object { Write-Host $_ } }

if ($hostExit -eq 0 -and $cliExit -eq 0) {
    Write-Host "[NetTest] ALL PASS"
    exit 0
}

Write-Host "[NetTest] FAIL host=$hostExit client=$cliExit"
if (Test-Path $hostErr) { Write-Host "--- host.err ---"; Get-Content $hostErr }
if (Test-Path $cliErr)  { Write-Host "--- client.err ---"; Get-Content $cliErr }
exit 1
```

- [x] **Step 6: 跑联机测试**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\games\RogueCoop\tools\net_test\run_net_test.ps1
```
Expected: 打印 host 与 client 的 `PASS` 行，末尾 `[NetTest] ALL PASS`，exit 0。

> 若 30s 超时：先看 `%TEMP%\roguecoop_nettest\host.err` / `client.err` 报错（autoload、RPC 路径、端口占用是三个常见根因）；端口冲突时改 `Protocol.DEFAULT_PORT` 后重跑。

- [x] **Step 7: 提交**

```powershell
git -C D:\games\RogueCoop add tools/net_test
git -C D:\games\RogueCoop commit -m "test(net): 双实例 headless 联机冒烟测试（主机权威+快照+位移断言）"
```

---

## Task 10：质量收尾与首次提交

**Files:**
- Modify: `.gitignore`
- Modify: 全部 `*.gd`（格式化）

- [x] **Step 1: 格式化全部 GDScript**

Run:
```powershell
gdformat D:\games\RogueCoop\net D:\games\RogueCoop\sim D:\games\RogueCoop\autoload D:\games\RogueCoop\scripts D:\games\RogueCoop\tools
```
Expected: 输出被改写/未改写的文件列表，无异常。

- [x] **Step 2: 静态检查**

Run:
```powershell
gdlint D:\games\RogueCoop\net D:\games\RogueCoop\sim D:\games\RogueCoop\autoload D:\games\RogueCoop\scripts D:\games\RogueCoop\tools
```
Expected: 无 error 级别问题。若有 `unused-argument` / `max-line-length` 一类告警，按提示修正或加行内 `# gdlint:ignore` 注释。

- [x] **Step 3: 回归：单元测试 + 联机测试都通过**

Run:
```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path D:\games\RogueCoop res://tools/tests/run_tests.tscn
powershell -NoProfile -ExecutionPolicy Bypass -File D:\games\RogueCoop\tools\net_test\run_net_test.ps1
```
Expected: 前者 `[UnitTests] ALL PASS` exit 0；后者 `[NetTest] ALL PASS` exit 0。

- [x] **Step 4: 追加 `.gitignore`**

在 `D:\games\RogueCoop\.gitignore` 末尾追加：

```
# 测试产物
tools/net_test/*.log
tools/net_test/*.err
tools/net_test/out/
```

- [x] **Step 5: 最终提交**

```powershell
git -C D:\games\RogueCoop add -A
git -C D:\games\RogueCoop commit -m "chore: 格式化 GDScript 并忽略测试产物（M1 完成）"
git -C D:\games\RogueCoop log --oneline
```

- [x] **Step 6: 人工联机验收（需带上显示器，非 headless）**

1. 起两个实例：
   ```powershell
   & "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path D:\games\RogueCoop --position 0,0
   & "D:\Godot\Godot_v4.7.2-stable_win64.exe" --path D:\games\RogueCoop --position 700,0
   ```
2. 实例 A 点「建立主机」→ 进入世界，出现蓝色玩家。
3. 实例 B 点「加入主机」（`127.0.0.1`）→ 进入世界，出现橙色玩家；两边都能看到对方。
4. 任一侧用 WASD 移动，另一侧应看到平滑（插值后）位移；本地玩家响应无延迟感。

Expected: 双方互见、移动同步、无卡死。

---

## 自检（写完计划后逐条核对）

**1. 需求覆盖**
- 「房主创建房间」→ Task 7 `host_start` + Task 8 主菜单按钮 ✅
- 「客户端加入」→ Task 7 `client_connect` + Task 8 主菜单按钮 ✅
- 「客户端 30Hz 上报输入帧」→ Task 7 `_physics_process` 中 `Protocol.INPUT_RATE` 节流 + `_rpc_input.rpc_id(1, ...)` ✅
- 「玩家位置同步」→ Task 6 `physics_step` + Task 7 `_send_snapshot`（20Hz）✅
- 「远端插值」→ Task 5 `interp.gd` + Task 8 `player.gd` 客户端分支 ✅
- 「1 主机 + 1 客户端 headless 自动化断言」→ Task 9 ✅

**2. 占位符扫描**：无 TODO / TBD / 「自行补充」。每个代码步骤都给了完整代码。

**3. 类型与命名一致性**
- `Protocol.encode_input(decode_input)`、`encode_snapshot/decode_snapshot`、`snapshot_size`、`INPUT_BYTES`、`PLAYER_BYTES`、`DEFAULT_PORT`、`INPUT_RATE`、`SNAPSHOT_RATE`、`MAX_PLAYERS` —— Task 2/3 定义，Task 6/7/9 使用，命名一致。
- `Net.host_start/host_stop/client_connect/client_disconnect/send_local_input/is_host/is_client/local_id` 与信号 `world_state/player_joined/player_left/input_received/connected_ok/connection_failed/disconnected` —— Task 7 定义，Task 8/9 使用，命名一致。
- `NetHostLogic.reset/add_player/remove_player/has_player/set_remote_input/physics_step/player_states/peer_ids`、`NetClientLogic.reset` —— Task 6 定义，Task 7 调用，命名一致。
- `Interp.push/sample/sample_count`、`Movement.step/SPEED` —— Task 4/5 定义，Task 8 使用，命名一致。
- `Player.setup/push_authoritative` —— Task 8 内部一致。

**4. 已知风险（执行时优先验证）**
- RPC 解析依赖 `/root/Net` 路径两端一致 —— Task 7 的 autoload 装配是硬前提，先跑 Task 7 Step 5 再跑 Task 9。
- `world_state` 在主机侧每物理帧 emit（60Hz）、客户端侧每快照 emit（20Hz）—— 表现层与网络层解耦，Task 8 `player.gd` 已按「是否客户端」分支处理两种频率。
- 客户端 `local_id` 在 `connected_to_server` 时才赋值；首帧快照可能早于该信号 → 已在 Task 8 `world.gd` 用 `id == Net.local_id` 容错（最坏情况等下一帧快照重新 `_spawn` 判定）。

**5. 下一步（不在本计划内）**
- M2：主机权威战斗（敌人 AI、伤害裁决、掉落、兴趣范围裁剪快照）。
- M3：合作肉鸽循环（共享经验池 + 每人独立选卡、倒地救援、Boss、结算）。

---

## 执行偏离记录（M1 实际执行）

本计划在执行中发现并修正了若干会导致失败的问题，记录如下，供 M2 计划复用：

1. **快照玩家 id：u16 → u32（重要）**
   - 现象：客户端连上后能收到 2 名玩家的快照，却认不出自己（`self=false`）。
   - 根因：Godot 4 的对端 `multiplayer.get_unique_id()` 是**随机大整数**（实测 331138140 / 1420896317 等），计划的 `u16` 字段把 `1420896317` 截断成 `10301`。
   - 修正：`net/protocol.gd` 中 `PLAYER_BYTES` 10 → 12，快照布局改为 `u32 tick | u8 count | N*(u32 id | f32 x | f32 y)`，即 `5 + N*12`；`encode_snapshot` 用 `encode_u32`，`decode_snapshot` 用 `decode_u32`。用例改用大 id（`1420896317`）防回归。
   - 教训：**任何承载对端 id 的字段必须 u32**，M2 若传输 player_id / target_id / owner_id 一律 u32（或直接用变长编码）。

2. **主机本地输入采样位置：表现层 → Net 层（重要）**
   - 现象：人工验收时**主机侧 WASD 无效**，客户端正常。
   - 根因：计划的 `scripts/player.gd` 只在「`is_local and Net.is_client()`」分支读输入并调 `Net.send_local_input`；主机本地玩家落到 `else: position = _auth`，主机侧**从无任何代码采样键盘**，`_host.local_move` 恒为 `Vector2.ZERO`。且 headless 测试场景里没有玩家节点，该 bug 自动化测不到。
   - 修正：把主机本地输入采样上移到 `autoload/net.gd` 的 HOST 分支（`physics_step` 之前读 `Input.get_vector(...)` + 按键），新增 `_read_local_move()` / `_read_buttons()` 私有方法。`player.gd` 主机路径保持 `position = _auth` 不变。
   - 回归锁定：`tools/net_test/net_test_host.gd` 增加 `Input.action_press("move_right")` 与 `host_moved` 断言（旧代码在此断言下必然失败）。
   - 教训：**输入采样放在 Net 层**，保证“无场景树玩家节点”的 headless 测试也能覆盖。

3. **客户端连接前不发送输入**
   - `autoload/net.gd` 的客户端分支加 `local_id != 0` 守卫，消除连接建立前 `RPC via not connected` 报错。

4. **`run_net_test.ps1` 两处坑**
   - `$host` 是 PowerShell 保留只读变量，赋值报 `VariableNotWritable`；改名 `$hostProc`。
   - `Start-Process -PassThru` 在重定向 stdout/stderr 场景下 `.ExitCode` 为空；改为按日志中的 `PASS` 标记判定（`Select-String -SimpleMatch -Quiet`）。

5. **`net_test_host` 判定健壮性**
   - 主机通过后立即 `quit()` 会切断客户端快照供给；改为「最少存活 3s」再 PASS。
   - `_saw_two` 改为粘性闩锁（客户端先退出后不再被清零），否则主机误判 timeout。

6. **单元测试计数勘误**
   - 计划 Task 2 写 `[ProtocolInput] passed=8`、Task 4 写 `[Movement] passed=6`；实际断言数为 7 / 5。以实际为准，测试全绿即可。

7. **`.gitignore` 备注**
   - 实际测试日志写入 `%TEMP%\roguecoop_nettest\`，而非 `tools/net_test/*.log`；现有忽略条目无害但指向不存在路径，可择机清理。

**自动化验收结果（M1 完成依据）**
- 单元测试：`[UnitTests] ALL PASS`（ProtocolInput 7 / ProtocolSnapshot 9 / Movement 5 / Interp 6）。
- 联机冒烟：`[NetTest] ALL PASS`（主机 `remote_input=1 two_players=1 client_moved=1 host_moved=1`；客户端 `connected snapshots=10 two_players=1 moved=1`）。
- `gdformat` 无改动、`gdlint` no problems found。
