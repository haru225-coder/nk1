extends Node
# ResourceManager — 全局共享资源预加载 Autoload
# 避免多个脚本重复 preload 同一场景，统一管理公共 PackedScene 引用

const FloatingText = preload(ResourcePaths.SCENE_FLOATING_TEXT)
