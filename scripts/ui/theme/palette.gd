extends RefCounted
## 甲·夜幕蓝：全工程唯一取色 / 取字号事实源。
## 只放常量、无任何依赖；页面与 HUD 一律从这里取值，禁止在别处写字面量颜色。

# ---- 核心 6 色（用户已确认的「甲」，一字不改）----
const BG := Color("#2a3550")
const SURFACE := Color("#3d4d70")
const BORDER := Color("#5566aa")
const PRIMARY := Color("#4aa3ff")
const ACCENT := Color("#ffd93d")
const DANGER := Color("#b23b3b")

# ---- 派生 5 色（甲未列出，本次新增；需要改色只改这里）----
const TEXT := Color("#e8eefb")
const TEXT_MUTED := Color("#8b9bc4")
const ON_PRIMARY := Color("#0e1524")
const SURFACE_HOVER := Color("#46587f")
const SURFACE_PRESSED := Color("#2f3a57")

# ---- 字号台阶（像素字体必须取 12 的整数倍，否则缩放发虚）----
const FONT_CODE := 48
const FONT_TITLE := 36
const FONT_BODY := 24
const FONT_CAPTION := 12
