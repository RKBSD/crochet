# Setup for FriendlyElec SOM-RK3399

KERNCONF=SOM_RK3399

TARGET=arm64
TARGET_ARCH=aarch64

IMAGE_SIZE=$((8 * 1000 * 1000 * 1000))
BOARD_IMAGE_BACKEND=staged-makefs-mkimg

OH_MY_BSDLAB_ROOT=${OH_MY_BSDLAB_ROOT:-}
if [ -z "${OH_MY_BSDLAB_ROOT}" ]; then
    OH_MY_BSDLAB_ROOT=`host_first_existing_dir \
        "${TOPDIR}/oh-my-bsdlab" \
        "${TOPDIR}/../oh-my-bsdlab"` || true
fi

if [ -z "${SOM_RK3399_FIRMWARE_ROOT}" ]; then
    SOM_RK3399_FIRMWARE_ROOT=`host_first_existing_dir \
        "${OH_MY_BSDLAB_ROOT}/external/som-rk3399/u-boot" \
        "${TOPDIR}/external/som-rk3399/u-boot" \
        "${TOPDIR}/../external/som-rk3399/u-boot" \
        "${TOPDIR}/som-rk3399/u-boot" \
        "${TOPDIR}/../som-rk3399/u-boot" \
        "${TOPDIR}/u-boot" \
        "${TOPDIR}/../u-boot" \
        "/usr/local/share/u-boot/som-rk3399" \
        "/usr/local/share/u-boot/u-boot-som-rk3399"` || true
fi

SOM_RK3399_IDBLOADER=${SOM_RK3399_IDBLOADER:-${SOM_RK3399_FIRMWARE_ROOT}/idbloader.img}
SOM_RK3399_UBOOT_ITB=${SOM_RK3399_UBOOT_ITB:-${SOM_RK3399_FIRMWARE_ROOT}/u-boot.itb}

SOM_RK3399_DTB_NAME=${SOM_RK3399_DTB_NAME:-rk3399-som-rk3399.dts}
SOM_RK3399_DTB_BASENAME=${SOM_RK3399_DTB_BASENAME:-rk3399-som-rk3399}
SOM_RK3399_DTB_DESTDIR=${SOM_RK3399_DTB_DESTDIR:-${FREEBSD_SRC}/sys/contrib/device-tree/src/arm64/rockchip}
if [ -z "${SOM_RK3399_DTB_SOURCE_TREE}" ]; then
    SOM_RK3399_DTB_SOURCE_TREE=`host_first_existing_dir \
        "${OH_MY_BSDLAB_ROOT}/external/freebsd-src" \
        "${TOPDIR}/external/freebsd-src" \
        "${TOPDIR}/../external/freebsd-src" \
        "${TOPDIR}/freebsd-src" \
        "${TOPDIR}/../freebsd-src" \
        "${FREEBSD_SRC}" \
        "/usr/src"` || true
fi

SOM_RK3399_DTB_SOURCE=${SOM_RK3399_DTB_SOURCE:-${SOM_RK3399_DTB_SOURCE_TREE}/sys/contrib/device-tree/src/arm64/rockchip/${SOM_RK3399_DTB_NAME}}
SOM_RK3399_DTB_MAKEFILE_SOURCE=${SOM_RK3399_DTB_MAKEFILE_SOURCE:-${SOM_RK3399_DTB_SOURCE_TREE}/sys/modules/dtb/rockchip/Makefile}
SOM_RK3399_DTB_MAKEFILE_DEST=${SOM_RK3399_DTB_MAKEFILE_DEST:-${FREEBSD_SRC}/sys/modules/dtb/rockchip/Makefile}
SOM_RK3399_ESP_SIZE=${SOM_RK3399_ESP_SIZE:-64m}
SOM_RK3399_ESP_OFFSET=${SOM_RK3399_ESP_OFFSET:-16m}

