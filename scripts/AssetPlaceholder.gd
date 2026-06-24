extends Node
## 资产占位解析 — 缺失贴图时回退到别名或 placeholders 目录

const PORTRAIT_DIR := "res://assets/portraits/"
const PLACEHOLDER_DIR := "res://assets/placeholders/"
const BG_FALLBACK := PLACEHOLDER_DIR + "bg_fallback.png"
const AVATAR_FALLBACK := PORTRAIT_DIR + "portrait_fallback.png"
const LEGACY_AVATAR_FALLBACK := PLACEHOLDER_DIR + "avatar_fallback.png"

const BG_ALIASES: Dictionary = {
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

const LEGACY_AVATAR_BY_NPC: Dictionary = {
	"chen_wenlong": PLACEHOLDER_DIR + "avatar_chen.png",
	"teacher": PLACEHOLDER_DIR + "avatar_teacher.png",
	"jia_disciple": PLACEHOLDER_DIR + "avatar_jia.png",
	"lin_boyuan": PLACEHOLDER_DIR + "avatar_lin.png",
	"abbas": PLACEHOLDER_DIR + "avatar_abbas.png",
	"customs_official": PLACEHOLDER_DIR + "avatar_official.png",
	"ketagalan_elder": PLACEHOLDER_DIR + "avatar_elder.png",
	"ketagalan_child": PLACEHOLDER_DIR + "avatar_child.png",
}

var _texture_cache: Dictionary = {}

func resolve_path(path: String, category: String = "texture") -> String:
	if path == "":
		return _default_for(category)
	if _exists(path):
		return path
	if BG_ALIASES.has(path):
		var alias: String = BG_ALIASES[path]
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
		if LEGACY_AVATAR_BY_NPC.has(npc_id):
			var legacy: String = LEGACY_AVATAR_BY_NPC[npc_id]
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