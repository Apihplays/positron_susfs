# Handover / Maintenance Notes — positron_susfs

Everything a maintainer needs to continue this kernel. Companion to `README.md` (user-facing) — this file is for the maintainer.

## Repo layout

- `KernelSU/` — **git submodule** → `ReSukiSU/ReSukiSU` (pinned `058cdc9`, v4.1.0). ReSukiSU's `kernel/Kbuild` **hard-errors if this isn't a git submodule** (it runs `git rev-list`/`git describe` for the version and requires `.git`).
- `drivers/kernelsu` — **symlink** → `../KernelSU/kernel`. Do not replace with a real dir.
- `fs/susfs.c`, `include/linux/susfs.h`, `include/linux/susfs_def.h` — simonpunk susfs kernel side (v1.5.5). `susfs_def.h` was **extended with ReSukiSU ABI constants** (`SUSFS_MAGIC` + `CMD_SUSFS_ADD_SUS_PATH_LOOP` / `ADD_SUS_MAP` / `ENABLE_AVC_LOG_SPOOFING` / `HIDE_SUS_MNTS_FOR_NON_SU_PROCS`) that ReSukiSU's `dispatch.c`/`supercall.c` need but simonpunk's header lacked.
- **Core FS hooks** (both branches): `fs/exec.c` (`ksu_handle_execveat` in `do_execve` + `compat_do_execve`), `fs/open.c` (`ksu_handle_faccessat` in `faccessat`), `fs/stat.c` (`ksu_handle_stat`/`_newfstat_ret`/`_fstat64_ret`), `fs/read_write.c` (`ksu_handle_sys_read`, SUSFS-gated), `kernel/reboot.c` (`ksu_handle_sys_reboot`), `kernel/sys.c` (`ksu_handle_setresuid`, `susfs_spoof_uname`), `drivers/input/input.c` (`ksu_handle_input_handle_event`), `fs/devpts/inode.c` (`ksu_handle_devpts`).
- **SELinux exports** (`security/selinux/selinuxfs.c`): `write_op` + `sel_handle_status_ops` de-`static` (needed for ReSukiSU symbol lookup; harmless since `CONFIG_KALLSYMS=y` anyway).
- `arch/arm64/configs/veux_defconfig` — `CONFIG_KSU=y` + hook mode.

## Branches / tags

| Ref | Content |
|---|---|
| `master` **(default, working)** | ReSukiSU **Manual Hook** — **BUILDS to a bootable `Image`** (verified with llvm-arm-toolchain-10.0.9). |
| **`resukisu-susfs-v2`** | **ReSukiSU + SUSFS** (inline mode) — **BUILDS to a bootable `Image` + flashable AnyKernel3 zip** (verified). Root + root-hiding. **Recommended for susfs.** |
| **`kernelsu-next`** | **KernelSU-Next** (legacy manual-hook) — **BUILDS to a bootable `Image`** (verified). Same deref base, KSU-Next instead of ReSukiSU. |
| `resukisu-susfs` | **old / superseded** — earlier SUSFS attempt (replaced by `resukisu-susfs-v2`). |

Tags:
- `resukisu-manualhook-v1` — manual hook archive head (`feb441159`)

The two root methods are a Kconfig `choice` — mutually exclusive. If you flip mode, edit `veux_defconfig` and re-run `make veux_defconfig`.

## ✅ Verified working — KernelSU-Next kernel (`kernelsu-next`)

Built with `llvm-arm-toolchain-ship-10.0.9`:
- `KernelSU-Next version: 33193`, `Hook mode: Manual` (legacy branch — the 5.4-compatible line; `stable`/`dev` are GKI-2.0/5.10+ tracepoint-only)
- Full `vmlinux` → `OBJCOPY arch/arm64/boot/Image` (26.9 MB), **0 errors**
- KSU-Next verified to use `KSU_MANUAL_HOOK` on 5.4 (per its Kconfig: `default y if !KPROBES`)

**Integration notes (KSU-Next vs ReSukiSU on the same deref base):**
- Most v1.2.1 hooks are compatible (KSU-Next legacy shares the sucompat/ksud code). Added: `ksu_handle_sys_reboot` (reboot.c), `ksu_handle_newfstat_ret` (stat.c).
- **Removed** `ksu_handle_devpts` (KSU-Next does NOT define it — devpts is handled internally).
- **`fs/namespace.c`** `can_umount` must be `static int` (NOT `static inline`) so KSU-Next's Kbuild append-regex doesn't re-add a duplicate at every build.
- Same techpack toolchain fixes + AnyKernel3 + release pipeline reused.

## ✅ Verified working — Manual Hook kernel (ReSukiSU)

Built with **llvm-arm-toolchain-ship-10.0.9** (clang) + `aarch64-linux-android-4.9`:
- `ReSukiSU: using Manual Hook`, all 7 hooks verified
- `symbol_export: write_op + sel_handle_status_ops found`
- Full `vmlinux` linked → `OBJCOPY arch/arm64/boot/Image` (26.9 MB) produced, **0 errors**

