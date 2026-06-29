extends Node
## 资产占位解析 — 缺失贴图时回退到别名或 placeholders 目录
## NK1-P6-POLISH-004: 别名映射从 data/asset_backgrounds.json 加载，支持热重载

const PORTRAIT_DIR := "res://assets/portraits/"
const PLACEHOLDER_DIR := "res://assets/placeholders/"
const BG_FALLBACK := PLACEHOLDER_DIR + "bg_fallback.png"
const AVATAR_FALLBACK := PORTRAIT_DIR + "portrait_fallback.png"
const LEGACY_AVATAR_FALLBACK := PLACEHOLDER_DIR + "avatar_fallback.png"
const _CONFIG_PATH := "res://data/asset_backgrounds.json"

## NK1-P6-POLISH-004: 运行时从 JSON 加载的别名映射（懒加载）
var _bg_aliases: Dictionary = {}
var _bg_pools: Dictionary = {}
var _legacy_avatars: Dictionary = {}
var _config_loaded: bool = false
var _pool_indices: Dictionary = {}
var _pool_files_cache: Dictionary = {}

## NK1-P6-POLISH-004: 兼容性硬编码 fallback（JSON 加载失败时使用）
const _FALLBACK_BG_ALIASES: Dictionary = {
	"res://assets/bg_xinghua_school.png": "res://assets/bg_xinghua_residence.png",
	"res://assets/bg_quanzhou_port.png": "res://assets/bg_quanzhou_harbor_koei.png",
	"res://assets/bg_quanzhou_port_sunset.png": "res://assets/bg_quanzhou_harbor_koei.png",
	"res://assets/bg_lin_ship.png": "res://assets/bg_shipyard.jpg",
	"res://assets/bg_departure.png": "res://assets/bg_sea_route_ship.png",
	"res://assets/bg_penghu_night.png": "res://assets/bg_penghu_port.png",
	"res://assets/bg_black_water.png": "res://assets/bg_departure.png",
	"res://assets/bg_sea_route_aligned.png": "res://assets/bg_black_water.png",
	"res://assets/bg_keelung_coast.png": "res://assets/bg_keelung_port.png",
	"res://assets/bg_guangzhou_port.png": "res://assets/bg_guangzhou_harbor_koei.png",
	"res://assets/bg_mingzhou_port.png": "res://assets/bg_quanzhou_harbor_koei.png",
	"res://assets/bg_wenzhou_port.png": "res://assets/bg_quanzhou_harbor_koei.png",
	"res://assets/bg_keelung_port.png": "res://assets/bg_keelung_coast.png",
	"res://assets/bg_penghu_port.png": "res://assets/bg_penghu_night.png",
	"res://assets/bg_hakata_port.png": "res://assets/bg_western_port.png",
	"res://assets/bg_champa_port.png": "res://assets/bg_arab_desert_pass.png",
	"res://assets/bg_jeju_port.png": "res://assets/bg_northern_fortress_snow.png",
	"res://assets/bg_ganpu_port.png": "res://assets/bg_black_water.png",
	"res://assets/bg_zhangzhou_port.png": "res://assets/bg_quanzhou_port_sunset.png",
	"res://assets/bg_qiongzhou_port.png": "res://assets/bg_reef_bay_koei.png",
	"res://assets/bg_sanfoqi_port.png": "res://assets/bg_arab_mosque.jpg",
	"res://assets/bg_longyamen_port.png": "res://assets/bg_black_water.png",
	"res://assets/bg_bugan_port.png": "res://assets/bg_temple_gate.jpg",
	"res://assets/bg_jiaozhi_port.png": "res://assets/bg_quanzhou_arab_market.png",
	"res://assets/bg_yeshou_port.png": "res://assets/bg_temple_library.jpg",
	"res://assets/bg_tunmen_port.png": "res://assets/bg_customs_patrol.png",
	"res://assets/bg_tsushima_port.png": "res://assets/bg_northern_fortress_snow.png",
	"res://assets/bg_byland_port.png": "res://assets/bg_northern_fortress_snow.png",
	"res://assets/bg_xuwen_port.png": "res://assets/bg_reef_bay.jpg",
}

const _FALLBACK_LEGACY_AVATARS: Dictionary = {
	"chen_wenlong": PLACEHOLDER_DIR + "avatar_chen.png",
	"teacher": PLACEHOLDER_DIR + "avatar_teacher.png",
	"jia_disciple": PLACEHOLDER_DIR + "avatar_jia.png",
	"lin_boyuan": PLACEHOLDER_DIR + "avatar_lin.png",
	"abbas": PLACEHOLDER_DIR + "avatar_abbas.png",
	"customs_official": PLACEHOLDER_DIR + "avatar_official.png",
	"ketagalan_elder": PLACEHOLDER_DIR + "avatar_elder.png",
	"ketagalan_child": PLACEHOLDER_DIR + "avatar_child.png",
}

