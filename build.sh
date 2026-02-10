#!/bin/bash
set -e
set -o pipefail

# 📦 Configuration
#BOT_TOKEN=""
#CHAT_ID=""

START_TIME=$(date +%s)
BUILD_MESSAGE_ID=""

function banner() {
    echo -e "\e[1;36m─────────────────────────────────────────────\e[0m"
}

function usage_stats() {
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    RAM=$(free -m | awk '/Mem:/ {printf "%.2f", $3/$2*100}')
    STORAGE=$(df . | awk 'NR==2 {gsub("%","",$5); print $5}')
}

function telegram_progress() {
    usage_stats
    local text="⚒️ <b>Compiling Kernel...</b>

<b>• DEVICE:</b> <code>${DEVICE:-Unknown}</code>
<b>• JOBS:</b> <code>$(nproc --all)</code>
<b>• PROGRESS:</b> <code>$1</code>
<b>• CPU:</b> <code>${CPU}%</code>
<b>• RAM:</b> <code>${RAM}%</code>
<b>• STORAGE:</b> <code>${STORAGE}%</code>"

    if [ -z "$BUILD_MESSAGE_ID" ]; then
        RESPONSE=$(curl -s -F chat_id="$CHAT_ID" -F text="$text" -F parse_mode="HTML" \
            "https://api.telegram.org/bot$BOT_TOKEN/sendMessage")
        BUILD_MESSAGE_ID=$(echo "$RESPONSE" | jq -r '.result.message_id')
    else
        curl -s -F chat_id="$CHAT_ID" -F message_id="$BUILD_MESSAGE_ID" \
            -F text="$text" -F parse_mode="HTML" \
            "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" >/dev/null
    fi
}

function abort_build() {
    telegram_progress "❌ Build aborted!"
    exit 1
}

trap abort_build SIGINT SIGTERM

function compile() {
    source ~/.bashrc || true
    source ~/.profile || true

    export LC_ALL=C ARCH=arm64 USE_CCACHE=1
    ccache -M 100G

    DATE=$(date '+%Y%m%d-%H%M')
    export KBUILD_BUILD_HOST=android-build-mtk
    export KBUILD_BUILD_USER="EronX-Projects"

    [ ! -d clang ] && \
        git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 clang

    case "$1" in
        --ares) DEVICE=ares; DEFCONFIG=ares_defconfig ;;
        --chopin) DEVICE=chopin; DEFCONFIG=chopin_defconfig ;;
        --agate) DEVICE=agate; DEFCONFIG=agate_defconfig ;;
        *) echo "Usage: $0 [--ares|--chopin|--agate] [--permissive]"; exit 1 ;;
    esac

    telegram_progress "Starting Build System..."

    [ "$2" == "--permissive" ] && KERNEL_PERMISSIVE=true || KERNEL_PERMISSIVE=false

    mkdir -p out
    make O=out ARCH=arm64 $DEFCONFIG

    if [ "$KERNEL_PERMISSIVE" = true ]; then
        CMDLINE=$(grep '^CONFIG_CMDLINE=' out/.config | cut -d= -f2- | tr -d '"')
        [[ "$CMDLINE" != *"androidboot.selinux=permissive"* ]] && {
            scripts/config --file out/.config \
                --set-str CONFIG_CMDLINE "$CMDLINE androidboot.selinux=permissive" \
                --enable CONFIG_CMDLINE_EXTEND \
                --disable CONFIG_CMDLINE_FORCE
            make O=out ARCH=arm64 olddefconfig
        }
    fi

    find out -name "*.ko" -delete

    PATH="${PWD}/clang/bin:${PATH}" \
    make -j$(nproc --all) O=out ARCH=arm64 \
        CC="ccache clang" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LD=ld.lld STRIP=llvm-strip AS=llvm-as AR=llvm-ar NM=llvm-nm \
        OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
        Image.gz-dtb modules \
        2>&1 | tee error.log &
    BUILD_PID=$!

    while kill -0 $BUILD_PID 2>/dev/null; do
        telegram_progress "Building..."
        sleep 5
    done
}

function zupload() {
    rm -rf AnyKernel
    git clone --depth=1 https://github.com/Eron-Evan/AnyKernel3 -b $DEVICE AnyKernel
    find out -name "*.ko" -exec cp -f {} AnyKernel/modules/ \;

    VMLINUX="Image.gz-dtb"
    [ "$DEVICE" = "agate" ] && VMLINUX="Image.gz"

    if [ ! -f "out/arch/arm64/boot/$VMLINUX" ]; then
        echo "❌ Kernel image missing!"
        exit 1
    fi

    cp out/arch/arm64/boot/$VMLINUX AnyKernel

    SELINUX_MODE=$([ "$KERNEL_PERMISSIVE" = true ] && echo Permissive || echo Enforcing)

    cd AnyKernel
    ZIP_NAME="HydrogenKernel-${DEVICE}-${SELINUX_MODE}-${DATE}.zip"
    zip -r9 "$ZIP_NAME" *
    cd ..

    GOFILE_URL=$(bash upload.sh "AnyKernel/$ZIP_NAME")

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    MD5=$(md5sum "AnyKernel/$ZIP_NAME" | awk '{print $1}')
    SIZE=$(stat -c%s "AnyKernel/$ZIP_NAME")

    FINAL_MSG="🎯 <b>Kernel Build Completed!</b>

<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• SELinux:</b> <code>$SELINUX_MODE</code>
<b>• SIZE:</b> <code>$((SIZE/1024/1024))MB</code>
<b>• MD5:</b> <code>$MD5</code>
<b>• DOWNLOAD:</b> <a href=\"$GOFILE_URL\">GoFile</a>

⏱️ <i>$((DURATION/60)) minutes</i>"

    curl -s -F chat_id="$CHAT_ID" -F message_id="$BUILD_MESSAGE_ID" \
         -F text="$FINAL_MSG" -F parse_mode="HTML" \
         "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" >/dev/null
}

telegram_progress "Starting Build System..."
compile "$1" "$2"
zupload
