# Setup for FriendlyElec SOM-RK3399

KERNCONF=SOM_RK3399

TARGET=arm64
TARGET_ARCH=aarch64

IMAGE_SIZE=$((8 * 1000 * 1000 * 1000))

SOM_RK3399_FIRMWARE_ROOT=${SOM_RK3399_FIRMWARE_ROOT:-/linux/oh-my-bsdlab/external/som-rk3399/u-boot}
SOM_RK3399_IDBLOADER=${SOM_RK3399_IDBLOADER:-${SOM_RK3399_FIRMWARE_ROOT}/idbloader.img}
SOM_RK3399_UBOOT_ITB=${SOM_RK3399_UBOOT_ITB:-${SOM_RK3399_FIRMWARE_ROOT}/u-boot.itb}

SOM_RK3399_DTB_NAME=${SOM_RK3399_DTB_NAME:-rk3399-som-rk3399.dts}
SOM_RK3399_DTB_BASENAME=${SOM_RK3399_DTB_BASENAME:-rk3399-som-rk3399}
SOM_RK3399_DTB_DESTDIR=${SOM_RK3399_DTB_DESTDIR:-${FREEBSD_SRC}/sys/contrib/device-tree/src/arm64/rockchip}
SOM_RK3399_DTB_SOURCE_TREE=${SOM_RK3399_DTB_SOURCE_TREE:-/linux/oh-my-bsdlab/external/freebsd-src}
SOM_RK3399_DTB_SOURCE=${SOM_RK3399_DTB_SOURCE:-${SOM_RK3399_DTB_SOURCE_TREE}/sys/contrib/device-tree/src/arm64/rockchip/${SOM_RK3399_DTB_NAME}}
SOM_RK3399_DTB_MAKEFILE_SOURCE=${SOM_RK3399_DTB_MAKEFILE_SOURCE:-${SOM_RK3399_DTB_SOURCE_TREE}/sys/modules/dtb/rockchip/Makefile}
SOM_RK3399_DTB_MAKEFILE_DEST=${SOM_RK3399_DTB_MAKEFILE_DEST:-${FREEBSD_SRC}/sys/modules/dtb/rockchip/Makefile}

som-rk3399_check_firmware ( ) {
    if [ ! -f "${SOM_RK3399_IDBLOADER}" ]; then
        echo "Missing SOM-RK3399 firmware file:"
        echo "    ${SOM_RK3399_IDBLOADER}"
        echo
        echo "Build or point SOM_RK3399_IDBLOADER at the idbloader.img produced by"
        echo "/linux/oh-my-bsdlab for the SOM-RK3399 board."
        exit 1
    fi
    if [ ! -f "${SOM_RK3399_UBOOT_ITB}" ]; then
        echo "Missing SOM-RK3399 firmware file:"
        echo "    ${SOM_RK3399_UBOOT_ITB}"
        echo
        echo "Build or point SOM_RK3399_UBOOT_ITB at the u-boot.itb produced by"
        echo "/linux/oh-my-bsdlab for the SOM-RK3399 board."
        exit 1
    fi
    echo "Found SOM-RK3399 firmware in:"
    echo "    ${SOM_RK3399_FIRMWARE_ROOT}"
}
strategy_add $PHASE_CHECK som-rk3399_check_firmware

