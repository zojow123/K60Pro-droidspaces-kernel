"""Read Linux module __versions from uncompressed ELF64 little-endian .ko files.

Uses only Python's standard library; works on Windows and GitHub runners.
"""
from __future__ import annotations

import struct


def module_versions(data: bytes) -> dict[str, str]:
    if data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected a little-endian ELF64 kernel module")
    shoff = struct.unpack_from("<Q", data, 40)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 58)
    if shentsize != 64 or shstrndx >= shnum:
        raise ValueError("Unsupported ELF section table")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize)
                for i in range(shnum)]
    names_section = sections[shstrndx]
    names = data[names_section[4]:names_section[4] + names_section[5]]
    for section in sections:
        name = names[section[0]:].split(b"\0", 1)[0]
        if name == b"__versions":
            payload = data[section[4]:section[4] + section[5]]
            if len(payload) % 64:
                raise ValueError("Unsupported modversion_info record size")
            result = {}
            for offset in range(0, len(payload), 64):
                crc = struct.unpack_from("<Q", payload, offset)[0]
                symbol = payload[offset + 8:offset + 64].split(b"\0", 1)[0].decode()
                result[symbol] = f"0x{crc & 0xffffffff:08x}"
            return result
    raise ValueError("Module has no __versions; check CONFIG_MODVERSIONS")
