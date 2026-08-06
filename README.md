# positron_susfs — Custom Kernel for Xiaomi veux (ReSukiSU / KernelSU)

Custom Android kernel for the **Xiaomi veux** device line (Redmi Note 11E / POCO M4 5G / Redmi 11 Prime 5G), Linux **5.4.302**, based on [`dereference23/kernel_xiaomi_sm6375`](https://github.com/dereference23/kernel_xiaomi_sm6375).

Built with [**ReSukiSU**](https://github.com/ReSukiSU/ReSukiSU) root (a KernelSU derivative) integrated in-tree.

> ⚠️ **Status note:** the kernel-side ReSukiSU + SUSFS integration is complete and compiles clean, but a **bootable `boot.img` has not been built or flashed from this repo** — the vendor `techpack/` tree requires your OEM Android toolchain. See [Build](#build) and [HANDOVER.md](./HANDOVER.md).

## Branches

| Branch | Root method | Status |
|---|---|---|
| **`master`** (default) | ReSukiSU **Manual Hook** | ✅ **BUILDS to a bootable `Image`** (verified with llvm-arm-toolchain-10.0.9). Recommended. |
| `resukisu-susfs` | ReSukiSU + SUSFS | ⚠️ **WIP / blocked** — SUSFS kernel-side mismatch prevents linking. See below. |

Both provide ReSukiSU **root + `su`**. `master` is the working, buildable kernel. SUSFS root-hiding is not yet functional.

## What's integrated (`master`)

- **ReSukiSU** as a git submodule at `KernelSU/`, wired via `drivers/kernelsu` symlink.
- **Manual hook** mode (exec/open/stat/reboot hooks), verified by ReSukiSU's build-time checker.
- `veux_defconfig`: `CONFIG_KSU=y` + `CONFIG_KSU_MANUAL_HOOK=y`.

## SUSFS status (blocked)

ReSukiSU's SUSFS-inline mode needs 12 kernel-side `susfs_*` functions that no published susfs release provides (checked simonpunk 5.4/master, RKSU, MKSU, backslashxx, SukiSU-Ultra). Enable `CONFIG_KSU_SUSFS` only if the matching risuFS-style `fs/susfs.c` is found. `master` avoids this — use it.

## Cloning

ReSukiSU's `Kbuild` **hard-requires** the `KernelSU` git submodule. Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:Apihplays/positron_susfs.git
# or, if already cloned without them:
git submodule update --init --recursive
```

Without the submodule the kernel build fails.

## Build

A full `boot.img` requires the **OEM Android toolchain** (the vendor `techpack/` drivers need its `-I` include layout and clang). Using your Qualcomm-style flow:

```bash
export ARCH=arm64 CROSS_COMPILE=<toolchain>/aarch64-linux-gnu-
make veux_defconfig        # KSU on; SUSFS on (resukisu-susfs)
make Image -j$(nproc)
```

- Hook mode is chosen in `veux_defconfig`: `CONFIG_KSU_SUSFS=y` vs `CONFIG_KSU_MANUAL_HOOK=y` — mutually exclusive.
- ReSukiSU's version is derived from the `KernelSU` submodule git (v4.1.0).

## Flash / root

This repo is the *kernel*. Root on-device also needs the **ReSukiSU manager app**, and for SUSFS root-hiding the `ksu_susfs` userspace tool + simonpunk's `susfs4ksu` module (neither built here).

## Credits / License

- Kernel tree: GPL-2.0 (Linux), derived from `dereference23/kernel_xiaomi_sm6375`.
- ReSukiSU: GPL-2.0 / GPL-3.0 (see its repo).
- susfs4ksu (`simonpunk`): GPL.
- Respect each upstream's license.

*Integration track: ReSukiSU v4.1.0 (submodule `058cdc9`), SUSFS v1.5.5.*