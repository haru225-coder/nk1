# 【历史留档，勿运行】（lane doc7 定级）早期一次性补丁：读写写死的 Mac 旧路径 /Users/snowchan27/nk-1/scripts/Main.gd，把 "port_quanzhou" / "port_xinghua" 替换成短 id 后整文件回写。
# 现行 Main.gd 已无替换点（0 处），本机跑会 FileNotFoundError；改路径去跑也是整文件覆盖 Main.gd。
# 不是门禁、无调用方，仅供查来历。
import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

code = code.replace('"port_quanzhou"', '"quanzhou"')
code = code.replace('"port_xinghua"', '"xinghua"')

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
