#!/usr/bin/env python3
"""把 snippet 插入 nginx 站点文件的每一个 server 块（块内已有 needle 时跳过）。
用法: nginx_insert.py <site_file> <snippet_file> <needle>"""
import re
import sys

site_path, snippet_path, needle = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(site_path).read()
snippet = open(snippet_path).read()
if not snippet.endswith("\n"):
    snippet += "\n"

out, block, depth, changed = [], [], 0, False
for line in src.splitlines(True):
    block.append(line)
    depth += line.count("{") - line.count("}")
    if depth == 0 and block:
        text = "".join(block)
        head = text.split("{", 1)[0]
        if "server" in head and needle not in text:
            idx = text.rstrip().rfind("}")
            text = text[:idx] + snippet + text[idx:]
            changed = True
        out.append(text)
        block = []
if block:
    out.append("".join(block))
res = "".join(out)

if "access_log" not in res:
    res = res.replace("server_name", "access_log /var/log/nginx/access.log cf_combined;\n    server_name", 1)
elif "cf_combined" not in res:
    res = re.sub(r"access_log\s+[^;]+;", "access_log /var/log/nginx/access.log cf_combined;", res, count=1)

open(site_path, "w").write(res)
print("inserted" if changed else "already present")
