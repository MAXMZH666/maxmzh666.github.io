#!/usr/bin/env python3
"""把社区子域名 301 跳转块插入主站 nginx 配置的 443 server 块（仅 server_name 含 maxmzh.com
且不含 community.maxmzh.com 的块）。带标记、幂等；调用方负责备份与 nginx -t 校验。
用法: nginx_redirect_insert.py <site_file>
"""
import sys

MARKER = "community-subdomain-redirect"
SNIPPET = (
    "    # BEGIN " + MARKER + "\n"
    "    location ~ ^/community[^/]*(\\.html)?$ {\n"
    "        return 301 https://community.maxmzh.com$request_uri;\n"
    "    }\n"
    "    # END " + MARKER + "\n"
)

path = sys.argv[1]
src = open(path).read()
if MARKER in src:
    print("already present")
    sys.exit(0)

out, block, depth, changed = [], [], 0, False
for line in src.splitlines(True):
    block.append(line)
    depth += line.count("{") - line.count("}")
    if depth == 0 and block:
        text = "".join(block)
        head = text.split("{", 1)[0]
        if (
            "server" in head
            and "listen 443" in text
            and "maxmzh.com" in text
            and "community.maxmzh.com" not in text
        ):
            idx = text.rstrip().rfind("}")
            text = text[:idx] + SNIPPET + text[idx:]
            changed = True
        out.append(text)
        block = []
if block:
    out.append("".join(block))

if not changed:
    print("NO_TARGET_BLOCK")
    sys.exit(2)
open(path, "w").write("".join(out))
print("inserted")
