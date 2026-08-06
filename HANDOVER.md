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
| `master` **(default, working)** | ReSukiSU **Manual Hook** — **BUILDS to a bootable `Image`** (verified with llvm-arm-toolchain-10.0.9). CONFIG_Hooks |
| `resukisu-susfs` | **WIP / blocked** — ReSukiSU + SUSFS attempt. See SUSFS status below. |

Tags:
- `resukisu-manualhook-v1` — manual hook archive head (`feb441159`)

The two root methods are a Kconfig `choice` — mutually exclusive. If you flip mode, edit `veux_defconfig` and re-run `make veux_defconfig`.

## ✅ Verified working — Manual Hook kernel

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

## SUSFS — NOT working (blocked)

ReSukiSU's **SUSFS inline** mode calls 12 kernel-side `susfs_*` functions (`susfs_is_current_proc_umounted`, `susfs_set_hide_sus_mnts_for_non_su_procs`, `susfs_start_sdcard_monitor_fn`, `susfs_set_avc_log_spoofing`, `susfs_extra_works`, etc.) that **no published susfs release provides** — verified: simonpunk susfs4ksu (kernel-.4, master), RKSU, MKSU, backslashxx, SukiSU-Ultra. These match a **newer risuFS-style susfs** not settled for ReSukiSU v4.1.0. **Do not use `CONFIG_KSU_SUSFS=y`** — it will not link. Use Manual Hook.

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

## Gotchas

1. **Submodule**: `git clone --recurse-submodules` or `git submodule update --init`. ReSukiSU `Kbuild` fails without it.
2. **Toolchain libs**: clang 10 needs `libtinfo.so.5` + `ld.lld` needs `libxml2.so.2` — symlink them into `<llvm>/10.0.9/lib`.
3. **Clean config matters**: if `.config` was generated with a different hook mode (`KSU_SUSFS` vs `KSU_MANUAL_HOOK`), regenerate (`rm .config; make veux_defconfig`) before build, else ReSukiSU's verifier errors.
4. **`-Werror` under clang-22**: vendor techpack needs `-Wno-error=format` in `techpack/Kbuild` (added) if built with system clang-22; clang-10 avoids most. The stub-header fixes (techpack, power, tcpc) are real, toolchain-independent fixes.
5. **Manager/root**: kernel only. Install ReSukiSU manager app on device.

## Next steps (suggested)

1. Repack `arch/arm64/boot/Image` into `boot.img` (AnyKernel3 / mkbootimg) and flash → verify boot + root.
2. Verify root via ReSukiSU manager, `su`, device boots without issues.
3. If SUSFS is desired, find the matching risuFS-style `fs/susfs.c` for ReSukiSU v4.1.0 (see SUSFS status above) — not yet available.
4. Optionally add GitHub Actions CI (container with clang-10).
