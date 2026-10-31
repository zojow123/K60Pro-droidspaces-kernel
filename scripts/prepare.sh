#!/usr/bin/env bash
# 拉取锁定源码与工具链、自动选择 kABI padding 槽、应用 SYSVIPC 补丁。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p dist kernel toolchain .cache

readarray -t LOCK < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
k, t = x['kernel'], x['toolchain']
for v in (k['archive_url'], k.get('archive_sha256', ''), k['scmversion'],
          t['archive_url'], t['commit'], t['directory'], t.get('tree', '')):
    print(v)
PY
)
K_URL="${LOCK[0]}"; K_SHA="${LOCK[1]}"; SCMVER="${LOCK[2]}"
T_URL="${LOCK[3]}"; T_COMMIT="${LOCK[4]}"; T_DIR="${LOCK[5]}"; T_TREE="${LOCK[6]}"

# ---------- 1. kernel source ----------
if [[ ! -f kernel/Makefile ]]; then
  echo "== fetching kernel source: $K_URL"
  curl -fL --retry 3 "$K_URL" -o .cache/kernel-source.tar.gz
  if [[ -n "$K_SHA" ]]; then
    printf '%s  %s\n' "$K_SHA" .cache/kernel-source.tar.gz | sha256sum --check
  else
    sha256sum .cache/kernel-source.tar.gz | tee dist/kernel-source.sha256
  fi
  tar -xzf .cache/kernel-source.tar.gz --strip-components=1 -C kernel
  rm .cache/kernel-source.tar.gz
fi
python3 - <<'PY'
import json, re
from pathlib import Path
lock = json.load(open('config/sources.lock.json'))['kernel']
make = Path('kernel/Makefile').read_text()
want = lock['release'].split('-')[0]
got = '.'.join(re.search(rf'^{k} = (\d+)$', make, re.M).group(1)
               for k in ('VERSION', 'PATCHLEVEL', 'SUBLEVEL'))
print(f"== kernel source version: {got} (expect {want})")
assert got == want, (got, want)
PY

# ---------- 2. toolchain ----------
if [[ ! -x "toolchain/${T_DIR}/bin/clang" ]]; then
  echo "== fetching toolchain: ${T_DIR}"
  mkdir -p "toolchain/${T_DIR}"
  curl -fL --retry 3 "$T_URL" -o .cache/clang.tar.gz
  sha256sum .cache/clang.tar.gz > dist/compiler-archive.sha256
  tar -xzf .cache/clang.tar.gz -C "toolchain/${T_DIR}"
  rm .cache/clang.tar.gz
fi
"toolchain/${T_DIR}/bin/clang" --version | tee dist/compiler.txt
python3 - <<'PY'
import json, urllib.request
x = json.load(open('config/sources.lock.json'))['toolchain']
if not x.get('tree'):
    raise SystemExit(0)
url = f"{x['url']}/+/{x['commit']}/{x['directory']}/?format=JSON"
with urllib.request.urlopen(url, timeout=60) as r:
    tree = json.loads(r.read()[4:])['id']
assert tree == x['tree'], (tree, x['tree'])
print("== toolchain tree verified")
PY

# ---------- 3. SYSVIPC kABI padding ----------
cp kernel/include/linux/sched.h .cache/sched.h.original
cp kernel/arch/arm64/configs/gki_defconfig .cache/gki_defconfig.original

SLOT=$(python3 scripts/pick_kabi_slot.py kernel/include/linux/sched.h | tee /dev/stderr | tail -1)
PATCHFILE="patches/0001-sysvipc-kabi-padding-${SLOT}.patch"
echo "== kABI padding slot group: ${SLOT} -> ${PATCHFILE}"
test -f "$PATCHFILE" || { echo "missing $PATCHFILE"; exit 1; }
patch --directory=kernel --strip=1 --batch --fuzz=0 --dry-run < "$PATCHFILE"
patch --directory=kernel --strip=1 --batch --fuzz=0 < "$PATCHFILE"

# 精确复现设备 vermagic：5.15.194 + -android13-8 + -00019-g4321180a397 + -ab15212794
printf '%s\n' "$SCMVER" > kernel/.scmversion

diff -u --label a/include/linux/sched.h --label b/include/linux/sched.h \
  .cache/sched.h.original kernel/include/linux/sched.h > dist/source.patch || test "$?" -eq 1
cp config/sources.lock.json dist/
echo "== scmversion: $(cat kernel/.scmversion)"
df -h .
du -sh kernel toolchain