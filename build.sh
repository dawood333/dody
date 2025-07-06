#!/bin/bash

function compile()
{
    source ~/.bashrc && source ~/.profile
    export LC_ALL=C && export USE_CCACHE=1
    ccache -M 100G
    export ARCH=arm64
    DATE=$(date '+%Y%m%d-%H%M')
    export KBUILD_BUILD_HOST=android-build-mtk
    export KBUILD_BUILD_USER="AbzRaider"

    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-17 clang

    # Argument checks
    case "$1" in
        --ares)
            export DEVICE=ares
            export DEFCONFIG=ares_user_defconfig
            ;;
        --chopin)
            export DEVICE=chopin
            export DEFCONFIG=chopin_user_defconfig
            ;;
        --agate)
            export DEVICE=agate
            export DEFCONFIG=agate_user_defconfig
            ;;
        *)
            echo "Usage: $0 <device> [--permissive]"
            echo ""
            echo "Available <device> options:"
            echo "  --ares       Ares"
            echo "  --chopin     Chopin"
            echo "  --agate      Agate"
            echo ""
            echo "Optional flags:"
            echo "  --permissive     Make kernel SELinux permissive"
            exit 1
            ;;
    esac

    # Permissive mode check (second argument)
    if [ "$2" = "--permissive" ]; then
        export KERNEL_PERMISSIVE=true
    else
        export KERNEL_PERMISSIVE=false
    fi

    if ! [ -d "out" ]; then
        echo "Kernel OUT Directory Not Found. Making Again"
        mkdir out
    fi

    make O=out ARCH=arm64 $DEFCONFIG

    if [ "$KERNEL_PERMISSIVE" = true ]; then
        current_cmdline=$(grep '^CONFIG_CMDLINE=' out/.config | cut -d= -f2- | sed 's/^"//' | sed 's/"$//')
        if [[ "$current_cmdline" != *"androidboot.selinux=permissive"* ]]; then
            new_cmdline="${current_cmdline} androidboot.selinux=permissive"
            scripts/config --file out/.config \
                --set-str CONFIG_CMDLINE "$new_cmdline"
    # Append cmdline to bootloader cmdline instead of replacing
    scripts/config --file out/.config \
        --enable CONFIG_CMDLINE_EXTEND \
        --disable CONFIG_CMDLINE_FORCE

# Regenerate config with new settings
    make O=out ARCH=arm64 olddefconfig
        fi
    fi

    mkdir tmp
    cp -r out/.config tmp/final_config
    find out -type f -name "*.ko" -delete
    make O=out ARCH=arm64 tmp/final_config
    rm -rf tmp 

    CCACHE_EXEC=$(which ccache)

    PATH="${PWD}/clang/bin:${PATH}" \
    make -j$(nproc --all) O=out \
        ARCH=arm64 \
        CC="ccache clang" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE="${PWD}/clang/bin/aarch64-linux-gnu-" \
        CROSS_COMPILE_ARM32="${PWD}/clang/bin/arm-linux-gnueabi-" \
        LD=ld.lld \
        STRIP=llvm-strip \
        AS=llvm-as \
        AR=llvm-ar \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
	modules \
	Image.gz-dtb modules \
        CONFIG_NO_ERROR_ON_MISMATCH=y 2>&1 | tee error.log
}

function zupload()
{
    rm -rf AnyKernel
    git clone --depth=1 https://github.com/AbzRaider/AnyKernel33 -b $DEVICE AnyKernel
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
    zip -r9 4.14.336-Test-OSS-KERNEL-${DEVICE}-${SELINUX_MODE}-${DATE}-VIC.zip *
    cd ../
    bash upload.sh AnyK*/*.zip
}

# Call compile with args
compile "$1" "$2"
zupload
