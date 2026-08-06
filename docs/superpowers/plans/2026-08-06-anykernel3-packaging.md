# AnyKernel3 Flashable Zip for ReSukiSU veux Kernel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the built ReSukiSU veux kernel (`arch/arm64/boot/Image`) into an AnyKernel3 flashable zip that a user installs via recovery, replacing the device's `boot` kernel.

**Architecture:** Vendor the upstream `osm0sis/AnyKernel3` template into the repo (`anykernel.sh` + `tools/ak3-core.sh` + `META-INF`), set `anykernel.sh` for the veux device (`BLOCK=boot`, A/B auto), and add a `build-anykernel.sh` that copies the freshly-built `Image` into the template and zips it. Optionally add a GitHub Actions workflow to auto-build + attach to a Release on tag.

**Tech Stack:** AnyKernel3 (osm0sis), shell, clang-10 toolchain (`llvm-arm-toolchain-ship-10.0.9`), `zip`, git.

## Global Constraints

- Kernel payload = **raw `Image`** (`arch/arm64/boot/Image`, ~27 MB), matching `BOARD_KERNEL_IMAGE_NAME=Image` and the `split_boot` search list in `tools/ak3-core.sh` (line 310).
- Device = **veux** (single codename). A/B device (`IS_SLOT_DEVICE=auto`).
- Kernel partition = **`boot`** (`BLOCK=boot`).
- Do NOT commit the ~27 MB `Image` into git — it's build output. `build-anykernel.sh` places it at build time; `.gitignore` covers it.
- Do NOT ship any SUSFS (blocked — master is Manual Hook only). `do.modules=0` (kernel-only swap, no .ko injection).
- The zip installs via **recovery** (PixelOS/TWRP), not `fastboot`.
- Follow the approved design spec: `docs/superpowers/specs/2026-08-06-anykernel3-packaging-design.md`.

---
## File Structure

**Created:**
- `AnyKernel3/anykernel.sh` — veux device config (edited from upstream template)
- `AnyKernel3/tools/ak3-core.sh` — vendored upstream (from osm0sis/AnyKernel3, unmodified)
- `AnyKernel3/META-INF/com/google/android/update-binary` + `updater-script` — vendored upstream
- `AnyKernel3/README.md` — flash instructions
- `build-anykernel.sh` — builds Image + packages zip
- `.github/workflows/build-release.yml` — optional CI auto-release (Task 5)

**Committed (source):** `anykernel.sh`, `ak3-core.sh`, `META-INF/*`, `README.md`, `build-anykernel.sh`, workflow.
**Not committed (build output, gitignored):** `AnyKernel3/Image`, the produced `*.zip`.

---

## Task 1: Vendor the AnyKernel3 template

**Files:**
- Create: `AnyKernel3/anykernel.sh`, `AnyKernel3/tools/ak3-core.sh`, `AnyKernel3/META-INF/com/google/android/{update-binary,updater-script}`, `AnyKernel3/LICENSE`, `AnyKernel3/README.md`

