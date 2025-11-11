#!/bin/bash

# 📦 Configuration
BOT_TOKEN="8130900592:AAGz4VEehIJDGOiTE3SqKzgZwM3F3ay_Ch4"
CHAT_ID="-1002858539681"

START_TIME=$(date +%s)
BUILD_MESSAGE_ID=""

function banner() {
    echo -e "\e[1;36m─────────────────────────────────────────────\e[0m"
}

function usage_stats() {
    CPU=$(top -bn1 | awk -F',' '/Cpu/ {gsub(" ",""); print $1}' | awk '{print 100-$8}')
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
        BUILD_MESSAGE_ID=$(echo "$RESPONSE" | jq '.result.message_id')
    else
        curl -s -F chat_id="$CHAT_ID" -F message_id="$BUILD_MESSAGE_ID" -F text="$text" -F parse_mode="HTML" \
            "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" >/dev/null
    fi
}

function abort_build() {
    telegram_progress "❌ Build aborted!"
    echo -e "\n❌ Build aborted!"
    exit 1
}

trap abort_build SIGINT SIGTERM

function compile() {
    source ~/.bashrc && source ~/.profile
    export LC_ALL=C USE_CCACHE=1 ARCH=arm64
    ccache -M 100G
    DATE=$(date '+%Y%m%d-%H%M')
    export KBUILD_BUILD_HOST=android-build-mtk
    export KBUILD_BUILD_USER="EronX-Projects"

    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 clang

    case "$1" in
        --ares) DEVICE=ares; DEFCONFIG=ares_defconfig ;;
        --chopin) DEVICE=chopin; DEFCONFIG=chopin_defconfig ;;
        --agate) DEVICE=agate; DEFCONFIG=agate_defconfig ;;
        *)
            echo "Usage: $0 <device> [--permissive]"
            echo "  Available devices: --ares, --chopin, --agate"
            echo "  Optional: --permissive"
            exit 1
            ;;
    esac

    telegram_progress "Starting Build System..."

    [ "$2" == "--permissive" ] && KERNEL_PERMISSIVE=true || KERNEL_PERMISSIVE=false

    mkdir -p out
    make O=out ARCH=arm64 $DEFCONFIG

    if [ "$KERNEL_PERMISSIVE" = true ]; then
        current_cmdline=$(grep '^CONFIG_CMDLINE=' out/.config | cut -d= -f2- | tr -d '"')
        if [[ "$current_cmdline" != *"androidboot.selinux=permissive"* ]]; then
            new_cmdline="$current_cmdline androidboot.selinux=permissive"
            scripts/config --file out/.config --set-str CONFIG_CMDLINE "$new_cmdline"
            scripts/config --file out/.config --enable CONFIG_CMDLINE_EXTEND --disable CONFIG_CMDLINE_FORCE
            make O=out ARCH=arm64 olddefconfig
        fi
    fi

    mkdir tmp
    cp out/.config tmp/final_config
    find out -name "*.ko" -delete
    make O=out ARCH=arm64 tmp/final_config
    rm -rf tmp

    PATH="${PWD}/clang/bin:${PATH}" \
    make -j$(nproc --all) O=out ARCH=arm64 \
        CC="ccache clang" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE="${PWD}/clang/bin/aarch64-linux-gnu-" \
        CROSS_COMPILE_ARM32="${PWD}/clang/bin/arm-linux-gnueabi-" \
        LD=ld.lld STRIP=llvm-strip AS=llvm-as AR=llvm-ar NM=llvm-nm \
        OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump modules Image.gz-dtb modules \
        CONFIG_NO_ERROR_ON_MISMATCH=y \
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
    find out -type f -name "*.ko" -exec cp -f {} AnyKernel/modules/ \;

    if [ "$DEVICE" = "agate" ]; then
        cp out/arch/arm64/boot/Image.gz AnyKernel
    else
        cp out/arch/arm64/boot/Image.gz-dtb AnyKernel
    fi

    if [ "$KERNEL_PERMISSIVE" = true ]; then
        SELINUX_MODE="Permissive"
    else
        SELINUX_MODE="Enforcing"
    fi

    cd AnyKernel
    ZIP_NAME="4.14.336-HydrogenKernel-KSUN+SUSFS-1.5.12-${DEVICE}-${SELINUX_MODE}-${DATE}_V2.1-VIC.zip"
    zip -r9 "$ZIP_NAME" *

    cd ../

    echo -e "\n🚀 Uploading Kernel ZIP to GoFile…"

    GOFILE_URL=$(bash upload.sh "AnyKernel/$ZIP_NAME")

    if [[ -z "$GOFILE_URL" || "$GOFILE_URL" == *"fail"* ]]; then
        echo "❌ Failed to upload to GoFile!"
        GOFILE_URL="Upload failed"
    else
        echo "✅ Kernel ZIP upload complete."
    fi

    END_TIME=$(date +%s)
    BUILD_DURATION=$((END_TIME - START_TIME))
    BUILD_H=$((BUILD_DURATION / 3600))
    BUILD_M=$(((BUILD_DURATION % 3600) / 60))
    BUILD_S=$((BUILD_DURATION % 60))
    BUILD_TIME_STR="${BUILD_H}h ${BUILD_M}m ${BUILD_S}s"

    ZIP_SIZE_BYTES=$(stat -c%s "AnyKernel/$ZIP_NAME")
    ZIP_SIZE_MB=$((ZIP_SIZE_BYTES / 1024 / 1024))
    MD5SUM=$(md5sum "AnyKernel/$ZIP_NAME" | awk '{print $1}')

    # If ZIP size is less than 10MB, treat as failure and send error message with auto-pin
    if [ "$ZIP_SIZE_MB" -lt 10 ]; then
    banner
    echo -e  "❌ \e[1;34mBuild failed — no kernel image produced..\e[0m"

        FAIL_MSG="❌ <b>Kernel Build Failed</b>

