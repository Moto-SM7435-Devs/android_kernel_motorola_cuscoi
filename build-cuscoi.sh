#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Bootstrap and build the Motorola cuscoi kernel tree.
#
# The kernel tree intentionally keeps device-trees and vendor modules in sibling
# repositories. This wrapper makes that layout reproducible instead of requiring
# the caller to prepare the workspace manually.
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${ROOT_DIR}"
WORKSPACE_DIR="$(dirname "${KERNEL_DIR}")"
BRANCH="${KBRANCH:-android-16}"

MODULES_REPO="${MODULES_REPO:-https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-modules.git}"
DTS_REPO="${DTS_REPO:-https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-devicetrees.git}"
MODULES_DIR="${MODULES_DIR:-${WORKSPACE_DIR}/sm7435-modules}"
DTS_DIR="${DTS_DIR:-${WORKSPACE_DIR}/sm7435-devicetrees}"

log() { printf '[cuscoi] %s\n' "$*"; }
die() { printf '[cuscoi] ERROR: %s\n' "$*" >&2; exit 1; }

sync_repo() {
    local url="$1" dir="$2"
    if [[ -d "${dir}/.git" ]]; then
        log "Updating $(basename "${dir}")"
        git -C "${dir}" fetch --depth=1 origin "${BRANCH}"
        git -C "${dir}" checkout -B "${BRANCH}" "FETCH_HEAD"
    elif [[ -e "${dir}" ]]; then
        die "${dir} exists but is not a git repository"
    else
        log "Cloning $(basename "${dir}")"
        git clone --depth=1 --branch "${BRANCH}" "${url}" "${dir}"
    fi
}

prepare() {
    command -v git >/dev/null 2>&1 || die "git is required"
    [[ -x "${KERNEL_DIR}/build.sh" ]] || die "build.sh is missing or not executable"

    sync_repo "${DTS_REPO}" "${DTS_DIR}"
    sync_repo "${MODULES_REPO}" "${MODULES_DIR}"

    local vendor_link="${KERNEL_DIR}/arch/arm64/boot/dts/vendor"
    if [[ -L "${vendor_link}" ]]; then
        local target
        target="$(readlink "${vendor_link}")"
        [[ -e "${KERNEL_DIR}/arch/arm64/boot/dts/${target}" ]] ||
            die "device-tree symlink is broken: ${vendor_link} -> ${target}"
    elif [[ -d "${vendor_link}" ]]; then
        log "Using in-tree device-tree directory"
    else
        die "missing device-tree vendor path: ${vendor_link}"
    fi

    local required
    for required in \
        arch/arm64/configs/gki_defconfig \
        arch/arm64/configs/vendor/parrot_perf.config \
        arch/arm64/configs/vendor/ext_config/moto-parrot.config \
        arch/arm64/configs/vendor/ext_config/moto-parrot-cuscoi.config; do
        [[ -f "${KERNEL_DIR}/${required}" ]] || die "missing required config: ${required}"
    done

    log "Workspace is ready"
}

prepare
exec "${KERNEL_DIR}/build.sh" "$@"
