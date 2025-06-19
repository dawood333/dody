#!/bin/bash

function compile() 
{
    source ~/.bashrc && source ~/.profile
    export LC_ALL=C && export USE_CCACHE=1
    ccache -M 100G
    export ARCH=arm64
    export KBUILD_BUILD_HOST=android-build-mtk
    export KBUILD_BUILD_USER="AbzRaider"
    
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 clang

    # Argument checks
    if [ "$1" = "--ares" ]; then
        export DEVICE=ares
        export DEFCONFIG=ares_user_defconfig
    elif [ "$1" = "--chopin" ]; then
        export DEVICE=chopin
        export DEFCONFIG=chopin_user_defconfig
    elif [ "$1" = "--agate" ]; then
	export DEVICE=agate
        export DEFCONFIG=agate_user_defconfig	
else
        echo "Usage: $0 [--ares | --chopin| --agate]"
        exit 1
    fi

    if ! [ -d "out" ]; then
        echo "Kernel OUT Directory Not Found. Making Again"
        mkdir out
    fi

    make O=out ARCH=arm64 $DEFCONFIG

    PATH="${PWD}/clang/bin:${PATH}" \
    make -j$(nproc --all) O=out \
        ARCH=arm64 \
        CC="clang" \
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
        CONFIG_NO_ERROR_ON_MISMATCH=y 2>&1 | tee error.log 
}

function zupload()
{
    rm -rf AnyKernel    
    git clone --depth=1 https://github.com/AbzRaider/AnyKernel33 -b $DEVICE AnyKernel
    cp out/arch/arm64/boot/Image.gz-dtb AnyKernel
    cd AnyKernel
    zip -r9 4.14.336-Test-OSS-KERNEL-$DEVICE-VIC.zip *
    cd ..
    bash upload.sh AnyK*/*.zip
}

# Call compile function with the first argument
compile "$1"
# Call zupload function
zupload
