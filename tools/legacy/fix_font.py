# 【历史留档，勿运行】（lane doc7 定级）早期一次性补丁：读写写死的 Mac 旧路径 /Users/snowchan27/nk-1/scripts/Main.gd，把 Godot 3 式字号写法换成 add_theme_font_size_override 后整文件回写。
# 现行 Main.gd 已无替换点（0 处），本机跑会 FileNotFoundError；改路径去跑也是整文件覆盖 Main.gd。
# 不是门禁、无调用方，仅供查来历。
import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

code = code.replace('title_lbl.theme_override_font_sizes.font_size = 22', 'title_lbl.add_theme_font_size_override("font_size", 22)')
code = code.replace('sub_lbl.theme_override_font_sizes.font_size = 14', 'sub_lbl.add_theme_font_size_override("font_size", 14)')

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
