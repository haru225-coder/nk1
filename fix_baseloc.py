import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

code = code.replace('"port_quanzhou"', '"quanzhou"')
code = code.replace('"port_xinghua"', '"xinghua"')

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
