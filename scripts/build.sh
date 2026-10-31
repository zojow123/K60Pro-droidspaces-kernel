#!/usr/bin/env bash
# 用设备原厂 .config 作基线构建 Image，并比对 vendor 模块导入符号 CRC。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

readarray -t META < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
k, t = x['kernel'], x['toolchain']
for v in (k['release'], k['localversion'], k['build_number'], t['directory']):
    print(v)
PY
)
RELEASE="${META[0]}"; LOCALVER="${META[1]}"; BUILD_NUM="${META[2]}"; TOOLCHAIN_DIR="${META[3]}"

export PATH="$ROOT/toolchain/$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=socrates KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
# 设备 vermagic 后缀：-android13-8 ... -ab15212794
export LOCALVERSION="$LOCALVER"
export BUILD_NUMBER="$BUILD_NUM"
JOBS="${JOBS:-$(nproc)}"
mkdir -p out dist

cp config/device-baseline.config out/.config

# 把 fragment 同时写进 gki_defconfig（源码树里的官方 defconfig 保持一致）
# 支持 CONFIG_X=y 与 CONFIG_X=n 两种写法
while IFS= read -r entry; do
  if [[ "$entry" =~ ^CONFIG_([A-Z0-9_]+)=y$ ]]; then
    kernel/scripts/config --file kernel/arch/arm64/configs/gki_defconfig --enable "${BASH_REMATCH[1]}"
    kernel/scripts/config --file out/.config --enable "${BASH_REMATCH[1]}"
  elif [[ "$entry" =~ ^CONFIG_([A-Z0-9_]+)=n$ ]]; then
    kernel/scripts/config --file kernel/arch/arm64/configs/gki_defconfig --disable "${BASH_REMATCH[1]}"
    kernel/scripts/config --file out/.config --disable "${BASH_REMATCH[1]}"
  fi
done < config/droidspaces.config

make -C kernel O="$ROOT/out" olddefconfig

kernel/scripts/diffconfig config/device-baseline.config out/.config > dist/config.diff
cp out/.config dist/kernel.config
diff -u --label a/arch/arm64/configs/gki_defconfig --label b/arch/arm64/configs/gki_defconfig \
  .cache/gki_defconfig.original kernel/arch/arm64/configs/gki_defconfig >> dist/source.patch || test "$?" -eq 1

# ---- 配置自检 ----
python3 - <<'PY'
from pathlib import Path
def read(path):
    d = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line.startswith('CONFIG_') and '=' in line:
            k, v = line.split('=', 1)
            d[k] = v
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            d[line[2:-len(' is not set')].strip()] = 'n'
    return d
actual = read('out/.config')
wanted = read('config/droidspaces.config')
missing = [(n, actual.get(n), v) for n, v in wanted.items() if actual.get(n) != v]
assert not missing, f"fragment not applied: {missing}"

baseline = read('config/device-baseline.config')
# 必须与基线保持一致的关键编译/加固选项（变了就说明基线被误改）
for name in ('CONFIG_MODVERSIONS', 'CONFIG_CFI_CLANG', 'CONFIG_LTO_CLANG_FULL',
             'CONFIG_KASAN_HW_TAGS', 'CONFIG_SHADOW_CALL_STACK', 'CONFIG_DEBUG_INFO_BTF',
             'CONFIG_MODULE_SIG_PROTECT', 'CONFIG_MODULE_SIG'):
    assert actual.get(name) == baseline.get(name) == 'y', (name, actual.get(name), baseline.get(name))
# 刻意不动的两项（改了就破坏 kABI）
for name in ('CONFIG_CFS_BANDWIDTH', 'CONFIG_CGROUP_PIDS'):
    assert actual.get(name) == baseline.get(name), (name, actual.get(name), baseline.get(name))
# 与 Droidspaces 检查项直接相关的必须项
for name in ('CONFIG_PID_NS', 'CONFIG_IPC_NS', 'CONFIG_SYSVIPC', 'CONFIG_DEVTMPFS',
             'CONFIG_USER_NS', 'CONFIG_POSIX_MQUEUE', 'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE'):
    assert actual.get(name) == 'y', (name, actual.get(name))
print("== config self-check passed")
PY

make -C kernel O="$ROOT/out" -j"$JOBS" Image modules 2>&1 | tee dist/build.log
cp out/arch/arm64/boot/Image dist/Image
cp out/Module.symvers dist/Module.symvers
cp out/include/generated/utsrelease.h dist/

# ---- vermagic 必须与设备完全一致 ----
python3 - <<'PY'
import json
from pathlib import Path
lock = json.load(open('config/sources.lock.json'))
release = Path('dist/utsrelease.h').read_text().split('"')[1]
print(f"== built UTS_RELEASE: {release}")
print(f"== device release   : {lock['kernel']['release']}")
assert release == lock['kernel']['release'], (release, lock['kernel']['release'])
PY

# ---- ABI：与设备 vendor 模块导入符号 CRC 比对 ----
if [[ -f evidence/vendor-module-versions.json ]]; then
  python3 scripts/check_module_abi.py dist/Module.symvers evidence/vendor-module-versions.json \
    --report dist/abi-report.json
else
  echo "!! evidence/vendor-module-versions.json missing — ABI 未校验，禁止刷机"
fi

python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
lock = json.load(open('config/sources.lock.json'))
files = ['config/device-baseline.config', 'config/droidspaces.config', 'dist/Image']
files += [str(p) for p in Path('patches').glob('*.patch')]
info = {
    'device': lock['device'], 'rom': lock['rom'],
    'kernel_release': Path('dist/utsrelease.h').read_text().split('"')[1],
    'sources': lock,
    'ci_commit': os.environ.get('GITHUB_SHA'),
    'ci_run_id': os.environ.get('GITHUB_RUN_ID'),
    'changes': 'Droidspaces GKI fragment + SYSVIPC kABI padding; device .config as baseline',
    'hashes': {f: hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in files if Path(f).exists()},
    'validation': 'Built Image + imported symbol CRC comparison; device boot not tested',
}
Path('dist/build.json').write_text(json.dumps(info, indent=2) + '\n')
PY