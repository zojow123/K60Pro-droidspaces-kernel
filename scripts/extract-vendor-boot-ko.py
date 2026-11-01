#!/usr/bin/env python3
"""从 Android vendor_boot.img 提取 vendor_ramdisk 里的 .ko 模块。

用法： python3 scripts/extract-vendor-boot-ko.py <vendor_boot.img> <输出目录>

支持 header v3/v4，ramdisk 压缩格式：lz4-legacy / lz4-frame / gzip / 未压缩。
"""
from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

CPIO_NEWC = b"070701"


def align(n: int, page: int) -> int:
    return (n + page - 1) // page * page


def parse_header(data: bytes) -> dict:
    if data[:8] != b"VNDRBOOT":
        raise SystemExit("not a vendor_boot image")
    hv, page = struct.unpack_from("<II", data, 8)
    if hv not in (3, 4):
        raise SystemExit(f"unsupported header version {hv}")
    ramdisk_addr, ramdisk_size = struct.unpack_from("<II", data, 20)
    header_size = struct.unpack_from("<I", data, 2096)[0] if hv == 4 else 2112
    return {
        "header_version": hv,
        "page_size": page,
        "ramdisk_addr": ramdisk_addr,
        "ramdisk_size": ramdisk_size,
        "header_size": header_size,
        "ramdisk_offset": align(header_size, page),
    }


def decompress(raw: bytes) -> bytes:
    if raw[:4] == b"\x02\x21\x4c\x18" or raw[:4] == b"\x04\x22\x4d\x18":
        with tempfile.NamedTemporaryFile(suffix=".lz4") as f:
            f.write(raw)
            f.flush()
            out = subprocess.run(["lz4", "-d", "-c", f.name], capture_output=True, check=True)
            return out.stdout
    if raw[:2] == b"\x1f\x8b":
        import gzip
        return gzip.decompress(raw)
    return raw


def iter_cpio(blob: bytes):
    pos = 0
    n = len(blob)
    while pos + 110 <= n:
        if blob[pos:pos + 6] != CPIO_NEWC:
            break
        fields = [int(blob[pos + 6 + i * 8: pos + 14 + i * 8], 16) for i in range(13)]
        mode, filesize, namesize = fields[1], fields[6], fields[11]
        name_start = pos + 110
        name = blob[name_start:name_start + namesize - 1].decode(errors="replace")
        data_start = align(name_start + namesize, 4)
        data = blob[data_start:data_start + filesize]
        pos = align(data_start + filesize, 4)
        if name == "TRAILER!!!":
            break
        yield name, data


def main() -> int:
    img = Path(sys.argv[1])
    outdir = Path(sys.argv[2] if len(sys.argv) > 2 else "vb-ko")
    outdir.mkdir(parents=True, exist_ok=True)

    data = img.read_bytes()
    hdr = parse_header(data)
    print(f"== header v{hdr['header_version']}, page {hdr['page_size']}, "
          f"ramdisk {hdr['ramdisk_size']} bytes @ {hdr['ramdisk_offset']}")

    raw = data[hdr["ramdisk_offset"]: hdr["ramdisk_offset"] + hdr["ramdisk_size"]]
    blob = decompress(raw)
    print(f"== ramdisk decompressed: {len(blob)} bytes")

    count = 0
    total = 0
    for name, payload in iter_cpio(blob):
        if name.endswith(".ko"):
            target = outdir / Path(name).name
            target.write_bytes(payload)
            count += 1
            total += len(payload)
    print(f"== extracted {count} .ko ({total} bytes) -> {outdir}")
    return 0 if count else 1


if __name__ == "__main__":
    sys.exit(main())