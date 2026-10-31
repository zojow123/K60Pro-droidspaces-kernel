#!/usr/bin/env python3
"""把 capture-device.sh 采回的目录解析成 evidence/vendor-module-versions.json。

用法：
    python3 scripts/parse-capture.py /path/to/ds-capture
"""
from __future__ import annotations

import gzip
import json
import sys
import tarfile
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from elf_versions import module_versions  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "/sdcard/Download/ds-capture")
    if not src.is_dir():
        raise SystemExit(f"capture directory not found: {src}")

    # ---- device summary ----
    device = {}
    for line in (src / "device.txt").read_text(errors="ignore").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            device[k.strip()] = v.strip()
    print(json.dumps(device, indent=2, ensure_ascii=False))

    release = device.get("kernel_release", "")
    lock_release = json.load(open(ROOT / "config/sources.lock.json"))["kernel"]["release"]
    if release and release != lock_release:
        print(f"!! 设备内核版本 {release} 与 lock 中的 {lock_release} 不一致，请更新 sources.lock.json")

    # ---- baseline config ----
    config = gzip.decompress((src / "config.gz").read_bytes()).decode("utf-8", "replace")
    (ROOT / "config/device-baseline.config").write_text(config, encoding="utf-8", newline="\n")
    print(f"== config written: {len(config.splitlines())} lines")

    # ---- vendor module import CRCs ----
    inventory: dict[str, dict[str, str]] = {}
    with tarfile.open(src / "vendor-modules.tar") as archive:
        for member in archive:
            if member.isfile() and member.name.endswith(".ko"):
                data = archive.extractfile(member).read()
                try:
                    inventory[Path(member.name).name] = module_versions(data)
                except ValueError as exc:
                    print(f"   skip {member.name}: {exc}")
    if not inventory:
        raise SystemExit("no vendor modules parsed")
    print(f"== vendor modules: {len(inventory)}, imported symbols: {sum(len(v) for v in inventory.values())}")

    # ---- kallsyms export classification ----
    kernel_exports, vendor_exports = [], []
    for line in (src / "kallsyms.txt").read_text(errors="ignore").splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[2].startswith("__ksymtab_"):
            symbol = fields[2][len("__ksymtab_"):]
            (kernel_exports if len(fields) == 3 else vendor_exports).append(symbol)
    if not kernel_exports:
        raise SystemExit("no __ksymtab_ entries in kallsyms")
    print(f"== kernel exports: {len(set(kernel_exports))}, vendor exports: {len(set(vendor_exports))}")

    modules_txt = (src / "modules.txt").read_text(errors="ignore").splitlines()
    summary = {
        "collected_date": datetime.now().date().isoformat(),
        "device": device.get("device"),
        "model": device.get("model"),
        "rom_version": device.get("rom_version"),
        "android_version": device.get("build_release"),
        "security_patch": device.get("security_patch"),
        "kernel_release": release,
        "selinux": device.get("selinux"),
        "active_slot": device.get("slot"),
        "boot_partition_size": int(device.get("boot_size") or 0),
        "init_boot_partition_size": int(device.get("init_boot_size") or 0),
        "loaded_modules": len(modules_txt),
        "root_module": [l.split()[0] for l in modules_txt
                        if any(t in l.lower() for t in ("kernelsu", "sukisu", "ksu"))],
    }
    (ROOT / "evidence/device-summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    payload = {
        "modules": inventory,
        "kernel_exports": sorted(set(kernel_exports)),
        "vendor_exports": sorted(set(vendor_exports)),
    }
    out = ROOT / "evidence/vendor-module-versions.json"
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"== written {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())