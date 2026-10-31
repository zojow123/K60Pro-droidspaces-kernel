### AnyKernel3: socrates HyperOS 3.0 Droidspaces kernel
properties() { '
kernel.string=socrates 5.15.194 Droidspaces (HyperOS 3.0 / Android 16)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=socrates
supported.versions=16
supported.patchlevels=
supported.vendorpatchlevels=
'; }
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=0;
. tools/ak3-core.sh;
# SukiSU LKM 与 ramdisk 在 init_boot，本 ZIP 不触碰
split_boot;
flash_boot;