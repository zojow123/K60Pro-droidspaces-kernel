"""Compare a built Module.symvers against the phone's actual module imports.

This checks imported symbol CRCs. It does not certify runtime driver behavior.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("symvers", type=Path)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    exported = {}
    for line in args.symvers.read_text().splitlines():
        fields = line.split()
        if len(fields) >= 3:
            exported[fields[1]] = (fields[0].lower(), fields[2])
    inventory = json.loads(args.inventory.read_text())
    imports = inventory["modules"]
    kernel_exports = set(inventory["kernel_exports"])
    vendor_exports = set(inventory["vendor_exports"])
    failures, matched, external, unresolved = [], set(), set(), set()
    for module, symbols in imports.items():
        for symbol, expected in symbols.items():
            entry = exported.get(symbol)
            if entry is None:
                if symbol in kernel_exports:
                    failures.append({"module": module, "symbol": symbol,
                                     "device_crc": expected, "built_crc": "MISSING"})
                elif symbol in vendor_exports:
                    external.add(symbol)
                else:
                    unresolved.add(symbol)
            elif entry[0] != expected.lower():
                failures.append({"module": module, "symbol": symbol,
                                 "device_crc": expected, "built_crc": entry[0]})
            else:
                matched.add(symbol)
    report = {"modules": len(imports), "matched_symbols": len(matched),
              "crc_mismatches": failures,
              "not_in_kernel_symvers": sorted(external),
              "unclassified_missing_imports": sorted(unresolved),
              "scope": "Imported symbol CRCs; external exports classified using device kallsyms."}
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(matched)} matching import CRCs; {len(failures)} mismatches; "
          f"{len(external)} imports outside this build")
    if failures or unresolved or not matched:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