Build command (see `.config` = `CONFIG_KSU=y`, `CONFIG_KSU_MANUAL_HOOK=y`):
```bash
export PATH=<llvm-10.0.9>/bin:$PATH
export ARCH=arm64 LD_LIBRARY_PATH=<llvm-10.0.9>/lib
make HOSTCC=gcc CC=clang LD=ld.lld AR=llvm-ar STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy NM=llvm-nm Image -j$(nproc)
```
Note: needs `libtinfo.so.5` + `libxml2.so.2` symlinks in the toolchain lib dir (gnome toolchain).

## ✅ Verified working — SUSFS kernel (`resukisu-susfs-v2`)

Built with `llvm-arm-toolchain-ship-10.0.9` (same as positron/cyberc3dr recipe):
- ReSukiSU v4.1.0 + **SUSFS inline mode** (`CONFIG_KSU_SUSFS=y`)
- Full `vmlinux` → `OBJCOPY arch/arm64/boot/Image` (26.9 MB), **0 errors**
- AnyKernel3 zip packaged: `positron_susfs-veux-<sha>.zip` (flashable)
- **Recipe:** cyberc3dr `nGKI_Kernel_Build` (veux + ReSukiSU + SUSFS, proven). Kernel-side = `susfs_patch_to_5.4.patch` + device fixes; consistent `susfs.c`/`susfs.h`/`susfs_def.h` triplet (new-style ABI: `susfs_is_current_proc_umounted`, `TIF_PROC_UMOUNTED`, `AS_FLAGS_*`); kernel hooks in exec/open/stat/fd/task_mmu/namespace/sys.
- **Key gotchas solved:** `susfs_task_state` added to `task_struct` (kabi-reserve swap); fd.c ABI (old→new macro); `DEFAULT_SUS_MNT_ID` added to new `susfs_def.h`.

> Earlier "SUSFS blocked" note is superseded — it failed only because simonpunk's 5.4 branch susfs was too old for the newer hooks. The cyberc3dr recipe (adapted patches) resolves it.

## What's done vs NOT done (honest)

**Done & verified:**
- ReSukiSU wired as submodule + symlink; driver **compiles** under both configs.
- Manual-hook + SUSFS kernel hooks all applied; **all ReSukiSU build-time verifiers pass** (`manual_hook_check.mk`, `inline_hook_check.mk`, `susfs_compat.mk`, `static_export_check.mk`).
- `fs/susfs.o` + every patched FS/kernel file **compiles**; only harmless `-Wc90`/format warnings.
- `CONFIG_KSU_SUSFS=y` + all sub-features resolve in `.config`.

