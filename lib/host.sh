# Host abstraction helpers.

HOST_OS=`uname -s`
HOST_IS_FREEBSD=
HOST_IS_LINUX=
HOST_NCPU=1

FREEBSD_MAKE=${FREEBSD_MAKE:-}
MAKEFS_CMD=${MAKEFS_CMD:-}
MKIMG_CMD=${MKIMG_CMD:-}
MTREE_CMD=${MTREE_CMD:-}

host_detect ( ) {
    case "${HOST_OS}" in
        FreeBSD)
            HOST_IS_FREEBSD=y
            if [ -z "${FREEBSD_MAKE}" ]; then
                FREEBSD_MAKE=make
            fi
            HOST_NCPU=`sysctl -n hw.ncpu 2>/dev/null || echo 1`
            ;;
        Linux)
            HOST_IS_LINUX=y
            if [ -z "${FREEBSD_MAKE}" ]; then
                FREEBSD_MAKE=bmake
            fi
            HOST_NCPU=`nproc 2>/dev/null || echo 1`
            ;;
        *)
            echo "Unsupported host operating system: ${HOST_OS}"
            exit 1
            ;;
    esac

    if [ -z "${HOST_NCPU}" ]; then
        HOST_NCPU=1
    fi
}
PRIORITY=10 strategy_add $PHASE_POST_CONFIG host_detect
PRIORITY=100

host_require_cmd ( ) {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi

    echo "Missing required host command: $1"
    exit 1
}

host_require_linux_cmds ( ) {
    if [ -z "${HOST_IS_LINUX}" ]; then
        return 0
    fi

    host_require_cmd "${FREEBSD_MAKE}"
    host_require_cmd dtc
}
strategy_add $PHASE_CHECK host_require_linux_cmds

host_freebsd_buildenvvars ( ) {
    ${FREEBSD_MAKE} -C "${FREEBSD_SRC}" TARGET_ARCH="${TARGET_ARCH}" buildenvvars
}

host_freebsd_buildenv ( ) {
    ${FREEBSD_MAKE} -C "${FREEBSD_SRC}" TARGET_ARCH="${TARGET_ARCH}" buildenv
}

host_find_bootstrap_tool ( ) {
    local TOOL=$1
    local BUILDENV
    local CANDIDATE
    local TOOLPATH

    BUILDENV=`host_freebsd_buildenvvars`
    TOOLPATH=`eval "${BUILDENV} env | awk -F= '/^PATH=/{print substr(\$0,6)}'"`
    CANDIDATE=`printf '%s\n' ${TOOLPATH} | tr ':' '\n' | while read P; do
        if [ -x "${P}/${TOOL}" ]; then
            echo "${P}/${TOOL}"
            break
        fi
    done`
    if [ -n "${CANDIDATE}" ]; then
        echo "${CANDIDATE}"
        return 0
    fi

    if [ -d "${MAKEOBJDIRPREFIX}" ]; then
        find "${MAKEOBJDIRPREFIX}" -path "*/${TOOL}" -perm -111 2>/dev/null | head -n 1
        return 0
    fi

    return 1
}

host_resolve_disk_image_tools ( ) {
    if [ -n "${MAKEFS_CMD}" ] && [ ! -x "${MAKEFS_CMD}" ]; then
        echo "Configured MAKEFS_CMD is not executable:"
        echo "    ${MAKEFS_CMD}"
        exit 1
    fi
    if [ -n "${MKIMG_CMD}" ] && [ ! -x "${MKIMG_CMD}" ]; then
        echo "Configured MKIMG_CMD is not executable:"
        echo "    ${MKIMG_CMD}"
        exit 1
    fi
    if [ -n "${MTREE_CMD}" ] && [ ! -x "${MTREE_CMD}" ]; then
        echo "Configured MTREE_CMD is not executable:"
        echo "    ${MTREE_CMD}"
        exit 1
    fi

    if [ -z "${MAKEFS_CMD}" ]; then
        MAKEFS_CMD=`host_find_bootstrap_tool makefs`
    fi
    if [ -z "${MKIMG_CMD}" ]; then
        MKIMG_CMD=`host_find_bootstrap_tool mkimg`
    fi
    if [ -z "${MTREE_CMD}" ]; then
        MTREE_CMD=`host_find_bootstrap_tool mtree`
    fi

    if [ -n "${MAKEFS_CMD}" ]; then
        export MAKEFS_CMD
    fi
    if [ -n "${MKIMG_CMD}" ]; then
        export MKIMG_CMD
    fi
    if [ -n "${MTREE_CMD}" ]; then
        export MTREE_CMD
    fi
}
strategy_add $PHASE_CHECK host_resolve_disk_image_tools

host_check_disk_image_tools ( ) {
    if [ -z "${MAKEFS_CMD}" ] || [ ! -x "${MAKEFS_CMD}" ]; then
        echo "Missing host-runnable makefs."
        echo "Set MAKEFS_CMD explicitly, or build bootstrap tools from /usr/src"
        echo "with WITH_DISK_IMAGE_TOOLS_BOOTSTRAP=y."
        exit 1
    fi
    if [ -z "${MKIMG_CMD}" ] || [ ! -x "${MKIMG_CMD}" ]; then
        echo "Missing host-runnable mkimg."
        echo "Set MKIMG_CMD explicitly, or build bootstrap tools from /usr/src"
        echo "with WITH_DISK_IMAGE_TOOLS_BOOTSTRAP=y."
        exit 1
    fi
    if [ -z "${MTREE_CMD}" ] || [ ! -x "${MTREE_CMD}" ]; then
        echo "Missing host-runnable mtree."
        echo "Build bootstrap tools from /usr/src or set MTREE_CMD explicitly."
        exit 1
    fi
}
