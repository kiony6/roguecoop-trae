extends RefCounted
## 大厅服务端逻辑测试：建房 / 入房 / 满员 / 房间上限 / 离房 / 房主离线即时销毁 /
## 空置 120s 销毁（注入时钟）/ 开局 / 失败路径 / 每房独立种子 / 4 房隔离 /
## 码碰撞重试 / 入房失败限流。

const Harness := preload("res://tools/tests/harness.gd")
const LobbyServer := preload("res://net/lobby_server.gd")
const Lobby := preload("res://net/lobby.gd")
const AccountServer := preload("res://net/account_server.gd")


func run() -> int:
	var t := Harness.new()
	var acct := AccountServer.new("user://__test_lobby_accounts.json")
	_seed_accounts(acct)

	# (1)(2)(5) 建房 → 入房 → 离房（同一房内连续操作）
	var lobby_a := LobbyServer.new(acct)
	var r1: Dictionary = lobby_a.create_room(1)
	t.check(bool(r1["ok"]), "建房成功")
	t.eq(int(r1["err"]), Lobby.ERR.OK, "建房 err=OK")
	var code_a := String(r1["code"])
	t.check(Lobby.is_valid_code(code_a), "生成组队码合法")
	t.eq(lobby_a.room_count(), 1, "房间数 1")
	t.check(lobby_a.is_host(1), "peer1 是房主")
	t.eq(lobby_a.state_of(code_a), Lobby.STATE.WAITING, "初始 WAITING")
	t.eq(lobby_a.members_of(code_a), PackedInt32Array([1]), "成员 = [1]")
	t.eq(lobby_a.names_of(code_a), PackedStringArray(["alice"]), "用户名 = [alice]")

	var r2: Dictionary = lobby_a.join_room(2, code_a)
	t.check(bool(r2["ok"]), "入房成功")
	t.eq(lobby_a.members_of(code_a), PackedInt32Array([1, 2]), "房主首位")
	t.eq(lobby_a.names_of(code_a), PackedStringArray(["alice", "bob"]), "用户名按加入序")
	t.eq(lobby_a.room_of(2), code_a, "peer2 路由正确")
	t.check(not lobby_a.is_host(2), "peer2 非房主")

	var r_leave: Dictionary = lobby_a.leave_room(2)
	t.check(bool(r_leave["ok"]), "队友离房成功")
	t.eq(lobby_a.room_of(2), "", "队友路由清空")
	t.eq(lobby_a.room_count(), 1, "队友离房后房间仍在")
	var r_leave_host: Dictionary = lobby_a.leave_room(1)
	t.check(bool(r_leave_host["ok"]), "房主离房成功")
	t.eq(lobby_a.room_count(), 0, "房主离房销毁房间")

	# (3) 满员拒绝（MAX_PLAYERS=4）
	var lobby_b := LobbyServer.new(acct)
	var rb: Dictionary = lobby_b.create_room(1)
	var code_b := String(rb["code"])
	lobby_b.join_room(2, code_b)
	lobby_b.join_room(3, code_b)
	lobby_b.join_room(4, code_b)
	t.eq(lobby_b.members_of(code_b).size(), 4, "满员 4 人")
	var r_full: Dictionary = lobby_b.join_room(5, code_b)
	t.check(not bool(r_full["ok"]), "第 5 人被拒")
	t.eq(int(r_full["err"]), Lobby.ERR.ROOM_FULL, "err=ROOM_FULL")

	# (4) 房间数上限拒绝（MAX_ROOMS=4）
	var lobby_c := LobbyServer.new(acct)
	for h in [10, 11, 12, 13]:
		var rh: Dictionary = lobby_c.create_room(h)
		t.check(bool(rh["ok"]), "host %d 建房成功" % h)
	t.eq(lobby_c.room_count(), 4, "房间数 4")
	var r_over: Dictionary = lobby_c.create_room(14)
	t.check(not bool(r_over["ok"]), "第 5 房被拒")
	t.eq(int(r_over["err"]), Lobby.ERR.ROOM_LIMIT, "err=ROOM_LIMIT")

	# (6) 房主离线即时销毁 + 悬空映射清除
	var lobby_d := LobbyServer.new(acct)
	var rd: Dictionary = lobby_d.create_room(1)
	var code_d := String(rd["code"])
	lobby_d.join_room(2, code_d)
	var ev: Dictionary = lobby_d.on_peer_left(1)
	t.eq(String(ev["destroyed"]), code_d, "房主离线销毁房间")
	var affected: PackedInt32Array = ev["affected"]
	t.check(affected.has(2), "affected 含队友 2")
	t.eq(lobby_d.room_count(), 0, "房间数减 1")
	t.eq(lobby_d.room_of(2), "", "队友路由被清（无悬空映射）")

	# (7) 空置 120s 销毁（注入步进，安全网路径）
	var lobby_e := LobbyServer.new(acct)
	var re: Dictionary = lobby_e.create_room(1)
	var code_e := String(re["code"])
	lobby_e._rooms[code_e]["members"].clear()
	lobby_e._peer_room.clear()
	lobby_e.step(60.0)
	t.eq(lobby_e.room_count(), 1, "空置 60s 未销毁")
	lobby_e.step(61.0)
	t.eq(lobby_e.room_count(), 0, "空置 121s 销毁")

	# (8)(9) 开局与失败路径
	var lobby_f := LobbyServer.new(acct)
	var rf: Dictionary = lobby_f.create_room(1)
	var code_f := String(rf["code"])
	lobby_f.join_room(2, code_f)
	var r_start: Dictionary = lobby_f.start_run(1)
	t.check(bool(r_start["ok"]), "开局成功")
	t.eq(lobby_f.state_of(code_f), Lobby.STATE.RUNNING, "状态 RUNNING")
	var logic_f = lobby_f.logic_of(code_f)
	t.check(logic_f != null, "logic 非空")
	t.check(logic_f.players.has(1) and logic_f.players.has(2), "logic 含全部成员")
	t.check(logic_f.room_walls.is_empty(), "地图墙体已移除（恒为空）")
	lobby_f.step(0.2)
	t.check(logic_f.tick > 0, "step 后 tick 增长")
	t.check(lobby_f.running_rooms().has(code_f), "running_rooms 含该房")

	var r_nonhost: Dictionary = lobby_f.start_run(2)
	t.eq(int(r_nonhost["err"]), Lobby.ERR.NOT_HOST, "非房主 start → NOT_HOST")
	var r_nologin: Dictionary = lobby_f.create_room(300)
	t.eq(int(r_nologin["err"]), Lobby.ERR.NOT_LOGGED_IN, "未登录建房 → NOT_LOGGED_IN")
	var r_bad: Dictionary = lobby_f.start_run(1)
	t.eq(int(r_bad["err"]), Lobby.ERR.BAD_STATE, "已开局再 start → BAD_STATE")

	# (10) 每房独立地图种子 / 实例
	var lobby_g := LobbyServer.new(acct)
	var g1: Dictionary = lobby_g.create_room(1)
	var g2: Dictionary = lobby_g.create_room(2)
	var logic_ga = lobby_g.logic_of(String(g1["code"]))
	var logic_gb = lobby_g.logic_of(String(g2["code"]))
	t.check(logic_ga != logic_gb, "两房 logic 实例不同")
	t.check(logic_ga._rng.seed != logic_gb._rng.seed, "两房种子不同")
	t.check(logic_ga.room_walls.is_empty() and logic_gb.room_walls.is_empty(), "两房墙体均为空")

	# (11) 4 房并发隔离 + 单房 run_over 不串扰 + finish_run 只影响本房
	var lobby_h := LobbyServer.new(acct)
	var hosts := [1, 2, 3, 4]
	var codes_h: Array = []
	for h in hosts:
		var rh2: Dictionary = lobby_h.create_room(h)
		codes_h.append(String(rh2["code"]))
	for h in hosts:
		lobby_h.start_run(h)
	var logics := []
	for i in codes_h.size():
		logics.append(lobby_h.logic_of(String(codes_h[i])))
	t.check(
		logics[0] != logics[1] and logics[1] != logics[2] and logics[2] != logics[3],
		"4 房 logic 互不相同"
	)
	for i in logics.size():
		t.check(logics[i].players.has(hosts[i]) and logics[i].players.size() == 1, "房 %d 仅含本房主" % i)
	logics[0].run_over = true
	var ticks_before := []
	for i in logics.size():
		ticks_before.append(logics[i].tick)
	lobby_h.step(0.2)
	t.check(logics[1].tick > ticks_before[1], "B 房仍推进")
	t.check(logics[2].tick > ticks_before[2], "C 房仍推进")
	t.check(logics[3].tick > ticks_before[3], "D 房仍推进")
	t.check(logics[0].tick == ticks_before[0], "A 房 run_over 后不推进")
	lobby_h.finish_run(String(codes_h[0]))
	t.eq(lobby_h.state_of(String(codes_h[0])), Lobby.STATE.WAITING, "A 房置回 WAITING")
	for i in [1, 2, 3]:
		t.eq(lobby_h.state_of(String(codes_h[i])), Lobby.STATE.RUNNING, "房 %d 仍 RUNNING" % i)

	# (12) 码碰撞重试：固定 seed=7，先占用「第一支码」再建房
	var lobby_i := LobbyServer.new(acct)
	lobby_i.room_rng.seed = 7
	var probe := RandomNumberGenerator.new()
	probe.seed = 7
	var collide := Lobby.make_code(probe, {})
	lobby_i._rooms[collide] = {"code": collide}
	lobby_i._peer_room[99] = collide
	var ri: Dictionary = lobby_i.create_room(50)
	var code_i := String(ri["code"])
	t.check(bool(ri["ok"]), "碰撞后仍建房成功")
	t.check(code_i != collide, "重试跳过已占用码")
	t.check(Lobby.is_valid_code(code_i), "重试返回合法码")
	t.eq(lobby_i.room_count(), 2, "占位房 + 新房 = 2")

	# (13) 入房失败限流（滑窗 + 冷却）
	var lobby_j := LobbyServer.new(acct)
	lobby_j.test_clock_ms = 0
	var rj: Dictionary = lobby_j.create_room(200)
	var code_j := String(rj["code"])
	var absent := "999999" if code_j != "999999" else "999998"
	var r_bad1: Dictionary = lobby_j.join_room(201, "000000")
	t.eq(int(r_bad1["err"]), Lobby.ERR.BAD_CODE, "非法格式码 → BAD_CODE")
	t.check(not bool(r_bad1["limited"]), "非法格式码未被节流")
	var r_bad2: Dictionary = lobby_j.join_room(201, absent)
	t.eq(int(r_bad2["err"]), Lobby.ERR.ROOM_NOT_FOUND, "不存在码 → ROOM_NOT_FOUND")
	t.check(not bool(r_bad2["limited"]), "不存在码未被节流")
	for n in 3:
		var r_more: Dictionary = lobby_j.join_room(201, "000000")
		t.check(not bool(r_more["limited"]), "累计失败第 %d 次未被节流" % (n + 3))
	var r_limited: Dictionary = lobby_j.join_room(201, code_j)
	t.check(bool(r_limited["limited"]), "第 6 次改用真实码仍被节流")
	t.eq(int(r_limited["err"]), Lobby.ERR.ROOM_NOT_FOUND, "节流错误码 = ROOM_NOT_FOUND")
	lobby_j.test_clock_ms = LobbyServer.JOIN_COOLDOWN_MS + 1
	var r_ok: Dictionary = lobby_j.join_room(201, code_j)
	t.check(not bool(r_ok["limited"]), "冷却解除后不再节流")
	t.check(bool(r_ok["ok"]), "冷却解除后入房成功")

	return t.report("LobbyServer")


func _seed_accounts(acct) -> void:
	acct.sessions[1] = "alice"
	acct.sessions[2] = "bob"
	acct.sessions[3] = "carol"
	acct.sessions[4] = "dave"
	acct.sessions[5] = "erin"
	acct.sessions[10] = "henry"
	acct.sessions[11] = "iris"
	acct.sessions[12] = "jack"
	acct.sessions[13] = "kate"
	acct.sessions[14] = "leo"
	acct.sessions[50] = "solo"
	acct.sessions[200] = "hostx"
	acct.sessions[201] = "atkx"