**Context:** The `AnyKernel3` dir is vendored from `osm0sis/AnyKernel3` (a fresh clone at `$CLAUDE_JOB_DIR/tmp/ak3`). Copy the upstream files verbatim first, then edit `anykernel.sh` for veux in Task 2. Do not hand-write `ak3-core.sh` or `update-binary` — copy them (they're large, battle-tested shell).

- [ ] **1.1** Copy the upstream AnyKernel3 template into the repo:
```bash
cd /home/hayyan/Desktop/Code/kernel_xiaomi_sm6375-20260613
mkdir -p AnyKernel3
cp -r "$CLAUDE_JOB_DIR/tmp/ak3/anykernel.sh" \
      "$CLAUDE_JOB_DIR/tmp/ak3/tools" \
      "$CLAUDE_JOB_DIR/tmp/ak3/META-INF" \
      "$CLAUDE_JOB_DIR/tmp/ak3/LICENSE" \
      "$CLAUDE_JOB_DIR/tmp/ak3/README.md" \
      AnyKernel3/
```
  Expected: `AnyKernel3/` has `anykernel.sh`, `tools/ak3-core.sh`, `META-INF/com/google/android/{update-binary,updater-script}`, `LICENSE`, `README.md`.

- [ ] **1.2** Remove upstream cruft not needed (the tuna example edits, placeholder dirs):
```bash
rm -rf AnyKernel3/ramdisk AnyKernel3/patch AnyKernel3/modules AnyKernel3/tools/*.sh~ 2>/dev/null
```
  Keep the empty `ramdisk/`, `patch/`, `modules/` dirs only if upstream ships them; they're optional for a kernel-only zip. (Upstream ships them empty — remove them since we do no ramdisk/module work.)

- [ ] **1.3** Add `.gitignore` entry so the built `Image` and `*.zip` are never committed:
```bash
echo -e "\n# AnyKernel3 build output\n/AnyKernel3/Image\n/AnyKernel3/*.zip" >> .gitignore
```
  (Check `.gitignore` already covers `*.o`, `Image`, etc. from earlier work.)

- [ ] **1.4** Commit:
```bash
git add AnyKernel3 .gitignore
git commit -m "AnyKernel3: vendor osm0sis template (veux)
"
```

### Task 2: Configure `anykernel.sh` for veux

**Files:**
- Modify: `AnyKernel3/anykernel.sh`

**Interfaces:**
- Consumes: Task 1's vendored `anykernel.sh` + `tools/ak3-core.sh`.
- Produces: a device-correct `anykernel.sh` (BLOCK=boot, IS_SLOT_DEVICE=auto) that `build-anykernel.sh` zips in Task 3.

**Context:** The upstream `anykernel.sh` has example values (`ExampleKernel`, `maguro`, `omap_hsmmc` block path, tuna init.rc edits). Replace with veux values. The `dump_boot; write_boot;` at the end is the actual flash action — keep those (kernel-only swap; `dump_boot` dumps the on-device boot partition and replaces `kernel`, `write_boot` repacks+flashes). Remove the example `init.rc`/`fstab` edits (do.devicecheck + BLOCK only).

- [ ] **2.1** Replace the `properties()` block's kernel.string + device names:
```sh
properties() { '
kernel.string=positron_susfs (ReSukiSU) for veux
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=veux
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties
```

- [ ] **2.2** Replace the boot shell variables:
```sh
# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
```
  (`BLOCK=boot` lets AK3 detect the by-name path via the `boot` partition name; `IS_SLOT_DEVICE=auto` handles `_a`/`_b` on A/B.)

- [ ] **2.3** Remove the tuna-specific example edits (the `init.rc`, `init.tuna.rc`, `fstab.tuna` blocks after `dump_boot;`), leaving:
```sh
# boot install
dump_boot;
write_boot;
```

- [ ] **2.4** Verify `anykernel.sh` has no leftover `maguro`/`tuna`/`omap` references:
```bash
grep -niE "maguro|tuna|omap|Example" AnyKernel3/anykernel.sh || echo "clean"
```

- [ ] **2.5** Commit:
```bash
git add AnyKernel3/anykernel.sh
git commit -m "AnyKernel3: configure anykernel.sh for veux (boot, A/B)
"
```

### Task 3: `build-anykernel.sh` — build + zip

**Files:**
- Create: `build-anykernel.sh`

**Interfaces:**
- Consumes: Task 2's `AnyKernel3/` (with configured `anykernel.sh`), the built `arch/arm64/boot/Image`, and the clang-10 toolchain path (env `TC`).
- Produces: `positron_susfs-veux-<git-short>.zip` in the repo root.

**Context:** This script builds the kernel Image (same commands as HANDOVER, verified working), copies it into the template, and zips. It must be idempotent and fail loudly on missing toolchain/build.

- [ ] **3.1** Write `build-anykernel.sh`:
```sh
#!/bin/sh
# Build the ReSukiSU veux kernel and package it as an AnyKernel3 zip.
# Usage: ./build-anykernel.sh [toolchain-root]
#   toolchain-root: dir containing llvm-arm-toolchain-ship/ (default: ./toolchain)
set -e
cd "$(dirname "$0")"

TC_ROOT="${1:-./toolchain}"
TC="$TC_ROOT/llvm-arm-toolchain-ship/10.0.9/bin"
if [ ! -x "$TC/clang" ]; then
  echo "ERROR: clang not found at $TC/clang (set up toolchain first)" >&2
  exit 1
fi

# 1. Build the kernel Image (verified commands)
export PATH="$TC:$PATH" ARCH=arm64
export LD_LIBRARY_PATH="$TC/../lib"
[ -e "$TC/../lib/libtinfo.so.5" ] || ln -sf /usr/lib64/libtinfo.so.6 "$TC/../lib/libtinfo.so.5"
[ -e "$TC/../lib/libxml2.so.2" ] || ln -sf /usr/lib64/libxml2.so.16 "$TC/../lib/libxml2.so.2"
make HOSTCC=gcc CC=clang LD=ld.lld AR=llvm-ar STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy NM=llvm-nm Image -j$(nproc)

# 2. Copy Image into AnyKernel3 template
cp arch/arm64/boot/Image AnyKernel3/Image

# 3. Zip (exclude git + build outputs)
VER=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
cd AnyKernel3
zip -r9 "../positron_susfs-veux-${VER}.zip" . -x ".git/*" "README.md" "*.placeholder"
cd ..
echo "Built: $(ls -la positron_susfs-veux-${VER}.zip)"
```
  Note: `zip` command matches upstream doc (`zip -r9 UPDATE-AnyKernel3.zip * -x .git README.md *placeholder`).

- [ ] **3.2** `chmod +x build-anykernel.sh`.

- [ ] **3.3** Dry-run the zip step only (no full rebuild) to verify the template zips cleanly:
```bash
cp arch/arm64/boot/Image AnyKernel3/Image   # use the already-built Image
cd AnyKernel3 && zip -r9 ../test-ak3.zip . -x ".git/*" README.md
cd .. && unzip -l test-ak3.zip
```
  Expected: zip lists `anykernel.sh`, `tools/ak3-core.sh`, `META-INF/...`, `Image`. Remove `test-ak3.zip` after.

- [ ] **3.4** Commit:
```bash
git add build-anykernel.sh
git commit -m "build: add build-anykernel.sh (Image -> AnyKernel3 zip)
"
```

### Task 4: Full build + package verification

**Files:** none (runs the script)

**Context:** Prove the script works end-to-end with the actual toolchain.

- [ ] **4.1** Run the full script:
```bash
./build-anykernel.sh /path/to/toolchain-parent
```
  Expected: builds Image (or no-op if already built), prints `Built: positron_susfs-veux-<short>.zip`.

- [ ] **4.2** Inspect the zip contents:
```bash
unzip -l positron_susfs-veux-<short>.zip
```
  Expected: `anykernel.sh`, `tools/ak3-core.sh`, `META-INF/com/google/android/{updater-script,update-binary}`, `Image`, `LICENSE`.

- [ ] **4.3** Sanity-check `anykernel.sh` parses (shell syntax):
```bash
bash -n AnyKernel3/anykernel.sh && echo "anykernel.sh OK"
bash -n AnyKernel3/tools/ak3-core.sh && echo "ak3-core.sh OK"
```

- [ ] **4.4** Confirm the payload `Image` is the raw kernel (matches `split_boot` list):
```bash
file AnyKernel3/Image   # Linux kernel ARM64 boot executable Image
```

- [ ] **4.5** (Optional, if device connected) — real flash is out of scope here; note in the report that a device boot test remains.

### Task 5: Optional — GitHub Actions auto-release on tag

**Files:**
- Create: `.github/workflows/build-release.yml`

**Context:** Automate: on `v*` tag push, build Image with clang-10 (download from ravindu644's tutorial release), package the zip, attach to the GitHub Release. This needs the toolchain downloadable in CI (it is: `https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/llvm-arm-toolchain-ship-10.0.9.tar.gz`).

- [ ] **5.1** Create `.github/workflows/build-release.yml`:
```yaml
name: build-release
on:
  push:
    tags: ['v*']
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive          # KernelSU submodule is required
      - name: Install deps
        run: |
          sudo apt-get update && sudo apt-get install -y zip zlib1g-dev libxml2-dev
      - name: Download clang-10
        run: |
          mkdir -p toolchain
          curl -L -o toolchain/llvm.tar.gz \
            https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/llvm-arm-toolchain-ship-10.0.9.tar.gz
          tar -xzf toolchain/llvm.tar.gz -C toolchain
          # fix libxml2 symlink for ld.lld
          ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.2 toolchain/llvm-arm-toolchain-ship/10.0.9/lib/libxml2.so.2
      - name: Build + package
        run: ./build-anykernel.sh toolchain
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: positron_susfs-veux-*.zip
```

- [ ] **5.2** Validate the YAML (e.g. `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build-release.yml'))"` or a YAML linter).

- [ ] **5.3** Commit:
```bash
git add .github/workflows/build-release.yml
git commit -m "ci: build + release AnyKernel3 zip on v* tag
"
```

## Self-Review

- **Spec coverage:** vendored template (Task 1) ✓, veux config `BLOCK=boot`/A/B (Task 2) ✓, build script producing zip (Task 3) ✓, end-to-end verification (Task 4) ✓, optional CI release (Task 5) ✓. All spec sections covered.
- **Placeholder scan:** no TBDs; every command + file content is concrete. `device.name2-5` left empty deliberately (veux is the single codename per user).
- **Consistency:** payload named `Image` everywhere (matches `split_boot` list at ak3-core.sh:310); `BLOCK=boot` + `IS_SLOT_DEVICE=auto` consistent across spec/plan; zip naming `positron_susfs-veux-<short>.zip` consistent.
- **YAGNI:** no ramdisk/module injection (do.modules=0), no fastboot raw image (out of scope, documented). CI kept optional (Task 5).

## Execution Handoff

Plan complete. Two execution options:
1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.
2. **Inline Execution** — run in this session, checkpoint batches.

Which approach?