som-rk3399_check_firmware ( ) {
    if [ ! -f "${SOM_RK3399_IDBLOADER}" ]; then
        echo "Missing SOM-RK3399 firmware file:"
        echo "    ${SOM_RK3399_IDBLOADER}"
        echo
        echo "Set SOM_RK3399_IDBLOADER or SOM_RK3399_FIRMWARE_ROOT to a directory"
        echo "containing the board's idbloader.img."
        exit 1
    fi
    if [ ! -f "${SOM_RK3399_UBOOT_ITB}" ]; then
        echo "Missing SOM-RK3399 firmware file:"
        echo "    ${SOM_RK3399_UBOOT_ITB}"
        echo
        echo "Set SOM_RK3399_UBOOT_ITB or SOM_RK3399_FIRMWARE_ROOT to a directory"
        echo "containing the board's u-boot.itb."
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
            echo "Populate ${FREEBSD_SRC} with rk3399-som-rk3399 DTS, or provide"
            echo "SOM_RK3399_DTB_SOURCE or SOM_RK3399_DTB_SOURCE_TREE."
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

    mkdir -p ${TMPDIR} || exit 1
    rm -f ${TMPDTB}

    echo "${FREEBSD_SRC}/sys/tools/fdt/make_dtb.sh ${FREEBSD_SRC}/sys ${DTS_PATH} ${TMPDIR}" | (cd ${FREEBSD_SRC}; ${FREEBSD_MAKE} TARGET_ARCH=$TARGET_ARCH buildenv > /dev/null)
    if [ ! -f "${TMPDTB}" ]; then
        echo "Failed to build ${SOM_RK3399_DTB_BASENAME}.dtb from:"
        echo "    ${DTS_PATH}"
        exit 1
    fi
    cp "${TMPDTB}" EFI/BOOT/rk3399-som-rk3399.dtb || exit 1
)

som-rk3399_partition_image ( ) {
    if [ "${BOARD_IMAGE_BACKEND}" = "staged-makefs-mkimg" ]; then
        staged_image_register_partition FAT staged-esp
        staged_image_register_partition UFS staged-rootfs
        return 0
    fi

    echo "Installing SOM-RK3399 firmware on ${DISK_MD}"
    dd if=${SOM_RK3399_IDBLOADER} of=/dev/${DISK_MD} conv=sync bs=512 seek=64
    dd if=${SOM_RK3399_UBOOT_ITB} of=/dev/${DISK_MD} conv=sync bs=512 seek=16384

    echo "Installing partitions on ${DISK_MD}"
    disk_partition_mbr
    disk_fat_create 64m 16 1048576 -
    disk_ufs_create
}
strategy_add $PHASE_PARTITION_LWW som-rk3399_partition_image

som-rk3399_make_rootfs_image ( ) {
    staged_image_merge_metalogs \
        "${WORKDIR}/som-rk3399-rootfs.mtree" \
        "${BOARD_ROOTFS_METALOG}" \
        "${BOARD_STAGE_KERNEL_METALOG}"
    staged_image_add_unlisted_tree_to_metalog "${BOARD_FREEBSD_STAGE}" "${WORKDIR}/som-rk3399-rootfs.mtree"
    staged_image_make_rootfs "${WORKDIR}/som-rk3399-rootfs.img" "${WORKDIR}/som-rk3399-rootfs.mtree"
}

som-rk3399_make_esp_image ( ) {
    staged_image_make_esp "${WORKDIR}/som-rk3399-esp.img" "${SOM_RK3399_ESP_SIZE}"
}

som-rk3399_compose_image ( ) {
    if [ "${BOARD_IMAGE_BACKEND}" != "staged-makefs-mkimg" ]; then
        return 0
    fi

    rm -f "${WORKDIR}/som-rk3399-rootfs.img" "${WORKDIR}/som-rk3399-esp.img" "${WORKDIR}/som-rk3399-rootfs.mtree"
    som-rk3399_make_rootfs_image
    som-rk3399_make_esp_image
    "${MKIMG_CMD}" \
        -s gpt \
        -p "efi:=${WORKDIR}/som-rk3399-esp.img:${SOM_RK3399_ESP_OFFSET}" \
        -p "freebsd-ufs:=${WORKDIR}/som-rk3399-rootfs.img:+0" \
        -o "${IMG}"
    dd if="${SOM_RK3399_IDBLOADER}" of="${IMG}" conv=notrunc bs=512 seek=64
    dd if="${SOM_RK3399_UBOOT_ITB}" of="${IMG}" conv=notrunc bs=512 seek=16384
}
strategy_add $PHASE_POST_UNMOUNT som-rk3399_compose_image

strategy_add $PHASE_BUILD_OTHER freebsd_loader_efi_build
strategy_add $PHASE_BOOT_INSTALL mkdir -p EFI/BOOT
strategy_add $PHASE_BOOT_INSTALL freebsd_loader_efi_copy EFI/BOOT/BOOTAA64.EFI
strategy_add $PHASE_BOOT_INSTALL som-rk3399_install_dtb

strategy_add $PHASE_FREEBSD_BOARD_INSTALL board_default_installkernel .
strategy_add $PHASE_FREEBSD_BOARD_INSTALL mkdir -p boot/efi
