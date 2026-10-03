## lane w30-k3 qa_crew_fold_probe 的仿作宿主：LogFold.render 直收此件近况字段
## （LogFold 只读写宿主的五件现价字段，仿作件在此各备一件，探针直调 render(host, sep, dim_rest)）
extends Object

var _log_lines: PackedStringArray = PackedStringArray()
var _log_folds: Dictionary = {}
var _log_fold_open: String = ""
var _notice_run: int = 0
var _notice_when: Array = []
