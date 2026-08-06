#!/bin/sh
# Build the ReSukiSU veux kernel and package it as an AnyKernel3 zip.
# Usage: ./build-anykernel.sh [toolchain-root]
#   toolchain-root: dir containing llvm-arm-toolchain-ship/ (default: ./toolchain)
set -e
cd "$(dirname "$0")"

TC_ROOT="${1:-./toolchain}"
TC="$TC_ROOT/llvm-arm-toolchain-ship/10.0.9/bin"
if [ ! -x "$TC/clang" ]; then
  echo "ERROR: clang not found at $TC/clang (set up the toolchain first)" >&2
  exit 1
fi

# 1. Build the kernel Image (identical to the verified HANDOVER commands)
export PATH="$TC:$PATH" ARCH=arm64
export LD_LIBRARY_PATH="$TC/../lib"
# clang-10 needs libtinfo.so.5 and ld.lld needs libxml2.so.2; symlink if missing
[ -e "$TC/../lib/libtinfo.so.5" ] || ln -sf /usr/lib64/libtinfo.so.6 "$TC/../lib/libtinfo.so.5"
[ -e "$TC/../lib/libxml2.so.2" ] || ln -sf /usr/lib64/libxml2.so.16 "$TC/../lib/libxml2.so.2"
make HOSTCC=gcc CC=clang LD=ld.lld AR=llvm-ar STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy NM=llvm-nm Image -j$(nproc)

# 2. Copy Image into the AnyKernel3 template
cp arch/arm64/boot/Image AnyKernel3/Image

# 3. Zip into a standard zip (python3 zipfile: no external 'zip' dependency)
VER=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
OUT="positron_susfs-veux-${VER}.zip"
python3 - "$OUT" <<'EOF'
import sys, zipfile, os
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk('AnyKernel3'):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, 'AnyKernel3'))
EOF
echo "Built: $(ls -la "$OUT")"