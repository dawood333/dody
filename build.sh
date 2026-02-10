#!/bin/bash
set -e

START_TIME=$(date +%s)

# ===============================
# Build configuration
# ===============================
export ARCH=arm64
export LC_ALL=C
export USE_CCACHE=1
export KBUILD_BUILD_HOST=android-build-mtk
export KBUILD_BUILD_USER="EronX-Projects"

DATE=$(date '+%Y%m%d-%H%M')

# ===============================
# Select device
# ===============================
case "$1" in
  --ares)
    DEVICE=ares
    DEFCONFIG=ares_defconfig
    ;;
  --chopin)
    DEVICE=chopin
    DEFCONFIG=chopin_defconfig
    ;;
  --agate)
    DEVICE=agate
    DEFCONFIG=agate_defconfig
    ;;
  *)
    echo "Usage: $0 <--ares|--chopin|--agate> [--permissive]"
    exit 1
    ;;
esac

[ "$2" = "--permissive" ] && KERNEL_PERMISSIVE=true || KERNEL_PERMISSIVE=false

echo "======================================"
echo " Building kernel for: $DEVICE"
echo " Defconfig          : $DEFCONFIG"
echo " SELinux            : $([ "$KERNEL_PERMISSIVE" = true ] && echo Permissive || echo Enforcing)"
echo "======================================"

# ===============================
# Toolchain
# ===============================
if [ ! -d clang ]; then
  git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 clang
fi

export PATH="$PWD/clang/bin:$PATH"

ccache -M 100G

# ===============================
# Build
# ===============================
mkdir -p out
make O=out $DEFCONFIG

if [ "$KERNEL_PERMISSIVE" = true ]; then
  current_cmdline=$(grep '^CONFIG_CMDLINE=' out/.config | cut -d= -f2- | tr -d '"')
  if [[ "$current_cmdline" != *"androidboot.selinux=permissive"* ]]; then
    scripts/config --file out/.config \
      --set-str CONFIG_CMDLINE "$current_cmdline androidboot.selinux=permissive" \
      --enable CONFIG_CMDLINE_EXTEND \
      --disable CONFIG_CMDLINE_FORCE
    make O=out olddefconfig
  fi
fi

make -j$(nproc --all) O=out \
  CC="ccache clang" \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LD=ld.lld \
  STRIP=llvm-strip \
  AS=llvm-as \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  Image.gz-dtb modules

# ===============================
# AnyKernel packaging
# ===============================
rm -rf AnyKernel
git clone --depth=1 https://github.com/Eron-Evan/AnyKernel3 AnyKernel

find out -name "*.ko" -exec cp -f {} AnyKernel/modules/ \;

if [ "$DEVICE" = "agate" ]; then
  cp out/arch/arm64/boot/Image.gz AnyKernel/
else
  cp out/arch/arm64/boot/Image.gz-dtb AnyKernel/
fi

cd AnyKernel

SELINUX_MODE=$([ "$KERNEL_PERMISSIVE" = true ] && echo Permissive || echo Enforcing)
ZIP_NAME="HydrogenKernel-${DEVICE}-${SELINUX_MODE}-${DATE}.zip"

zip -r9 "$ZIP_NAME" .

cd ..

# ===============================
# Finish
# ===============================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "======================================"
echo " Build completed successfully"
echo " Output : AnyKernel/$ZIP_NAME"
echo " Time   : $((DURATION / 60)) min $((DURATION % 60)) sec"
echo "======================================"
