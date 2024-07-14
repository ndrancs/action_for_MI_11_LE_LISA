#!/bin/bash
#

SECONDS=0 # builtin bash timer
AK3_DIR="$HOME/AnyKernel3"
DEFCONFIG="lisa_defconfig"

ZIPNAME="Quickscrap-lisa_$(date '+%Y%m%d-%H%M').zip"

# Main Variables
KDIR=$(pwd)
DATE=$(date +%d-%h-%Y-%R:%S | sed "s/:/./g")
START=$(date +"%s")
TCDIR=$(pwd)/proton-clang
IMAGE=$(pwd)/out/arch/arm64/boot/Image

# Naming Variables
KNAME="Quickscrap KernelSU"
VERSION="v1.0"
CODENAME="lisa"
MIN_HEAD=$(git rev-parse HEAD)
export KVERSION="${KNAME}-${VERSION}-${CODENAME}-$(echo ${MIN_HEAD:0:8})"

# GitHub Variables
export COMMIT_HASH=$(git rev-parse --short HEAD)
export REPO_URL="https://github.com/likkai/ksu_kernel_xiaomi_lisa"

# Build Information
LINKER=ld.lld
export COMPILER_NAME="$(${TCDIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
export LINKER_NAME="$("${TCDIR}"/bin/${LINKER} --version | head -n 1 | sed 's/(compatible with [^)]*)//' | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
export KBUILD_BUILD_USER=likkai
export KBUILD_BUILD_HOST=runner
export DEVICE="Xiaomi 11 Lite 5G NE"
export CODENAME="lisa"
export TYPE="Stable"
export DISTRO=$(source /etc/os-release && echo "${NAME}")

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

MAKE_PARAMS="O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=$TCDIR/bin/llvm-"

export PATH="$TCDIR/bin:$PATH"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make $MAKE_PARAMS $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out
	echo "Cleaned output folder"
fi

mkdir -p out
make $MAKE_PARAMS $DEFCONFIG

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $MAKE_PARAMS || exit $?
make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

kernel="out/arch/arm64/boot/Image"
dtb="out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
dtbo="out/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo"

if [ ! -f "$kernel" ] || [ ! -f "$dtb" ] || [ ! -f "$dtbo" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

echo -e "\nKernel compiled succesfully! Zipping up...\n"
if [ -d "$AK3_DIR" ]; then
	cp -r $AK3_DIR AnyKernel3
	git -C AnyKernel3 checkout lisa &> /dev/null
elif ! git clone -q https://github.com/likkai/AnyKernel3 -b lisa; then
	echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
	exit 1
fi

cp $kernel AnyKernel3
cp $dtb AnyKernel3/dtb
python2 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo
cp $(find out/modules/lib/modules/5.4* -name '*.ko') AnyKernel3/modules/vendor/lib/modules/
cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules
cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/modules.load
sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' AnyKernel3/modules/vendor/lib/modules/modules.dep
sed -i 's/.*\///g' AnyKernel3/modules/vendor/lib/modules/modules.load
rm -rf out/arch/arm64/boot out/modules
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..
rm -rf AnyKernel3
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