## NK1-P6-POLISH-004: 加载 JSON 配置（懒加载 + 缓存）
func _ensure_config_loaded() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	if not FileAccess.file_exists(_CONFIG_PATH):
		_bg_aliases = _FALLBACK_BG_ALIASES.duplicate()
		_legacy_avatars = _FALLBACK_LEGACY_AVATARS.duplicate()
		return
	var f := FileAccess.open(_CONFIG_PATH, FileAccess.READ)
	if f == null:
		_bg_aliases = _FALLBACK_BG_ALIASES.duplicate()
		_legacy_avatars = _FALLBACK_LEGACY_AVATARS.duplicate()
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_bg_aliases = _FALLBACK_BG_ALIASES.duplicate()
		_legacy_avatars = _FALLBACK_LEGACY_AVATARS.duplicate()
		return
	var data = json.data
	if data is Dictionary:
		_bg_aliases = (data.get("bg_aliases", {}) as Dictionary).duplicate()
		_bg_pools = (data.get("bg_pools", {}) as Dictionary).duplicate()
		_legacy_avatars = (data.get("legacy_avatars", {}) as Dictionary).duplicate()
	else:
		_bg_aliases = _FALLBACK_BG_ALIASES.duplicate()
		_legacy_avatars = _FALLBACK_LEGACY_AVATARS.duplicate()

## NK1-P6-POLISH-004: 热重载（测试用）
func reload_config() -> void:
	_config_loaded = false
	_bg_aliases.clear()
	_bg_pools.clear()
	_legacy_avatars.clear()
	_pool_indices.clear()
	_pool_files_cache.clear()
	_ensure_config_loaded()

## NK1-P6-POLISH-004: 公开 API — 根据别名 key 查询实际路径
func get_background_path(alias_key: String) -> String:
	_ensure_config_loaded()
	return _bg_aliases.get(alias_key, alias_key)


## 进港背景轮换：有图池则按序轮播，否则走别名回退。
func pick_background_path(alias_key: String) -> String:
	_ensure_config_loaded()
	if alias_key.is_empty():
		return alias_key
	if _bg_pools.has(alias_key):
		var files: Array = _list_pool_files(str(_bg_pools[alias_key]))
		if not files.is_empty():
			var idx: int = int(_pool_indices.get(alias_key, 0)) % files.size()
			_pool_indices[alias_key] = idx + 1
			return str(files[idx])
	return get_background_path(alias_key)


func _list_pool_files(pool_dir: String) -> Array:
	if _pool_files_cache.has(pool_dir):
		return _pool_files_cache[pool_dir]
	var files: Array = []
	if not pool_dir.ends_with("/"):
		pool_dir += "/"
	var abs_dir := ProjectSettings.globalize_path(pool_dir)
	var dir := DirAccess.open(abs_dir)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and (entry.ends_with(".jpg") or entry.ends_with(".png")):
				files.append(pool_dir + entry)
			entry = dir.get_next()
		dir.list_dir_end()
	files.sort()
	_pool_files_cache[pool_dir] = files
	return files

## NK1-P6-POLISH-004: 公开 API — 查询 NPC legacy 头像路径
func get_legacy_avatar_path(npc_id: String) -> String:
	_ensure_config_loaded()
	return _legacy_avatars.get(npc_id, "")

var _texture_cache: Dictionary = {}

func resolve_path(path: String, category: String = "texture") -> String:
	if path == "":
		return _default_for(category)
	if _exists(path):
		return path
	_ensure_config_loaded()
	if _bg_aliases.has(path):
		var alias: String = _bg_aliases[path]
		if _exists(alias):
			return alias
	return _default_for(category)

func _portrait_path(npc_id: String) -> String:
	return PORTRAIT_DIR + "portrait_" + npc_id + ".png"

func resolve_avatar(npc_id: String, configured_path: String = "") -> String:
	if configured_path != "" and _exists(configured_path):
		return configured_path
	if npc_id != "":
		var portrait_path := _portrait_path(npc_id)
		if _exists(portrait_path):
			return portrait_path
		_ensure_config_loaded()
		if _legacy_avatars.has(npc_id):
			var legacy: String = _legacy_avatars[npc_id]
			if _exists(legacy):
				return legacy
	if _exists(AVATAR_FALLBACK):
		return AVATAR_FALLBACK
	if _exists(LEGACY_AVATAR_FALLBACK):
		return LEGACY_AVATAR_FALLBACK
	return ""

func load_texture(path: String, category: String = "texture") -> Texture2D:
	var resolved := resolve_path(path, category)
	if _texture_cache.has(resolved):
		return _texture_cache[resolved]
	var tex := _load_texture_from_disk(resolved)
	if tex == null:
		var fallback := _default_for(category)
		if fallback != resolved:
			tex = _load_texture_from_disk(fallback)
	if tex:
		_texture_cache[resolved] = tex
	return tex

func _default_for(category: String) -> String:
	if category == "avatar":
		if _exists(AVATAR_FALLBACK):
			return AVATAR_FALLBACK
		return LEGACY_AVATAR_FALLBACK
	return BG_FALLBACK

func _exists(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path):
		return true
	return FileAccess.file_exists(ProjectSettings.globalize_path(path))

func _load_texture_from_disk(path: String) -> Texture2D:
	if not _exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex:
		return tex
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null