som-rk3399_ensure_dts ( ) {
    local DEST_DTS=${SOM_RK3399_DTB_DESTDIR}/${SOM_RK3399_DTB_NAME}

    if [ ! -f "${DEST_DTS}" ]; then
        if [ ! -f "${SOM_RK3399_DTB_SOURCE}" ]; then
            echo "Missing SOM-RK3399 DTS in both source trees."
            echo "Expected one of:"
            echo "    ${DEST_DTS}"
            echo "    ${SOM_RK3399_DTB_SOURCE}"
            echo
            echo "Populate /usr/src with rk3399-som-rk3399 DTS, or provide"
            echo "SOM_RK3399_DTB_SOURCE pointing to an alternate FreeBSD source tree."
            exit 1
        fi

        echo "Migrating SOM-RK3399 DTS into ${FREEBSD_SRC}"
        mkdir -p "${SOM_RK3399_DTB_DESTDIR}" || exit 1
        cp "${SOM_RK3399_DTB_SOURCE}" "${DEST_DTS}" || exit 1
    fi

    if [ ! -f "${SOM_RK3399_DTB_MAKEFILE_DEST}" ]; then
        echo "Missing Rockchip DTB module Makefile:"
        echo "    ${SOM_RK3399_DTB_MAKEFILE_DEST}"
        exit 1
    fi

    if ! grep -q "rockchip/${SOM_RK3399_DTB_NAME}" "${SOM_RK3399_DTB_MAKEFILE_DEST}"; then
        if [ ! -f "${SOM_RK3399_DTB_MAKEFILE_SOURCE}" ]; then
            echo "Rockchip DTB Makefile does not list ${SOM_RK3399_DTB_NAME},"
            echo "and the migration source Makefile is missing:"
            echo "    ${SOM_RK3399_DTB_MAKEFILE_SOURCE}"
            exit 1
        fi

        echo "Updating Rockchip DTB module Makefile in ${FREEBSD_SRC}"
        cp "${SOM_RK3399_DTB_MAKEFILE_SOURCE}" "${SOM_RK3399_DTB_MAKEFILE_DEST}" || exit 1
    fi
}
strategy_add $PHASE_CHECK som-rk3399_ensure_dts

som-rk3399_install_dtb ( ) (
    local DTS_PATH=${SOM_RK3399_DTB_DESTDIR}/${SOM_RK3399_DTB_NAME}
    local TMPDIR=${WORKDIR}/som-rk3399-dtb
    local TMPDTB=${TMPDIR}/${SOM_RK3399_DTB_BASENAME}.dtb

    buildenv=`cd ${FREEBSD_SRC}; make TARGET_ARCH=$TARGET_ARCH buildenvvars`

    mkdir -p ${TMPDIR} || exit 1
    rm -f ${TMPDTB}

    echo "${FREEBSD_SRC}/sys/tools/fdt/make_dtb.sh ${FREEBSD_SRC}/sys ${DTS_PATH} ${TMPDIR}" | (cd ${FREEBSD_SRC}; make TARGET_ARCH=$TARGET_ARCH buildenv > /dev/null)
    if [ ! -f "${TMPDTB}" ]; then
        echo "Failed to build ${SOM_RK3399_DTB_BASENAME}.dtb from:"
        echo "    ${DTS_PATH}"
        exit 1
    fi
    cp "${TMPDTB}" EFI/BOOT/rk3399-som-rk3399.dtb || exit 1
)

som-rk3399_partition_image ( ) {
    echo "Installing SOM-RK3399 firmware on ${DISK_MD}"
    dd if=${SOM_RK3399_IDBLOADER} of=/dev/${DISK_MD} conv=sync bs=512 seek=64
    dd if=${SOM_RK3399_UBOOT_ITB} of=/dev/${DISK_MD} conv=sync bs=512 seek=16384

    echo "Installing partitions on ${DISK_MD}"
    disk_partition_mbr
    disk_fat_create 64m 16 1048576 -
    disk_ufs_create
}
strategy_add $PHASE_PARTITION_LWW som-rk3399_partition_image

strategy_add $PHASE_BUILD_OTHER freebsd_loader_efi_build
strategy_add $PHASE_BOOT_INSTALL mkdir -p EFI/BOOT
strategy_add $PHASE_BOOT_INSTALL freebsd_loader_efi_copy EFI/BOOT/BOOTAA64.EFI
strategy_add $PHASE_BOOT_INSTALL som-rk3399_install_dtb

strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel .
strategy_add $PHASE_FREEBSD_BOARD_INSTALL mkdir -p boot/efi
