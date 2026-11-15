#!/usr/bin/env python3
"""从 nginx 站点文件里删除已插入的 Agar 位置块（/agar/ 与 /socket.io/），供改版片段重新插入。
用法: nginx_remove_agar.py <site_file>"""
import sys

path = sys.argv[1]
lines = open(path).read().splitlines(True)
out = []
i = 0
removed = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    if (stripped.startswith("location /agar/") or stripped.startswith("location ^~ /agar/")
            or stripped.startswith("location /socket.io/")) and stripped.endswith("{"):
        # 连同上方紧邻的 MAX Agar 注释行一起删（若已暂存）
        if out and "MAX Agar" in out[-1]:
            out.pop()
        depth = 0
        while i < len(lines):
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
            if depth == 0:
                break
        removed += 1
        continue
    out.append(line)
    i += 1
open(path, "w").write("".join(out))
print(f"removed {removed} agar location block(s)")
