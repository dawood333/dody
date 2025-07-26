#!/bin/bash

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
    export DEVICE=mt6893-common	
    export DEFCONFIG_1=chopin_user_defconfig
    export DEFCONFIG_2=ares_user_defconfig
    export DEFCONFIG_3=agate_user_defconfig
fi

if [ -z "$1" ]; then
    make -j"$(nproc --all)" O=out ARCH=arm64 SUBARCH=arm64 "$DEFCONFIG_1"
    cp -af out/.config arch/arm64/configs/"$DEFCONFIG_1"

    make -j"$(nproc --all)" O=out ARCH=arm64 SUBARCH=arm64 "$DEFCONFIG_2"
    cp -af out/.config arch/arm64/configs/"$DEFCONFIG_2"

     make -j"$(nproc --all)" O=out ARCH=arm64 SUBARCH=arm64 "$DEFCONFIG_3"
     cp -af out/.config arch/arm64/configs/"$DEFCONFIG_3"

    git add arch/arm64/configs/"$DEFCONFIG_1"
    git add arch/arm64/configs/"$DEFCONFIG_2"
    git add arch/arm64/configs/"$DEFCONFIG_3"
    git commit -m "$DEVICE: configs: Sync config with source"
    echo -e "\nSuccessfully regenerated defconfig for $DEVICE"
else
    make -j"$(nproc --all)" O=out ARCH=arm64 SUBARCH=arm64 "$DEFCONFIG"
    cp -af out/.config arch/arm64/configs/"$DEFCONFIG"
    git add arch/arm64/configs/"$DEFCONFIG"
    git commit -m "$DEVICE: config: Sync config with source"
    echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
fi
