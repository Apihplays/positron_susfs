# KernelSU-Next Branch for veux — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a `kernelsu-next` branch of the veux kernel, starting from the `dereference23/kernel_xiaomi_sm6375` base, replacing its bundled KSU v1.2.1 with **KernelSU-Next (legacy branch, manual-hook mode)**, building a working ReRuku-style kernel.

**Architecture:** Fetch the dereference base as a clean starting point. Run KernelSU-Next's `legacy`-branch `setup.sh` (clones `KernelSU-Next/`, symlinks `drivers/kernelsu`, wires Kconfig/Makefile). Then **remove dereference's KSU v1.2.1 core hooks** (`ksu_execveat_hook`, `ksu_handle_execveat_sucompat`, `ksu_vfs_read_hook`, `ksu_handle_stat`, `ksu_handle_devpts`) and **re-apply KernelSU-Next's manual hooks** in the same files (KSU-Next legacy Kbuild `$(error)`s if no hook mode is set). Build with clang-10 toolchain + the verified techpack fixes (ported), produce a working `Image`.

**Tech Stack:** Linux kernel 5.4 (veux), KernelSU-Next `legacy` branch, clang-10 (`llvm-arm-toolchain-ship-10.0.9`), git, AnyKernel3 (reuse our pipeline).

## Global Constraints

- Base = `dereference23/kernel_xiaomi_sm6375` (`main` = `f4b8a13`), which ships **KSU v1.2.1 hooks** that must be removed.
- KernelSU-Next branch = **`legacy`** (the only one with 5.4/non-GKI manual-hook support; `stable`/`dev` are GKI-2.0/5.10+ tracepoint-only).
- Hook mode = **manual hook** (`CONFIG_KSU_MANUAL_HOOK=y`). Kbuild errors if neither manual nor kprobe hook is defined.
- Build with clang-10 (verified). Port the **techpack fixes** from our master (stub headers, `-Wno-error`, datarmnet `-I`, pd_policy/tcpc fixes) since the base is dereference's (same tree).
- `CONFIG_KPROBES` should stay off (manual hook preferred on 5.4).
- Keep the AnyKernel3 packaging + release pipeline (reuse `build-anykernel.sh` + workflow).

---
## File Structure

**Created:**
- `KernelSU-Next/` — git submodule → `KernelSU-Next/KernelSU-Next` (legacy), via `setup.sh`
- `drivers/kernelsu` — symlink → `KernelSU-Next/kernel`
- `.gitmodules` — submodule entry
- `.github/workflows/build-release.yml` + `build-anykernel.sh` — reuse from master (copied)