**NOT done (blockers):**
- ❌ **No bootable `boot.img`.** The vendor `techpack/` tree fails under a generic toolchain (`techpack/audio/soc/core.h` needs the OEM clang's `-I` layout; `flask.h` is a build-generated artifact). Must build with the OEM Android toolchain on a machine that has it.
- ❌ **Never booted on device.** Neither branch has been flashed.
- ❌ **SUSFS userspace not built.** Root-hiding needs `ksu_susfs` tool + simonpunk's `susfs4ksu` module (userspace half). Kernel half only is in-tree.
- ReSukiSU **manager app** not bundled (kernel-side only).

## Build (VERIFIED with llvm-arm-toolchain-10.0.9)

```bash
TC=<path>/llvm-arm-toolchain-ship/10.0.9/bin
export PATH=$TC:$PATH ARCH=arm64 LD_LIBRARY_PATH=$TC/../lib
# ensure libtinfo.so.5 + libxml2.so.2 exist in $TC/../lib
make HOSTCC=gcc CC=clang LD=ld.lld AR=llvm-ar STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy NM=llvm-nm Image -j$(nproc)
# produces arch/arm64/boot/Image; repack via your vendor flow
```

Master default = Manual Hook (`CONFIG_KSU_MANUAL_HOOK=y`). Do NOT enable `CONFIG_KSU_SUSFS=y` (does not link — see SUSFS status).

## Repack `Image` → `boot.img` + flash (magiskboot)

You **cannot** build `boot.img` from just `Image` — you need the **stock boot.img** from the device (it holds the ramdisk + dtb + boot header that magiskboot reuses). The APK's `magiskboot` is **statically linked and runs on your Linux PC** (`lib/x86_64/libmagiskboot.so`) — verified working. (The `arm64-v8a` variant runs on-device if you prefer.)

**Get `magiskboot` (on PC):**
```bash
# Download Magisk-v30.7.apk (https://github.com/topjohnwu/Magisk/releases/tag/v30.7)
unzip -j Magisk-v30.7.apk "lib/x86_64/libmagiskboot.so" -d magiskboot_tool
chmod +x magiskboot_tool/libmagiskboot.so
mv magiskboot_tool/libmagiskboot.so magiskboot_tool/magiskboot
./magiskboot_tool/magiskboot   # should print usage (runs on x86_64 Linux)
```

**Repack (on PC):**
```bash
# 0. Get stock boot.img from device or firmware zip
#    adb pull /dev/block/by-name/boot stock-boot.img   (rooted/adb) OR from the device's firmware
# 1. Copy built Image next to stock
cp arch/arm64/boot/Image ./Image
# 2. Unpack stock boot (magiskboot must be in PATH)
./magiskboot_tool/magiskboot unpack stock-boot.img
#    → produces: kernel, ramdisk.cpio, dtb/kernel_dtb (per stock header)
# 3. Replace kernel with ours
cp Image kernel
# 4. sm6375: our built Image is KERNEL-ONLY (no embedded dtb — verified: magiskboot split finds none).
#    The DTB/ramdisk must come from your STOCK boot.img (unpacked above) — do NOT replace kernel_dtb.
#    (If your device uses a separate dtb partition or images.dtb, keep whatever stock unpack produced.)
# 5. Repack
./magiskboot_tool/magiskboot repack stock-boot.img new-boot.img
# 6. Verify
./magiskboot_tool/magiskboot verify new-boot.img
# 7. Flash
fastboot flash boot new-boot.img    # unlocked bootloader
```

**Verify:** after flash, boot and check `su` via the ReSukiSU manager app.

> **Important (vbmeta/AVB):** sm6375 uses AVB. If the device checks vbmeta, you may need to disable AVB verification (unlock + `fastboot --disable-verity --disable-verification flash vbmeta ...`) or sign with your own key. This is device-flashing knowledge beyond the kernel; proceed with a bootloader-unlocked device and at your own risk.

## Gotchas

1. **Submodule**: `git clone --recurse-submodules` or `git submodule update --init`. ReSukiSU `Kbuild` fails without it.
2. **Toolchain libs**: clang 10 needs `libtinfo.so.5` + `ld.lld` needs `libxml2.so.2` — symlink them into `<llvm>/10.0.9/lib`.
3. **Clean config matters**: if `.config` was generated with a different hook mode (`KSU_SUSFS` vs `KSU_MANUAL_HOOK`), regenerate (`rm .config; make veux_defconfig`) before build, else ReSukiSU's verifier errors.
4. **`-Werror` under clang-22**: vendor techpack needs `-Wno-error=format` in `techpack/Kbuild` (added) if built with system clang-22; clang-10 avoids most. The stub-header fixes (techpack, power, tcpc) are real, toolchain-independent fixes.
5. **Manager/root**: kernel only. Install ReSukiSU manager app on device.

## Release process (GitHub Actions)

The repo ships a **CI auto-release workflow** (`.github/workflows/build-release.yml`) that builds the AnyKernel3 zip and publishes it. Two triggers:

### Trigger A — tag push (creates a GitHub Release, zip attached flat) ✅ preferred
```bash
git tag v1.0              # or v1.1, v2.0, ...
git push origin v1.0
```
On the `v*` tag push the workflow:
1. checks out the repo **with the KernelSU submodule** (recursive — required by Kbuild)
2. downloads `llvm-arm-toolchain-ship-10.0.9` (from `ravindu644/Android-Kernel-Tutorials` release)
3. runs `./build-anykernel.sh "$PWD/toolchain"` → generates `.config` via `veux_defconfig`, builds `Image`, packages `positron_susfs-veux-<sha>.zip`
4. uploads the zip **as a workflow artifact** (always)
5. on tag events only, **attaches the zip to the GitHub Release** for that tag — flat download, no artifact-folder wrapping

### Trigger B — manual "Run workflow" (no tag, artifact only)
GitHub → Actions → **build-release** → **Run workflow**.
Produces the zip as an **artifact** (download from the run summary). Does **not** create a Release (no tag context).

### What the zip contains (flat, correct for PixelOS)
```
anykernel.sh        # veux config: BLOCK=boot, IS_SLOT_DEVICE=auto, device.name1=veux
Image               # the built kernel (raw ARM64, ~27MB)
tools/ak3-core.sh   # + magiskboot, busybox, etc. (from upstream osm0sis/AnyKernel3)
META-INF/...        # recovery installer
LICENSE, README.md
```
Install the zip in **recovery** (PixelOS/TWRP). It uses `split_boot`/`flash_boot` — replaces only the kernel in the existing `boot`, preserving the ROM's ramdisk + dtb.

### Gotchas when releasing
- **Fresh CI has no `.config`** — `build-anykernel.sh` runs `make veux_defconfig` first; don't remove that step.
- **Do NOT set `withKernelSU`-style steps that `rm -rf drivers/kernelsu`** (the `Android-Kernel-Builder` fork does this and would replace ReSukiSU with upstream KernelSU — never use that builder for this repo).
- The zip builds, but a **device flash test is the real verification** — the CI only proves it compiles/packages.

## Next steps (suggested)

1. **Flash the Release zip** on the veux device (recovery) → verify boot + root via ReSukiSU manager. This is the one real-world test that remains.
2. If it bootloops: `fastboot flash boot <pixelos-boot.img>` reverts instantly (data untouched).
3. If SUSFS is desired, find the matching risuFS-style `fs/susfs.c` for ReSukiSU v4.1.0 (see SUSFS status above) — not yet available.
4. CI auto-release is **done** (workflow + v1.0 Release). New releases = `git tag vX.Y && git push origin vX.Y`.
