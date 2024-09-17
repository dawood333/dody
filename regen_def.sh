#!/bin/bash

if [ $1 = "--ares" ]; then
		export DEVICE=ares
		export DEFCONFIG=ares_user_defconfig
	else
		export DEVICE=chopin
		export DEFCONFIG=chopin_user_defconfig
fi

make -j"$(nproc --all)" O=out ARCH=arm64 SUBARCH=arm64 "$DEFCONFIG"
cp -af out/.config arch/arm64/configs/"$DEFCONFIG"
git add arch/arm64/configs/"${DEFCONFIG}"
git commit -m "$DEVICE: Sync config with source"
echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