<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• SELinux:</b> <code>$SELINUX_MODE</code>
<b>• Duration:</b> <code>$BUILD_TIME_STR</code>
<b>• Reason:</b> No kernel image produced.

📋 See attached <code>error.log</code> for details."

        RESPONSE=$(curl -s -F chat_id="$CHAT_ID" \
             -F caption="$FAIL_MSG" \
             -F parse_mode="HTML" \
             -F document=@"error.log" \
             "https://api.telegram.org/bot$BOT_TOKEN/sendDocument")

        ERROR_MSG_ID=$(echo "$RESPONSE" | jq '.result.message_id')

        curl -s -F chat_id="$CHAT_ID" \
             -F message_id="$ERROR_MSG_ID" \
             -F disable_notification=true \
             "https://api.telegram.org/bot$BOT_TOKEN/pinChatMessage" >/dev/null
    
    echo -e  "📋 \e[1;34merror.log uploaded & pinned.\e[0m"
    banner

       return
    fi

    FINAL_MESSAGE="🎯 <b>Kernel Build Completed!</b>

<b>• KERNEL:</b> <code>$ZIP_NAME</code>
<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• TYPE:</b> <code>Test build</code>
<b>• SIZE:</b> <code>${ZIP_SIZE_MB}MB</code>
<b>• MD5:</b> <code>$MD5SUM</code>
<b>• DOWNLOAD:</b> <a href=\"$GOFILE_URL\">GoFile</a>

⏱️ <i>Total time: $BUILD_TIME_STR</i>"

    curl -s -F chat_id="$CHAT_ID" \
         -F message_id="$BUILD_MESSAGE_ID" \
         -F text="$FINAL_MESSAGE" \
         -F parse_mode="HTML" \
         "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" >/dev/null

    curl -s -F chat_id="$CHAT_ID" \
         -F message_id="$BUILD_MESSAGE_ID" \
         -F disable_notification=true \
         "https://api.telegram.org/bot$BOT_TOKEN/pinChatMessage" >/dev/null

    banner
    echo -e "🎉 \e[1;32mBuild completed & published!\e[0m"
    echo -e "📥 \e[1;34mDownload:\e[0m $GOFILE_URL"
    echo -e "⏱️ \e[1;33mDuration:\e[0m $BUILD_TIME_STR"
    banner
}

telegram_progress "Starting Build System..."
compile "$1" "$2"
zupload
