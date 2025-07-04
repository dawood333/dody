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
    
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 clang

    # Argument checks
    if [ "$1" = "--ares" ]; then
        export DEVICE=ares
        export DEFCONFIG=ares_user_defconfig
	  export build_mitee=true
	  export region=CN
    elif [ "$1" = "--aresin" ]; then
	   export DEVICE=ares
         export DEFCONFIG=ares_user_defconfig
	   export build_mitee=false
	   export region=IN
    elif [ "$1" = "--chopin" ]; then
        export DEVICE=chopin
        export DEFCONFIG=chopin_user_defconfig
	  export build_mitee=true
	  export region=CN
    elif [ "$1" = "--choping" ]; then
	 export DEVICE=chopin
	 export DEFCONFIG=chopin_user_defconfig
	 export build_mitee=false
	 export region=GL
    else
        echo "Usage: $0 [--ares | --aresin | --chopin | --choping]"
        exit 1
    fi

    if ! [ -d "out" ]; then
        echo "Kernel OUT Directory Not Found. Making Again"
        mkdir out
    fi

    make O=out ARCH=arm64 $DEFCONFIG

if [ "$build_mitee" = true ]; then
    # Extract current CMDLINE (strip quotes properly)
    current_cmdline=$(grep '^CONFIG_CMDLINE=' out/.config | cut -d= -f2- | sed 's/^"//' | sed 's/"$//')

    # Append tee_type only if it's not already present
    if [[ "$current_cmdline" != *"androidboot.tee_type=1"* ]]; then
        new_cmdline="${current_cmdline} androidboot.tee_type=1"

        # Cleanly escape it for scripts/config
        scripts/config --file out/.config \
            --set-str CONFIG_CMDLINE "$new_cmdline"
    fi
fi

mkdir tmp
cp -r out/.config tmp/final_config
make O=out ARCH=arm64 tmp/final_config
rm -rf tmp

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
	modules \
        CONFIG_NO_ERROR_ON_MISMATCH=y 2>&1 | tee error.log 
}

function zupload()
{
    rm -rf AnyKernel    
    git clone --depth=1 https://github.com/AbzRaider/AnyKernel33 -b $DEVICE AnyKernel
    if [ "$DEVICE" = "agate" ]; then
	    cp out/arch/arm64/boot/Image.gz AnyKernel
    else
	    cp out/arch/arm64/boot/Image.gz-dtb AnyKernel
    fi
    cd AnyKernel
    zip -r9 4.14.336-Test-OSS-KERNEL-${DEVICE}-${region}-${DATE}-VIC.zip *
    cd ../
    bash upload.sh AnyK*/*.zip
}

# Call compile function with the first argument
compile "$1"
# Call zupload function
zupload
