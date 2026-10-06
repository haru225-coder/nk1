#!/usr/bin/env godot --headless -s
## 英文批次 29 张立绘 + 3 张零消费背景 载入自证探针（lane portrait-wiring，2026-10-05）
## 用法：godot --headless --path <项目根> -s tools/art/load_en_batch.gd
## 逐张 load() 在库 <id>_en.png 与三张 bg_*.jpg：任一取不回 Texture2D 即退出码 1。
## 这是「接线后 headless 载入不报错」的实测门禁，独立于 compile 检查（后者只编译脚本、不解码贴图）。
extends SceneTree

const EN_IDS := [
	"ai_thong_siam", "awang_foluoan", "boni_mayang", "cai_shijiu", "folian",
	"gandha_tengliumei", "han_deukryong", "kafur", "kham_luohu_broker", "le_tac",
	"mayi_batu", "muttu", "nampo_shomyo", "niu_lver", "pham_ngu_lao",
	"pisheye_tiezai", "sanyu_alon", "si_parut_javaka", "takezaki_suenaga", "xie_ao",
	"yan_zhongan", "yu_yuanqing", "zeng_yan", "zhang_xuan", "zhao_zhong",
	"zheng_shiyi_niang", "zhiligan", "zhou_axi", "zhu_qing",
]
const BG_FILES := ["bg_sea_cabin.jpg", "bg_porcelain_kiln.jpg", "bg_lacquer_workshop.jpg"]


func _initialize() -> void:
	var fails: Array = []
	for id in EN_IDS:
		_probe("res://assets/portraits/%s_en.png" % id, fails)
	for f in BG_FILES:
		_probe("res://assets/%s" % f, fails)
	if fails.is_empty():
		print("EN_BATCH_OK 29 立绘 + 3 背景 全载入通道绿（资源系统或 Image 兜底，任取其一即为 non-empty 位图）")
		quit(0)
	else:
		for f in fails:
			printerr("FAIL: ", f)
		quit(1)


func _probe(path: String, fails: Array) -> void:
	# 第一支：资源系统导入通道。仓内 assets 的 .ctex 不入 git，.godot/imported/ 是本地缓存，
	# headless 首跑必将 load() 返回 null（cs_kit.load_texture 源码本为此型立的兜）。
	if ResourceLoader.exists(path, "Texture2D"):
		var t := load(path) as Texture2D
		if t != null and t.get_width() > 0:
			return
	# 第二支（Image 兜底，须能解码出非空位图才算「载入不报错」）
	if not FileAccess.file_exists(path):
		fails.append("%s：文件不在库" % path)
		return
	var img := Image.new()
	var err := img.load(path)
	if err != OK or img.is_empty() or img.get_width() <= 0:
		fails.append("%s：Image 解码失败（err=%d）" % [path, err])
