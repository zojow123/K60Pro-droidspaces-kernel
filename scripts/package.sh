#!/usr/bin/env bash
# 打 AnyKernel3 ZIP（只替换当前槽 boot 内核）
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
readarray -t AK3 < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))['anykernel3']
print(x['url']); print(x['commit'])
PY
)
ZIPNAME="socrates-hyperos3-5.15.194-droidspaces.zip"

rm -rf .cache/anykernel3
mkdir -p .cache/anykernel3
git init -q .cache/anykernel3
git -C .cache/anykernel3 remote add origin "${AK3[0]}"
git -C .cache/anykernel3 fetch -q --depth=1 origin "${AK3[1]}"
git -C .cache/anykernel3 checkout -q --detach FETCH_HEAD
cp dist/Image .cache/anykernel3/Image
cp config/anykernel.sh .cache/anykernel3/anykernel.sh
cp dist/build.json .cache/anykernel3/build.json
cd .cache/anykernel3
zip -r9 "$ROOT/dist/$ZIPNAME" . -x '.git/*' '.github/*' 'README.md'
cd "$ROOT/dist"
sha256sum Image "$ZIPNAME" > SHA256SUMS
ls -la