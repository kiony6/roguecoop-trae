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
