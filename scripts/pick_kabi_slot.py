#!/usr/bin/env python3
"""从 kernel/include/linux/sched.h 的 struct task_struct 里挑出可用的
ANDROID_KABI_RESERVE 槽，输出可套用的 SYSVIPC padding 补丁组。

输出形如 "6-7-8" / "3-4-5" / "1-2-3"；没有可用连续三槽时退出码 2。
"""
import re
import sys


def task_struct_block(text: str) -> str:
    i = text.find("struct task_struct {")
    if i < 0:
        raise SystemExit("struct task_struct not found")
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
    raise SystemExit("unbalanced braces in task_struct")


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "kernel/include/linux/sched.h"
    block = task_struct_block(open(path, errors="ignore").read())

    used = set()
    free = set()
    for line in block.splitlines():
        stripped = line.strip()
        if "ANDROID_KABI_USE(" in stripped:
            for n in re.findall(r"ANDROID_KABI_USE\(\s*(\d+)", stripped):
                used.add(int(n))
        if "_ANDROID_KABI_REPLACE" in stripped:
            for n in re.findall(r"ANDROID_KABI_RESERVE\(\s*(\d+)", stripped):
                used.add(int(n))
        m = re.fullmatch(r"ANDROID_KABI_RESERVE\(\s*(\d+)\s*\);", stripped)
        if m:
            free.add(int(m.group(1)))

    free -= used
    print(f"# reserved slots present: {sorted(free)}")
    print(f"# slots already in use : {sorted(used)}", file=sys.stderr)

    for group in ("6-7-8", "3-4-5", "1-2-3"):
        nums = [int(x) for x in group.split("-")]
        if all(n in free for n in nums):
            print(group)
            return 0

    print("NO-CONTIGUOUS-SLOT", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())