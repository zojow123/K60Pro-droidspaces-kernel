# K60 Pro · Droidspaces 内核（HyperOS 3.0 / Android 16）

> 为 **Redmi K60 Pro（socrates / 22127RK46C）** 定制的 GKI 内核，开启 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 容器运行所需的内核特性。
>
> **✅ 已实机刷入验证**

---

## 实机验证结果（2026-11-01）

| 项目 | 结果 |
|---|---|
| 内核版本 | `5.15.194-android13-8-00019-gf4321180a397-ab15212794` |
| 与原厂 vermagic | **完全一致**（一字不差）|
| 厂商模块 ABI | **404 个模块，`crc_mismatches: 0`** |
| 刷入后模块加载 | 401 个全部正常，无 `disagrees about version` |
| CFI | 正常工作（`.cfi_jt` 后缀存在，无 type mismatch）|
| `/proc/1/ns` | pid / ipc / user 命名空间全部出现 |
| Droidspaces Check Requirements | **All required features found** |

Check Requirements 明细：**MUST HAVE 10/10 ✅，RECOMMENDED 9/9 ✅**

> 仅 `--cpus`（CPU 限额）和 `--pids-limit`（进程数限额）两项 ✗ —— 这是**刻意留的**：开启 `CFS_BANDWIDTH` / `CGROUP_PIDS` 会让约 4000 个符号的 CRC 变化，破坏与原厂模块的兼容性。用 `cpu.weight`（相对权重）可以替代 `--cpus`。

---

## 启用的内核特性

```
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_SYSVIPC=y
CONFIG_DEVTMPFS=y
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_NETFILTER=y
CONFIG_CGROUPS / CGROUP_V2
CONFIG_BLK_DEV_LOOP=y
CONFIG_EXT4_FS=y
```

完整差异见 `config.diff`（相对设备原厂配置）。

---

## 下载

| 文件 | 说明 |
|---|---|
| **`socrates-hyperos3-5.15.194-droidspaces.zip`** | **推荐** · AnyKernel3 刷机包，直接刷 |
| `Image` | 裸内核镜像（47 MB），用于手动写入 boot 分区 |
| `abi-report.json` | ABI 比对报告（404 模块 / 3063 符号）|
| `config.diff` | 配置差异 |
| `kernel.config` | 完整内核配置（6962 行）|
| `build.json` / `compiler.txt` | 构建环境信息 |
| `SHA256SUMS` | 校验和 |

---

## 刷机

### 前置条件

- Redmi K60 Pro（socrates），**HyperOS 3.0 / Android 16**
- 已解锁 Bootloader + 已 root（SukiSU / KernelSU）
- 备份：`dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.orig.img`

### 方式一：AnyKernel3（推荐）

在 KernelSU / SukiSU Manager 里刷入 `socrates-hyperos3-5.15.194-droidspaces.zip`，重启。

### 方式二：手动写 boot 分区

```bash
# 1. 备份
dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.orig.img

# 2. 检查原 boot.img 结构（K60 Pro 是 header 4096 + kernel，无 ramdisk/dtb）
python3 - <<'EOF'
import struct
h = open('/sdcard/boot_a.orig.img','rb').read(4096)
print('kernel_size =', struct.unpack('<I', h[8:12])[0])
print('ramdisk_size =', struct.unpack('<I', h[12:16])[0])
EOF

# 3. 修改 header 的 kernel_size（偏移 0x08，小端 uint32），拼接新 Image，写回

# 4. 校验后重启
md5sum /dev/block/by-name/boot_a   # 与写入值比对
sync; echo b > /proc/sysrq-trigger
```

> ⚠️ `reboot` 命令在 chroot 里跑不了（Android linker 路径问题），用 sysrq 触发。

### 刷后验证

```bash
uname -r                      # 应显示 5.15.194-android13-8-00019-gf4321180a397-ab15212794
ls /proc/1/ns/                # 应有 pid / ipc / user
lsmod | wc -l                 # 应有 401 个模块
dmesg | grep -i "cfi"         # 不应有 type mismatch
```

### 回滚

```bash
dd if=/sdcard/boot_a.orig.img of=/dev/block/by-name/boot_a
sync; echo b > /proc/sysrq-trigger
```

---

## 构建（可复现）

源码基线：ACK tag `android13-5.15.194_r00`（commit `bce84c40`）

关键点：

1. **vermagic 必须精确复现**：`LOCALVERSION=-android13-8` + `.scmversion` 内容 `-00019-gf4321180a397` + `BUILD_NUMBER=15212794`
2. **`CONFIG_UNUSED_KSYMS_WHITELIST=n`**：原厂配置指向小米构建机的绝对路径（`/mnt/disks/build-disk/.../abi_symbollist.raw`），不改会构建失败
3. **kABI padding**：`task_struct` 尾部 6/7/8 号 reserve 槽全部空闲，用 `scripts/pick_kabi_slot.py` 自动检测
4. **工具链**：clang r563880c（21.0.0），必须支持 Full LTO + CFI
5. **构建环境**：4 核 16 GB（public 仓库免费 runner 约 20 分钟；2 核 7 GB 跑不完）

产物验证会跑 `scripts/check_module_abi.py`，把 404 个厂商模块的 `__versions` 段与构建出的 `Module.symvers` 逐一比对，`crc_mismatches` 为空才允许刷机。

---

## 仓库结构

```
config/device-baseline.config          设备原厂内核配置（6962 行）
evidence/vendor-module-versions.json   404 个厂商模块的 ABI 基线
scripts/pick_kabi_slot.py              自动选 kABI padding 槽
scripts/check_module_abi.py            模块 CRC 比对
scripts/extract-vendor-boot-ko.py      从 vendor_boot 提取 .ko
.github/workflows/build.yml            CI 构建流程
```

---

## 免责声明

刷机有风险，变砖、丢数据、失去保修都是可能的。请先备份 boot 分区并确认机型匹配（**仅限 Redmi K60 Pro / socrates / HyperOS 3.0**，其他机型刷了必炸）。

本项目仅供学习和自用，不对任何损失负责。

---

## 相关

- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) —— Android 上的容器运行时
- [ACK (Android Common Kernel)](https://android.googlesource.com/kernel/common/)
- 社区同类项目：[shark-wan/K60Prosocrates-Kernel-DroidSpaces](https://github.com/shark-wan/K60Prosocrates-Kernel-DroidSpaces)（LineageOS 23.2 版）

---

*构建于 2026-11-01 · 已在 Redmi K60 Pro 实机验证*