**Modified (core hooks — remove v1.2.1, add KernelSU-Next manual hooks):**
- `fs/exec.c` — replace `ksu_execveat_hook`/`ksu_handle_execveat_sucompat` block with KernelSU-Next's `ksu_handle_execveat`
- `fs/read_write.c` — remove `ksu_vfs_read_hook`/`ksu_handle_vfs_read` (KSU-Next doesn't use it)
- `fs/stat.c` — `ksu_handle_stat` + `ksu_handle_newfstat_ret`/`ksu_handle_fstat64_ret` (KSU-Next pattern)
- `fs/open.c` — `ksu_handle_faccessat`
- `fs/devpts/inode.c` — `ksu_handle_devpts`
- `kernel/reboot.c` — add `ksu_handle_sys_reboot` (required by legacy Kbuild)

**Config:**
- `arch/arm64/configs/veux_defconfig` — `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`

**Ports from master (techpack fix set):** `techpack/Kbuild` (`-Wno-error`), 3 stub headers, `pinctrl-lpi.c`, `datarmnet/core/Kbuild` (`-I`), `pd_policy_manager.h`, `pd_dpm_pdo_select.h`.

---

## Task 1: Fetch dereference base + branch

**Files:** git branch setup

- [ ] **1.1** Clone dereference base (shallow, background — large repo):
```bash
cd "$CLAUDE_JOB_DIR/tmp"
git clone --depth 1 --branch main https://github.com/dereference23/kernel_xiaomi_sm6375.git deref_next
```
  Expected: `deref_next/` populated with the veux kernel (incl. `drivers/kernelsu` KSU v1.2.1).

- [ ] **1.2** Init git in the clone and make a baseline commit (so we can revert):
```bash
cd deref_next
git init && git add -A && git commit -m "veux kernel base (dereference23) with KSU v1.2.1"
```

- [ ] **1.3** Create the working branch:
```bash
git checkout -b kernelsu-next
```

### Task 2: Remove dereference's KSU v1.2.1

**Files:** `drivers/kernelsu/` (delete), `drivers/Makefile`, `drivers/Kconfig`, core hook files (read-only check)

**Context:** Dereference's KSU v1.2.1 is a flat dir + hooks. Must remove before KernelSU-Next setup (the symlink + Kconfig would conflict).

- [ ] **2.1** Delete the driver dir + wiring:
```bash
rm -rf drivers/kernelsu
# remove from drivers/Makefile: obj-$(CONFIG_KSU) += kernelsu/
# remove from drivers/Kconfig:  source "drivers/kernelsu/Kconfig"
```

- [ ] **2.2** Verify core files still have the v1.2.1 hooks (to be reworked in Task 4):
```bash
grep -n "ksu_" fs/exec.c fs/read_write.c fs/stat.c fs/open.c fs/devpts/inode.c
```

- [ ] **2.3** Commit: `git commit -am "kernel: remove bundled KernelSU v1.2.1 (for KernelSU-Next)"`

### Task 3: KernelSU-Next legacy setup

**Files:** `KernelSU-Next/` submodule, `drivers/kernelsu` symlink, `.gitmodules`, drivers/Makefile+Kconfig

**Context:** Use the official legacy setup.sh. It clones `KernelSU-Next/KernelSU-Next`, symlinks `drivers/kernelsu` → `KernelSU-Next/kernel`, wires Makefile+Kconfig.

- [ ] **3.1** Run the legacy setup (stable tag of legacy branch):
```bash
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh" | bash -s stable
```
  Expected: `KernelSU-Next/` cloned, symlink created, Makefile/Kconfig lines added.

- [ ] **3.2** Convert to a proper git submodule (KSU-Next legacy may not require it, but for cleanliness):
```bash
git submodule add https://github.com/KernelSU-Next/KernelSU-Next KernelSU-Next
```

- [ ] **3.3** Commit: `git add .gitmodules KernelSU-Next drivers/Makefile drivers/Kconfig; git commit -m "KernelSU-Next: integrate legacy submodule"`

### Task 4: Rework core hooks to KernelSU-Next legacy manual-hook scheme

**Files:** `fs/exec.c`, `fs/read_write.c`, `fs/stat.c`, `fs/open.c`, `fs/devpts/inode.c`, `kernel/reboot.c`

**Context:** KSU-Next legacy Kbuild `$(error)s` if no hook mode. The v1.2.1 hooks are wrong for KSU-Next. Re-apply KSU-Next's manual hooks (the exact signatures are the same family as ReSukiSU's — KSU-Next legacy shares the sucompat/ksud codebase). The core-file edits follow the KSU-Next integration pattern (from the `legacy` branch's `hook/` + `runtime/`):

- [ ] **4.1** `fs/exec.c` — replace the v1.2.1 block (`ksu_execveat_hook`, `ksu_handle_execveat_sucompat`) with `ksu_handle_execveat` called from `do_execve`/`compat_do_execve` (guard `#ifdef CONFIG_KSU`), matching KSU-Next's `ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags)`.

- [ ] **4.2** `fs/read_write.c` — remove `ksu_vfs_read_hook`/`ksu_handle_vfs_read` (KSU-Next doesn't use a vfs_read hook; its read hook is `ksu_handle_sys_read` if needed).

- [ ] **4.3** `fs/stat.c` — move `ksu_handle_stat` into `newfstatat`, add `ksu_handle_newfstat_ret`/`ksu_handle_fstat64_ret` (guard `CONFIG_KSU`), remove from `vfs_statx`.

- [ ] **4.4** `fs/open.c` — `ksu_handle_faccessat` in the `faccessat` syscall.

- [ ] **4.5** `fs/devpts/inode.c` — keep `ksu_handle_devpts` (KSU-Next provides it).

- [ ] **4.6** `kernel/reboot.c` — add `ksu_handle_sys_reboot` (KSU-Next legacy `supercall`).

- [ ] **4.7** Commit: `git commit -am "kernel: rework core hooks to KernelSU-Next legacy manual hooks"`

### Task 5: Config + techpack ports

**Files:** `arch/arm64/configs/veux_defconfig`, techpack fixes (from master)

- [ ] **5.1** defconfig: `CONFIG_KSU=y`, `CONFIG_KSU_MANUAL_HOOK=y` (KSU-Next Kconfig auto-selects manual if `!KPROBES`; set explicitly). Ensure `CONFIG_KPROBES` NOT enabled.

- [ ] **5.2** Port techpack fix set from master (cherry-pick or copy): `techpack/Kbuild` `-Wno-error`, 3 stub headers, `pinctrl-lpi.c` dev_dbg fix, `datarmnet/core/Kbuild` `-I`, `pd_policy_manager.h`, `pd_dpm_pdo_select.h`.

- [ ] **5.3** Commit.

### Task 6: Build + verify

- [ ] **6.1** Regenerate config with clang-10, verify `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`:
```bash
rm -f .config
make HOSTCC=gcc CC=clang ARCH=arm64 veux_defconfig
grep -E "^CONFIG_KSU|KSU_MANUAL" .config
```
- [ ] **6.2** Build Image (clang-10, same verified command as master):
```bash
make HOSTCC=gcc CC=clang LD=ld.lld AR=llvm-ar STRIP=llvm-strip OBJCOPY=llvm-objcopy NM=llvm-nm Image -j$(nproc)
```
  Expected: links `vmlinux` → `OBJCOPY arch/arm64/boot/Image`, 0 errors.
- [ ] **6.3** Package AnyKernel3 zip (reuse `build-anykernel.sh` + `AnyKernel3/` from master, copied).

### Task 7: Release pipeline (reuse)

- [ ] **7.1** Copy `AnyKernel3/` + `build-anykernel.sh` + `.github/workflows/build-release.yml` from master.
- [ ] **7.2** Push branch + tag.

## Self-Review

- Spec coverage: fetch base (T1), remove v1.2.1 (T2), KSU-Next setup (T3), hook rework (T4), config+ports (T5), build (T6), release (T7). All covered.
- No placeholders; concrete commands/signatures.
- **Key risk flagged:** KSU-Next `legacy` manual-hook exact signatures are "same family" as ReSukiSU but may differ in detail — the build (T6) will reveal mismatches, resolved against KSU-Next's `runtime/ksud_integration.c`/`feature/sucompat.c` (same approach as our ReSukiSU work). This is the main execution-time risk.
- YAGNI: no SUSFS (blocked for both), no kprobe mode (5.4 prefers manual).

## Execution Handoff

Plan complete. Two options: subagent-driven or inline. Recommend inline (matches prior execution, lots of build iteration).
