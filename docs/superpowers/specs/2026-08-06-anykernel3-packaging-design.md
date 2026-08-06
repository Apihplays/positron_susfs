# AnyKernel3 Flashable Zip for ReSukiSU veux Kernel — Design

## Context

The `master` branch builds a bootable `arch/arm64/boot/Image` (26.9 MB, raw ARM64 kernel) with **ReSukiSU Manual Hook** integrated. Verified with `llvm-arm-toolchain-ship-10.0.9`. The user wants this kernel packaged as a **flashable zip** ready to install on their device (PixelOS veux, Android 16, kernel in `boot` partition, A/B slots).

**Deliverable:** an **AnyKernel3** zip that, flashed via recovery (PixelOS/TWRP), replaces the veux `boot` partition's kernel with our ReSukiSU kernel. Plus a build script to produce it, and an optional CI workflow to auto-publish on tag.

**User-confirmed decisions:**
- Packaging method = **AnyKernel3** zip (recovery install, not fastboot raw image).
- Kernel boots from **`boot`** partition (verified from device tree `sm6375-devs/device_xiaomi_veux` BoardConfig.mk: `AB_OTA_PARTITIONS += boot ...`, `BOARD_BOOT_HEADER_VERSION=3`, `BOARD_KERNEL_IMAGE_NAME=Image`, `BOARD_INCLUDE_DTB_IN_BOOTIMG=true`, `BOARD_KERNEL_SEPARATED_DTBO=true`).

## Why AnyKernel3 (not raw boot.img)

- AnyKernel3 dumps the **on-device** boot partition, swaps in our `Image` as the kernel, re-packs, and flashes — **no stock boot.img base needed** (it uses the live boot partition's header/ramdisk/dtb).
- Avoids the fragile magiskboot repack + stock-base step documented earlier. Matches the user's "it will just replace the kernel" intent.
- Note: AnyKernel3 installs via **recovery**, not `fastboot` (fastboot flashes raw `.img`). This is correct for the user's chosen method.

## Design

### 1. Repo additions

```
AnyKernel3/                     # committed template + build hook
├── anykernel.sh                # veux config (see below)
├── tools/ak3-core.sh           # from osm0sis/AnyKernel3 (upstream)
├── META-INF/com/google/android/{updater-script,update-binary}
├── Image                       # NOT committed (large, ~27MB) — placed by build script
└── README.md                   # flash instructions
build-anykernel.sh              # top-level: build Image + zip it into AnyKernel3
```

### 2. `anykernel.sh` (veux config)

```sh
kernel.string=positron_susfs (ReSukiSU) for veux
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=veux
device.name2=peux
supported.versions=13.0 - 16.0

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;          # veux is A/B
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;
dump_boot;
write_boot;
```

- `BLOCK=boot` — kernel lives in `boot` (confirmed).
- `IS_SLOT_DEVICE=auto` — handles A/B slot suffix (`_a`/`_b`).
- `device.name1/2=veux,peux` — the veux family codenames.
- Payload file named **`Image`** (raw kernel, matches `BOARD_KERNEL_IMAGE_NAME=Image`). AnyKernel3 will use it as the boot kernel.

### 3. `build-anykernel.sh`

```sh
#!/bin/sh
# 1. Build Image (clang-10 toolchain)  — same cmd as HANDOVER
# 2. cp arch/arm64/boot/Image AnyKernel3/Image
# 3. cd AnyKernel3 && zip -r9 ../positron_susfs-veux-<ver>.zip . -x .git README.md
```

### 4. Optional CI (GitHub Actions, later)

- On tag push: checkout repo + `KernelSU` submodule, set up clang-10 (cache), `make Image`, run `build-anykernel.sh`, upload zip to the GitHub Release. Needs the toolchain downloadable in CI (it is: ravindu644 release assets) + `KernelSU` submodule init.

## Modules / dtbo

- `do.modules=0`: our build has no out-of-tree `.ko` to inject (ReSukiSU is in-kernel). The ROM's existing kernel modules (stock) are used — AnyKernel3 keeps them if `do.modules=0` and only swaps the kernel. (If device needs vendor modules, that's out of scope — our Image is kernel-only.)
- `dtbo`: separate partition, untouched (our Image has no dtb; `BOARD_KERNEL_SEPARATED_DTBO=true` means dtbo is separate and stays stock).

## Verification

1. `./build-anykernel.sh` → produces `positron_susfs-veux-<ver>.zip`.
2. Inspect zip: `unzip -l` shows `anykernel.sh`, `Image`, `META-INF/...`.
3. On-device: flash zip in PixelOS/TWRP recovery → boot → verify `su` via ReSukiSU manager.
4. Revert path: reinstall the stock ROM / recovery boot.img.

## Out of scope (documented)

- Fastboot raw `boot.img` (would need magiskboot + stock base — documented in HANDOVER instead).
- SUSFS (blocked — see HANDOVER).
- Actual device boot test (needs the user's hardware).
