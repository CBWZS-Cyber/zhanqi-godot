#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查 Godot 导出包（.pck / 内嵌 pck 的 exe）里**到底装了什么**。

用途：验证 `export_presets.cfg` 的 include/exclude 规则是否按预期生效。
      改过导出设置后**必须**跑一次 —— filter 写错会把脚本一起排除、包直接废，
      而"导出成功"本身不会报任何错。

用法：
    # 1) 先导出一个 pck（只写 pck、不写 exe，快）
    godot --headless --path . --export-pack "Windows Desktop" /tmp/t.pck
    # 2) 检查
    python tools/inspect_pck.py /tmp/t.pck

背景（README 注意点 33）：
    本工程 `export_filter="all_resources"` → 导出**工程里所有资源**（不管有没有被引用）。
    而 `.md` / `.html` **不是 Godot 资源**，也没人 `load()` 它们 → **天然不进包**。
    所以「放进工程目录」≠「进程序包」，取决于它是不是资源类型。
"""

import collections
import re
import sys

# 期望【不在】包里的（出现即为 FAIL）
MUST_BE_ABSENT = {
    "tests/": "测试脚本（_probes/ 里硬编码服务器地址）",
    "_backup_": "备份目录（漏加 .gdignore 时会进包）",
    "res://Godot/": "根目录那个编辑器数据目录（611MB，误建）",
}
# 期望【在】包里的（缺失即为 FAIL —— 说明 filter 误伤了）
MUST_BE_PRESENT = {
    ".gdc": "脚本导出产物（少了说明 filter 把脚本一起排除了）",
    "res://scripts/": "源码目录",
    "res://assets/": "素材目录",
}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    blob = open(sys.argv[1], "rb").read()

    paths = sorted(set(m.decode("utf-8", "replace")
                       for m in re.findall(rb"res://[A-Za-z0-9_./\-]+", blob)))

    print("包体积   = %.1f MB" % (len(blob) / 1048576.0))
    print("路径条目 = %d" % len(paths))

    print("\n--- 目录分布 ---")
    dirs = collections.Counter()
    for p in paths:
        parts = p[6:].split("/")
        dirs[parts[0] if len(parts) > 1 else "(根目录)"] += 1
    for k, v in dirs.most_common():
        print("  %-22s %d" % (k, v))

    print("\n--- 文档类（bytes 精确搜；`.md`/`.py` 的少量命中多为二进制巧合字节）---")
    for kw in ["README.md", "CHANGELOG.md", ".html"]:
        print("  %-14s %d 次" % (kw, blob.count(kw.encode())))
    for kw in ["UI设计系统", "设计系统"]:
        print("  %-14s %d 次（UTF-8）" % (kw, blob.count(kw.encode("utf-8"))))

    fails = []

    print("\n--- ★ 必须【不在】包里 ---")
    for kw, why in MUST_BE_ABSENT.items():
        n = len([p for p in paths if kw in p]) if kw.startswith("res://") \
            else len([p for p in paths if kw in p or kw in p[6:]])
        mark = "✓" if n == 0 else "✗"
        if n:
            fails.append("%s 仍有 %d 条" % (kw, n))
        print("  %s %-16s %3d 条   （%s）" % (mark, kw, n, why))

    print("\n--- ★ 必须【在】包里 ---")
    for kw, why in MUST_BE_PRESENT.items():
        n = blob.count(kw.encode()) if kw.startswith(".") else len([p for p in paths if p.startswith(kw)])
        mark = "✓" if n > 0 else "✗"
        if n == 0:
            fails.append("%s 缺失" % kw)
        print("  %s %-16s %3d" % (mark, kw, n) + "   （%s）" % why)

    print()
    if fails:
        print("== FAIL ==")
        for f in fails:
            print("  · " + f)
        return 1
    print("== PASS：排除规则正确，且未误伤脚本与素材 ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
