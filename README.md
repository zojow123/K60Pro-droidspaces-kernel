# K60Pro-droidspaces-kernel

为 **Redmi K60 Pro（socrates / 22127RK46C）· HyperOS 3.0.304.0 · Android 16 · 内核 5.15.194-android13-8** 构建带 Droidspaces 支持的 GKI 内核。

不改动 init_boot（SukiSU LKM 保留），只替换当前槽 `boot` 的 Image。

## 设备现状（2026-10-28 实测）

| 项 | 值 |
|---|---|
| 内核 | `5.15.194-android13-8-00019-g4321180a397-ab15212794`，clang r450784e (14.0.7) |
| 内核性质 | 纯 AOSP GKI（common-android13-5.15），驱动全在 vendor_dlkm 的 .ko |
| 缺的必须项 | `PID_NS` `IPC_NS` `USER_NS` `SYSVIPC` `POSIX_MQUEUE` `DEVTMPFS` `NETFILTER_XT_MATCH_ADDRTYPE` |
| 已满足 | `NAMESPACES` `UTS_NS` `NET_NS` `CGROUPS` `CGROUP_SCHED` `SECCOMP` `VETH` `BRIDGE` `NETFILTER` `NF_NAT` `IPTABLES` `MASQUERADE` `MEMCG` `OVERLAY_FS` … |

## 为什么不能刷社区那个 LineageOS 内核

`shark-wan/K60Prosocrates-Kernel-DroidSpaces` 是 **5.15.211 + LineageOS 23.2** 的 boot，与本机 5.15.194 + HyperOS 3.0 的 vendor 模块不匹配，刷了会卡 logo。
本仓库复用了它的**方法论与脚手架**（kABI padding、CRC 比对、AnyKernel3、Actions 流程），但源码基线、config、工具链全部换成本机的。

## 目录

```
config/sources.lock.json      # 源码 commit / 工具链 / 补丁 / AnyKernel3 全部锁定
config/device-baseline.config # 从本机 boot.img 的 IKCONFIG 提取的完整 .config（6962 行）
config/droidspaces.config     # 需要打开的 fragment（18 项）
config/anykernel.sh           # AnyKernel3 打包配置
patches/                      # SYSVIPC kABI padding 三个候选（1-2-3 / 3-4-5 / 6-7-8）
scripts/pick_kabi_slot.py     # 自动检测 task_struct 里哪些 RESERVE 槽空闲
scripts/prepare.sh            # 拉源码+工具链、自动选槽、打补丁、写 .scmversion
scripts/build.sh              # olddefconfig → 自检 → 编 Image → vermagic 校验 → CRC 比对
scripts/package.sh            # 打 AnyKernel3 ZIP
scripts/capture-device.sh     # 【在手机上跑】采集 ABI 基线
scripts/parse-capture.py      # 【在电脑/本机跑】解析采集结果 → evidence/*.json
scripts/check_module_abi.py   # Module.symvers vs 设备模块导入符号 CRC
evidence/                     # ABI 基线（vendor-module-versions.json 约 1.5 MB）
```

## 流程

### 第 1 步：在 K60 Pro 上采集 ABI 基线（必须，否则无法校验）

手机 root 后执行（Operit / Termux 均可）：

```sh
su -c 'sh /sdcard/Download/Operit工作区/项目/K60Pro-droidspaces-kernel/scripts/capture-device.sh'
```

产物在 `/sdcard/Download/ds-capture/`：`config.gz`、`kallsyms.txt`、`modules.txt`、`device.txt`、`vendor-modules.tar`。
只读，不动任何分区。

### 第 2 步：解析成 evidence

把 `ds-capture` 整个目录取回后：

```bash
python3 scripts/parse-capture.py /path/to/ds-capture
```

会重新生成 `config/device-baseline.config`、`evidence/vendor-module-versions.json`、`evidence/device-summary.json`。

### 第 3 步：推到 GitHub 跑 Actions

```bash
git init && git add -A && git commit -m "init: socrates HyperOS droidspaces kernel"
git remote add origin git@github.com:<you>/K60Pro-droidspaces-kernel.git
git push -u origin main
```

