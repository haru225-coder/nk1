extends RefCounted
## 按名认函数的源码探查（lane cs15；Python 门禁那份是 tools/src_probe.py，口径同）。
## 光秃 find 只按前缀认：`src.find("func X")` 认到 func X_v2，`body.find("X(")` 认到 _X( / fooX(，
## 定位锚 find 落到 _X 上——函数一改名（调用点同改），正向断言照样打「已定义 / 已调用」。一律改走这里：
##   has_func(src, name)          行首 `[static ]func 名字(`（名尾须紧跟括号，不认 X_v2 / 注释 / 文案里的字样）。
##   func_at(src, name)           同一口径，给手切函数体的：返回那一行 `func` 的下标，取不到 -1（同 String.find）。
##   func_body(src, name)         同一口径取函数体（到下一个行首 func / static func 为止），取不到 ""。
##   calls(src, name)             按名调用 `名字(` 或 `名字.bind(` / `.call(` / `.callv(`；名前不接标识符或点（名字可带宿主）。
##   has_tok / tok_find(src, lit) 字面量按标识符边界认：头是标识符字符就要求前面不接标识符字符，尾同理；
##                                call=true 时 lit 是名字，后面须紧跟 `(` 或 `.bind(` 等（宿主不限）。
## 每处新条件都严格蕴含旧的 find >= 0，只收紧不放宽。反向断言（find < 0）不走这里：按前缀认只会多红。

const _CALL_TAIL := "\\s*(?:\\(|\\.(?:bind|call|callv)\\s*\\()"


static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


static func _is_word(ch: String) -> bool:
	return ch == "_" or (ch >= "0" and ch <= "9") or (ch.to_lower() >= "a" and ch.to_lower() <= "z")


static func _search(pattern: String, src: String, from := 0) -> RegExMatch:
	var rx := RegEx.new()
	if rx.compile(pattern) != OK:
		push_error("src_probe: 正则编不过 " + pattern)
		return null
	return rx.search(src, from)


static func has_func(src: String, name: String) -> bool:
	return func_at(src, name) >= 0


static func func_at(src: String, name: String) -> int:
	var m := _search("(?m)^[ \\t]*(?:static\\s+)?(func\\s+" + _esc(name) + "\\s*\\()", src)
	return m.get_start(1) if m != null else -1


static func func_body(src: String, name: String) -> String:
	var at := func_at(src, name)
	if at < 0:
		return ""
	var m := _search("(?m)^(?:static\\s+)?func\\s", src, at + 1)
	return src.substr(at, (m.get_start() if m != null else src.length()) - at)


static func calls(src: String, name: String) -> bool:
	return _search("(?<![\\w.])" + _esc(name) + _CALL_TAIL, src) != null


static func tok_find(src: String, lit: String, from := 0, call := false) -> int:
	var p := _esc(lit)
	if _is_word(lit.left(1)):
		p = "(?<!\\w)" + p
	if call:
		p += _CALL_TAIL
	elif _is_word(lit.right(1)):
		p += "(?!\\w)"
	var m := _search(p, src, from)
	return m.get_start() if m != null else -1


static func has_tok(src: String, lit: String, call := false) -> bool:
	return tok_find(src, lit, 0, call) >= 0
