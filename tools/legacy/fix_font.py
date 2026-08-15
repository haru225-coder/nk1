import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

code = code.replace('title_lbl.theme_override_font_sizes.font_size = 22', 'title_lbl.add_theme_font_size_override("font_size", 22)')
code = code.replace('sub_lbl.theme_override_font_sizes.font_size = 14', 'sub_lbl.add_theme_font_size_override("font_size", 14)')

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
