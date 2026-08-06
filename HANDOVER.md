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
| `resukisu-susfs` (default) | ReSukiSU + SUSFS inline hook. `CONFIG_KSU_SUSFS=y`. Latest work. |
| `master` | ReSukiSU Manual Hook only. `CONFIG_KSU_MANUAL_HOOK=y`. Stable baseline. |
| `resukisu-susfs-v1` | Tag at SUSFS head (`1bcfbda9`). |
| `resukisu-manualhook-v1` | Tag at manual archive head (`feb44115`). |

The two root methods are a Kconfig `choice` — mutually exclusive. If you flip mode, edit `veux_defconfig` and re-run `make veux_defconfig`.

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

## Build (requires OEM toolchain)

```bash
export ARCH=arm64 CROSS_COMPILE=<oem-toolchain>/aarch64-linux-gnu-
make veux_defconfig      # resukisu-susfs: KSU_SUSFS=y
make Image -j$(nproc)
# then your vendor's boot.img repack
```

## Gotchas

1. **Submodule**: `git clone --recurse-submodules` or `git submodule update --init`. ReSukiSU `Kbuild` fails without it.
2. **`.gitignore`**: already covers `*.o`, `.ko`, `.config`, `/vmlinux`. Build output won't be committed. Re-audit if you add an `out/` dir convention.
3. **Susfs `.rej`**: all 3 patch rejects (dcache/mount.h/sys.c) were hand-applied. If you re-run `50_add_susfs_in_kernel-5.4.patch`, expect those hunks to conflict — resolve manually, don't force.
4. **`SUSFS_MAGIC`** is `0xFAFAFAFA` (C-valid); ReSukiSU userspace uses `0xFAFA_FAFA` — same value, different literal style. Keep them equal.
5. **Manager/root**: kernel only. Install ReSukiSU manager; SUSFS features need the ksu_susfs tool.

## Next steps (suggested)

1. Build with OEM toolchain → confirm `boot.img` + device boots.
2. Verify root via ReSukiSU manager, then susfs hiding via `ksu_susfs`.
3. Optionally add GitHub Actions CI to build on push (needs a toolchain container).
