#!/bin/sh
set -eu

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
ROOTFS_TAR="${WORKSPACE_DIR}/kuiper-rootfs.tar"
SYSROOT_DIR="${KUIPER_SYSROOT_DIR:-/opt/kuiper-sysroot}"
STAMP_FILE="${SYSROOT_DIR}/.prepared-from-kuiper-rootfs"
LOCK_DIR="${SYSROOT_DIR}.lock"

if [ ! -f "${ROOTFS_TAR}" ]; then
    echo "Missing rootfs archive: ${ROOTFS_TAR}" >&2
    exit 1
fi

mkdir -p "$(dirname "${SYSROOT_DIR}")"

while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    if [ -f "${STAMP_FILE}" ]; then
        echo "Sysroot ready at ${SYSROOT_DIR}"
        mkdir -p "${WORKSPACE_DIR}/build"
        chown -R dev:dev "${WORKSPACE_DIR}/build" "${SYSROOT_DIR}" 2>/dev/null || true
        exit 0
    fi
    echo "Waiting for an existing sysroot preparation to finish..."
    sleep 5
done

cleanup() {
    rmdir "${LOCK_DIR}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

if [ ! -f "${STAMP_FILE}" ]; then
    rm -rf "${SYSROOT_DIR}"
    mkdir -p "${SYSROOT_DIR}"
    tar -xf "${ROOTFS_TAR}" -C "${SYSROOT_DIR}"
    touch "${STAMP_FILE}"
fi

mkdir -p "${WORKSPACE_DIR}/build"
chown -R dev:dev "${WORKSPACE_DIR}/build" "${SYSROOT_DIR}" 2>/dev/null || true

echo "Sysroot ready at ${SYSROOT_DIR}"
