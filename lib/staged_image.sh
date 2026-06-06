# Staged image backend for Linux-capable boards.

BOARD_IMAGE_BACKEND=${BOARD_IMAGE_BACKEND:-legacy-disk}
BOARD_BOOT_STAGE=
BOARD_FREEBSD_STAGE=
BOARD_ROOTFS_METALOG=
BOARD_STAGE_KERNEL_METALOG=

staged_image_define_paths ( ) {
    BOARD_BOOT_STAGE=${WORKDIR}/stage/boot
    BOARD_FREEBSD_STAGE=${WORKDIR}/stage/rootfs
    BOARD_ROOTFS_METALOG=${BOARD_FREEBSD_STAGE}/METALOG
    BOARD_STAGE_KERNEL_METALOG=${BOARD_FREEBSD_STAGE}/kernel.meta
}
strategy_add $PHASE_POST_CONFIG staged_image_define_paths

staged_image_prepare_dirs ( ) {
    rm -rf "${WORKDIR}/stage"
    mkdir -p "${BOARD_BOOT_STAGE}" "${BOARD_FREEBSD_STAGE}"
}

staged_image_use_mountpoints ( ) {
    if [ "${BOARD_IMAGE_BACKEND}" != "staged-makefs-mkimg" ]; then
        return 0
    fi
    BOARD_BOOT_MOUNTPOINT_PREFIX=${BOARD_BOOT_STAGE}
    BOARD_FAT_MOUNTPOINT_PREFIX=${BOARD_BOOT_STAGE}
    BOARD_FREEBSD_MOUNTPOINT_PREFIX=${BOARD_FREEBSD_STAGE}
    BOARD_UFS_MOUNTPOINT_PREFIX=${BOARD_FREEBSD_STAGE}
}
strategy_add $PHASE_POST_CONFIG staged_image_use_mountpoints

staged_image_host_checks ( ) {
    if [ "${BOARD_IMAGE_BACKEND}" = "staged-makefs-mkimg" ]; then
        host_check_disk_image_tools
    fi
}
strategy_add $PHASE_CHECK staged_image_host_checks

staged_image_reject_legacy_on_linux ( ) {
    if [ -n "${HOST_IS_LINUX}" ] && [ "${BOARD_IMAGE_BACKEND}" = "legacy-disk" ]; then
        echo "Board ${BOARDNAME} uses legacy-disk image handling, which is only supported on FreeBSD hosts."
        exit 1
    fi
}
strategy_add $PHASE_CHECK staged_image_reject_legacy_on_linux

staged_image_create_raw ( ) {
    local SIZE_DISPLAY="$((${IMAGE_SIZE} / 1000000))MB"
    echo "Creating a ${SIZE_DISPLAY} raw disk image in:"
    echo "    ${IMG}"
    [ -f "${IMG}" ] && rm -f "${IMG}"
    dd if=/dev/zero of="${IMG}" bs=1 count=0 seek="${IMAGE_SIZE}" >/dev/null 2>&1
}

staged_image_no_mount ( ) {
    staged_image_prepare_dirs
}

staged_image_register_partition ( ) {
    disk_created_new "$1" "$2"
}

staged_image_merge_metalogs ( ) {
    local METALOG_OUT=$1
    shift

    {
        echo "#mtree 2.0"
        for F in "$@"; do
            if [ -f "${F}" ]; then
                awk 'NR > 1 { print }' "${F}"
            fi
        done
    } > "${METALOG_OUT}.tmp"
    mv "${METALOG_OUT}.tmp" "${METALOG_OUT}"
}

staged_image_add_unlisted_tree_to_metalog ( ) {
    local ROOTDIR=$1
    local METALOG=$2
    local TMP_SPEC=${WORKDIR}/_.mtree.$$.spec
    local TMP_FILTERED=${WORKDIR}/_.mtree.$$.filtered

    if [ ! -d "${ROOTDIR}" ]; then
        return 0
    fi

    (
        cd "${ROOTDIR}" || exit 1
        "${MTREE_CMD}" -c -p . -k type,mode,uid,gid,uname,gname,link,size,time 2>/dev/null
    ) > "${TMP_SPEC}" || exit 1

    awk '
        NR == FNR {
            if (FNR > 1) {
                seen[$1] = 1
            }
            next
        }
        NR == 1 { next }
        {
            if ($1 == ".") {
                next
            }
            if (seen[$1]) {
                next
            }
            sub(/uid=[^ ]+/, "uid=0")
            sub(/gid=[^ ]+/, "gid=0")
            if ($0 !~ /uid=/) {
                $0 = $0 " uid=0"
            }
            if ($0 !~ /gid=/) {
                $0 = $0 " gid=0"
            }
            sub(/uname=[^ ]+/, "uname=root")
            sub(/gname=[^ ]+/, "gname=wheel")
            if ($0 !~ /uname=/) {
                $0 = $0 " uname=root"
            }
            if ($0 !~ /gname=/) {
                $0 = $0 " gname=wheel"
            }
            print
        }
    ' "${METALOG}" "${TMP_SPEC}" > "${TMP_FILTERED}"
    cat "${TMP_FILTERED}" >> "${METALOG}"
    rm -f "${TMP_SPEC}" "${TMP_FILTERED}"
}

staged_image_make_esp ( ) {
    local ESP_IMAGE=$1
    local ESP_SIZE=${2:-64m}
    "${MAKEFS_CMD}" -t msdos -s "${ESP_SIZE}" -B le -N "${BOARD_FREEBSD_STAGE}/etc" "${ESP_IMAGE}" "${BOARD_BOOT_STAGE}"
}

staged_image_make_rootfs ( ) {
    local ROOTFS_IMAGE=$1
    local METALOG=$2
    (
        cd "${BOARD_FREEBSD_STAGE}" || exit 1
        "${MAKEFS_CMD}" \
            -t ffs \
            -o version=2,label=root \
            -o softupdates=1 \
            -b 200k \
            -f 1k \
            -R 4m \
            -B le \
            -N "${BOARD_FREEBSD_STAGE}/etc" \
            "${ROOTFS_IMAGE}" \
            "${METALOG}"
    )
}

staged_image_compose_gpt ( ) {
    local ESP_IMAGE=$1
    local ROOTFS_IMAGE=$2
    "${MKIMG_CMD}" \
        -s gpt \
        -p "efi:=${ESP_IMAGE}:16m" \
        -p "freebsd-ufs:=${ROOTFS_IMAGE}:+0" \
        -o "${IMG}"
}