然后 Actions → **Build socrates HyperOS Droidspaces kernel** → Run workflow。
约 60–120 分钟（Full LTO 很慢）。产物 `socrates-hyperos-droidspaces-N` 里有：

- `Image` — 原始内核
- `socrates-hyperos3-5.15.194-droidspaces.zip` — AnyKernel3，直接刷
- `abi-report.json` — **必须看这个**
- `kernel.config` / `config.diff` / `source.patch` / `build.json` / `SHA256SUMS`

### 第 4 步：判读 abi-report.json

```json
{"modules": 401, "matched_symbols": 3971, "crc_mismatches": [], ...}
```

- `crc_mismatches` 为空 → 可以刷
- 非空 → **不要刷**，把 mismatches 列表发出来，需要换 padding 槽或换源码基线

### 第 5 步：刷机

**先备份当前 boot**（其实 `项目/K60Pro-mainline/固件/images/boot.img` 已有，但再确认一次）：

```bash
adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.orig.img'
adb pull /sdcard/boot_a.orig.img
```

刷入（KernelSU/SukiSU 环境下用 AnyKernel3 ZIP 最稳）：

```bash
adb reboot sideload        # 或进 recovery / KernelSU 的刷机入口
adb sideload socrates-hyperos3-5.15.194-droidspaces.zip
```

或者 fastboot（确认当前槽是 a 再刷）：

```bash
adb shell getprop ro.boot.slot_suffix     # 先看是 _a 还是 _b
adb reboot bootloader
fastboot flash boot_a Image
fastboot reboot
```

回滚：

```bash
fastboot flash boot_a boot_a.orig.img
```

### 第 6 步：验证

```bash
adb shell uname -r                    # 应为 5.15.194-android13-8-00019-g4321180a397-ab15212794
adb shell su -c 'ls /proc/1/ns'       # 应出现 pid ipc user
adb shell su -c 'zcat /proc/config.gz | grep -E "CONFIG_(PID_NS|IPC_NS|SYSVIPC|DEVTMPFS)="'
adb shell dmesg | grep -iE 'cfi|modversion|module verification'
```

然后装 Droidspaces APK → Settings → Requirements → **Check Requirements**。

## 已知风险

| 风险 | 说明 | 应对 |
|---|---|---|
| `UNUSED_KSYMS_WHITELIST` | 基线里指向小米构建机绝对路径 `/mnt/disks/build-disk/.../abi_symbollist.raw`，不存在 | 已在 fragment 里 `CONFIG_TRIM_UNUSED_KSYMS=n`，导出全部符号（Image 大几 MB） |
| clang 版本 | 设备用 r450784e(14.0.7)，上游已下架；本仓库用 r563880c(21.0.0) | 开机 dmesg 查 `CFI:` 报错；失败则需找 clang 14 工具链 |
| 源码基线 | 设备是 `g4321180a397`，上游 ACK 无此 commit；用 tag `android13-5.15.194_r00` | 靠 CRC 比对兜底；mismatch 非空就不能刷 |
| Full LTO | 全量 LTO 链接吃 16 GB 内存 + 30 GB 磁盘 | Actions 里已挂 swap；本地别试 |
| `CFS_BANDWIDTH` / `CGROUP_PIDS` | 开了会改 struct 大小，约 4000 个导出符号 CRC 变化，无补丁可救 | 保持关闭，`--cpus` / `--pids-limit` 灰掉即可 |
| AVB | boot 内有 vbmeta（偏移 47,599,616，896 字节） | AnyKernel3 用 `PATCH_VBMETA_FLAG=0` 不改；若开机校验失败需关 verity |

## 参考

- Droidspaces 官方内核配置指南：`ravindu644/Droidspaces-OSS` → `Documentation/Kernel-Configuration.md`
- 同 SoC 先例：`shark-wan/K60Prosocrates-Kernel-DroidSpaces`（LineageOS 23.2，已实机验证）
- 本机硬件逆向：`/sdcard/Download/Operit工作区/项目/K60Pro-mainline/`
