#!/system/bin/sh
# 在 Redmi K60 Pro (socrates) 上以 root 运行，采集构建所需证据。
# 只读操作：不写任何分区，只在 /sdcard 下生成一个目录。
#
# 用法（二选一）：
#   su -c 'sh /sdcard/Download/Operit工作区/项目/K60Pro-droidspaces-kernel/scripts/capture-device.sh'
#   或在 Termux 里： su -c sh capture-device.sh
set -e

OUT=/sdcard/Download/ds-capture
SLOT=$(getprop ro.boot.slot_suffix)

echo "== device: $(getprop ro.product.device)   slot: $SLOT"
[ "$(getprop ro.product.device)" = "socrates" ] || echo "!! 警告：设备代号不是 socrates"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== 1/6 config.gz"
cat /proc/config.gz > "$OUT/config.gz"

echo "== 2/6 kallsyms"
cat /proc/kallsyms > "$OUT/kallsyms.txt"

echo "== 3/6 modules"
cat /proc/modules > "$OUT/modules.txt"

echo "== 4/6 props"
{
  echo "kernel_release=$(uname -r)"
  echo "device=$(getprop ro.product.device)"
  echo "model=$(getprop ro.product.model)"
  echo "build_release=$(getprop ro.build.version.release)"
  echo "build_id=$(getprop ro.build.id)"
  echo "security_patch=$(getprop ro.build.version.security_patch)"
  echo "rom_version=$(getprop ro.mi.os.version.name)"
  echo "selinux=$(getenforce)"
  echo "slot=$SLOT"
  echo "boot_size=$(blockdev --getsize64 /dev/block/by-name/boot$SLOT)"
  echo "init_boot_size=$(blockdev --getsize64 /dev/block/by-name/init_boot$SLOT 2>/dev/null || echo 0)"
  echo "vendor_dlkm_size=$(blockdev --getsize64 /dev/block/by-name/vendor_dlkm$SLOT 2>/dev/null || echo 0)"
} > "$OUT/device.txt"

echo "== 5/6 vendor modules tar"
tar -cf "$OUT/vendor-modules.tar" -C /vendor_dlkm/lib/modules . 2>/dev/null || \
  tar -cf "$OUT/vendor-modules.tar" -C /vendor/lib/modules .
echo "   ko count: $(tar -tf "$OUT/vendor-modules.tar" | grep -c '\.ko$' || true)"

echo "== 6/6 vendor_boot / dtbo 结构快照（不备份整分区）"
{
  echo "--- /proc/cmdline"
  cat /proc/cmdline
  echo "--- mounts of interest"
  mount | grep -E 'vendor_dlkm|/vendor |/odm' || true
} > "$OUT/extra.txt"

chmod -R 755 "$OUT" 2>/dev/null || true
ls -la "$OUT"
echo
echo "== 完成。请把整个 $OUT 目录取回（或压缩后传回）"
echo "   tar -czf /sdcard/Download/ds-capture.tgz -C /sdcard/Download ds-capture"