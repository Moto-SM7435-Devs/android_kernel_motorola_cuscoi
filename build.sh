#!/usr/bin/env bash
# =============================================================================
#  NEBULA Kernel Builder
#  Motorola moto g96 5G (cuscoi) | SM7435 / Snapdragon 7s Gen 2 (Parrot)
#  android-16
# =============================================================================

# ═══════════════════════════════════════════════════════════════════════════════
#  §1  SHELL OPTIONS
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail
IFS=$'\n\t'

# ═══════════════════════════════════════════════════════════════════════════════
#  §2  COLOUR
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;34m'
    CYAN=$'\033[1;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  §3  DEVICE & IDENTITY
# ═══════════════════════════════════════════════════════════════════════════════
export DEVICE="${DEVICE:-Motorola moto g96 5G}"
export CODENAME="${CODENAME:-cuscoi}"
export PLATFORM="${PLATFORM:-parrot}"
export KNAME="${KNAME:-NEBULA}"
export BUILDER="${BUILDER:-${USER:-builder}}"
export DATE="${DATE:-$(date +%Y-%m-%d)}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-${BUILDER}}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-nebula-ci}"

KDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KDIR

COMMIT_HASH="$(git -C "${KDIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BRANCH_NAME="$(git -C "${KDIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

if [[ -f "${KDIR}/version" ]]; then
    export KBUILD_BUILD_VERSION
    KBUILD_BUILD_VERSION="$(grep 'num=' "${KDIR}/version" | cut -d= -f2)"
    export VERSION
    VERSION="$(grep 'ver=' "${KDIR}/version" | cut -d= -f2)"
else
    export KBUILD_BUILD_VERSION=1
    export VERSION="r1"
fi

ZIP_NAME="${ZIP_NAME:-${KNAME}-${CODENAME}-${VERSION}-${DATE}}"

# ═══════════════════════════════════════════════════════════════════════════════
#  §4  PATHS
# ═══════════════════════════════════════════════════════════════════════════════
ROOT_DIR="$(dirname "${KDIR}")"
OUT_DIR="${OUT_DIR:-${KDIR}/out}"
DIST_DIR="${DIST_DIR:-${OUT_DIR}/dist}"
MODULES_INSTALL_DIR="${MODULES_INSTALL_DIR:-${OUT_DIR}/modules_install}"
AK3="${AK3:-${KDIR}/AnyKernel3}"
LOG_FILE="${LOG_FILE:-${KDIR}/build.log}"

# Companion repositories (sibling directories to the kernel tree)
MODULES_DIR="${ROOT_DIR}/sm7435-modules"
DEVICETREES_DIR="${ROOT_DIR}/sm7435-devicetrees"
MODULES_REPO="https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-modules"
DEVICETREES_REPO="https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-devicetrees"
AK3_REPO="${AK3_REPO:-https://github.com/Moto-SM7435-Devs/AnyKernel3}"
KBRANCH="${KBRANCH:-android-16}"

# Device-tree search roots and glob patterns for dtree()
DTS_ROOTS=(
    "arch/arm64/boot/dts"
    "arch/arm64/boot/dts/vendor"
    "vendor/qcom/opensource/devicetrees"
    "vendor/qcom/opensource/display-devicetree"
)
DISPLAY_DTS_GLOBS=(
    "*${CODENAME}*.dts"  "*${CODENAME}*.dtsi"
    "*cusco*.dts"        "*cusco*.dtsi"
    "*parrot*.dts"       "*parrot*.dtsi"
    "*display*.dts"      "*display*.dtsi"
    "*dsi*.dts"          "*panel*.dts"
)

# ═══════════════════════════════════════════════════════════════════════════════
#  §5  BUILD CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
export ARCH="${ARCH:-arm64}"
export SUBARCH="${SUBARCH:-arm64}"
PROCS="${PROCS:-$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
export DEBUG="${DEBUG:-0}"
export COMPILER="${COMPILER:-clang}"
CLANG_VERSION_MIN=14

# ═══════════════════════════════════════════════════════════════════════════════
#  §6  DEFCONFIG & CONFIG FRAGMENTS
# ═══════════════════════════════════════════════════════════════════════════════
export CONFIG="${CONFIG:-gki_defconfig}"
export LOCALVERSION="${LOCALVERSION:--${KNAME}}"
export KERNEL_VARIANT="${KERNEL_VARIANT:-perf}"
export TARGET_PRODUCT="${TARGET_PRODUCT:-cuscoi}"
export TARGET_BOARD_PLATFORM="${TARGET_BOARD_PLATFORM:-parrot}"

# Motorola MMI config is generated from:
#   moto-parrot.config
#   moto-parrot-cuscoi.config
#   moto-parrot-perf.config
#
# The generated moto_fragment.config is then consumed as a single Motorola
# fragment by the existing merge_config.sh flow.
CONFIG_FRAGMENTS=(
    "arch/arm64/configs/vendor/parrot_perf.config"
    "arch/arm64/configs/vendor/ext_config/moto_fragment.config"
)
DEBUG_FRAGMENT="arch/arm64/configs/vendor/ext_config/debug-parrot-${CODENAME}.config"

# ═══════════════════════════════════════════════════════════════════════════════
#  §7  TOOLCHAIN SETUP
# ═══════════════════════════════════════════════════════════════════════════════
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT:-arm-linux-gnueabi-}"

# Prepend CLANG_DIR/bin to PATH if explicitly set
if [[ -n "${CLANG_DIR:-}" ]]; then
    [[ -x "${CLANG_DIR}/bin/clang" ]] ||
        { echo "${RED}[✗] CLANG_DIR does not contain bin/clang: ${CLANG_DIR}${NC}" >&2; exit 1; }
    export PATH="${CLANG_DIR}/bin:${PATH}"
fi

# Locate ld.lld — required even for olddefconfig on kernel 6.x
# (scripts/Kconfig.include checks for the linker at Kconfig time)
_find_lld() {
    # 1. Prebuilt inside CLANG_DIR
    if [[ -n "${CLANG_DIR:-}" && -x "${CLANG_DIR}/bin/ld.lld" ]]; then
        echo "${CLANG_DIR}/bin/ld.lld"; return
    fi
    # 2. System PATH
    if command -v ld.lld >/dev/null 2>&1; then
        command -v ld.lld; return
    fi
    # 3. Versioned system binaries (lld-18, lld-17, …)
    local v
    for v in 20 19 18 17 16 15 14; do
        if command -v "ld.lld-${v}" >/dev/null 2>&1; then
            command -v "ld.lld-${v}"; return
        fi
    done
    echo ""
}
LLD_PATH="$(_find_lld)"
if [[ -z "${LLD_PATH}" ]]; then
    echo -e "${RED}[✗] ld.lld not found!${NC}" >&2
    echo -e "    Install it:  sudo apt install lld" >&2
    echo -e "    Or set:      CLANG_DIR=/path/to/prebuilt-clang" >&2
    exit 1
fi
export LD="${LLD_PATH}"

# make flags shared by every invocation
declare -a MAKE_FLAGS=(
    O="${OUT_DIR}"
    ARCH="${ARCH}"
    SUBARCH="${ARCH}"
    LLVM=1
    LLVM_IAS=1
    LD="${LLD_PATH}"
    CROSS_COMPILE="${CROSS_COMPILE}"
    CROSS_COMPILE_COMPAT="${CROSS_COMPILE_COMPAT}"
    LOCALVERSION="${LOCALVERSION}"
    KBUILD_BUILD_USER="${KBUILD_BUILD_USER}"
    KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"
)

_compiler_string() {
    if command -v clang >/dev/null 2>&1; then
        clang --version | sed -n '1p'
    elif command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
        "${CROSS_COMPILE}gcc" --version | sed -n '1p'
    else
        echo "unknown"
    fi
}
COMPILER_STRING="$(_compiler_string)"

# ═══════════════════════════════════════════════════════════════════════════════
#  §8  TRAPS & SIGNALS
# ═══════════════════════════════════════════════════════════════════════════════
_on_error() {
    echo -e "\n${RED}${BOLD}[✗] Script aborted (line ${BASH_LINENO[0]}): ${BASH_COMMAND}${NC}" >&2
}
_on_sigint() {
    echo -e "\n${RED}${BOLD}[✗] Interrupted by user.${NC}" >&2
    exit 130
}
trap '_on_error'   ERR
trap '_on_sigint'  SIGINT SIGTERM

cd "${KDIR}" || { echo "Failed to cd into ${KDIR}" >&2; exit 1; }

# ═══════════════════════════════════════════════════════════════════════════════
#  §9  CORE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════
step()  { echo -e "\n${BLUE}${BOLD}━━━  $*  ━━━${NC}"; }
msg()   { echo -e "\n${YELLOW}[*] $*${NC}"; }
ok()    { echo -e "\n${GREEN}[✓] $*${NC}"; }
warn()  { echo -e "\n${YELLOW}[!] $*${NC}"; }
abort() { echo -e "\n${RED}[✗] $*${NC}" >&2; exit 1; }

run_make() { make "${MAKE_FLAGS[@]}" "$@"; }

requirements() {
    step "Checking requirements"
    local missing=() tool
    for tool in awk bc bison cpio depmod find flex git make perl python3 sed sort tee xargs zip; do
        command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
    done
    ((${#missing[@]} == 0)) || abort "Missing required tools: ${missing[*]}"

    command -v clang >/dev/null 2>&1 ||
        abort "clang not found — install it or set CLANG_DIR=/path/to/clang"

    local ver
    ver=$(clang --version 2>/dev/null | head -1 \
          | grep -oP '\d+(?=\.\d+\.\d+)' | head -1 || true)
    if [[ -z "${ver}" || "${ver}" -lt "${CLANG_VERSION_MIN}" ]]; then
        warn "clang v${ver:-?} may be too old (need >= ${CLANG_VERSION_MIN})"
    fi

    command -v ld.lld >/dev/null 2>&1 ||
        abort "ld.lld not found — run: sudo apt install lld  (or set CLANG_DIR to a prebuilt clang)"
    ok "Requirements satisfied (clang v${ver:-?}, ld.lld: ${LLD_PATH}, ${PROCS} CPUs)"
}

banner() {
    local cs_short="${COMPILER_STRING:0:48}"
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║        ███╗   ██╗███████╗██████╗ ██╗   ██╗██╗          ║"
    echo "║        ████╗  ██║██╔════╝██╔══██╗██║   ██║██║          ║"
    echo "║        ██╔██╗ ██║█████╗  ██████╔╝██║   ██║██║          ║"
    echo "║        ██║╚██╗██║██╔══╝  ██╔══██╗██║   ██║██║          ║"
    echo "║        ██║ ╚████║███████╗██████╔╝╚██████╔╝███████╗   A ║"
    echo "║        ╚═╝  ╚═══╝╚══════╝╚═════╝  ╚═════╝ ╚══════╝     ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    printf "║  %-56s║\n" "Device   : ${DEVICE} [${CODENAME}]"
    printf "║  %-56s║\n" "Platform : ${PLATFORM} — SM7435 / Snapdragon 7s Gen 2"
    printf "║  %-56s║\n" "Branch   : ${BRANCH_NAME}  (${COMMIT_HASH})"
    printf "║  %-56s║\n" "Compiler : ${cs_short}"
    printf "║  %-56s║\n" "Jobs     : ${PROCS}   Version : ${VERSION}"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §10  CONFIG MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Generate the Motorola MMI config files when they do not exist.
_prepare_mmi_config() {
    local ext_config="${KDIR}/arch/${ARCH}/configs/vendor/ext_config"
    local moto_fragment="${ext_config}/moto_fragment.config"
    local product_bzl="${KDIR}/moto_product.bzl"

    mkdir -p "${ext_config}"

    if [[ ! -f "${moto_fragment}" ]]; then
        cat \
            "${ext_config}/moto-${TARGET_BOARD_PLATFORM}.config" \
            "${ext_config}/moto-${TARGET_BOARD_PLATFORM}-${TARGET_PRODUCT}.config" \
            "${ext_config}/moto-${TARGET_BOARD_PLATFORM}-${KERNEL_VARIANT}.config" \
            > "${moto_fragment}" ||
            abort "Failed to generate ${moto_fragment}"
    fi

    if [[ ! -f "${product_bzl}" ]]; then
        {
            echo "# this is auto generated moto kernel product config"
            echo "mmi_product_name = \"${TARGET_PRODUCT}\""
            echo "mmi_product_type = \"${TARGET_PRODUCT}\""
        } > "${product_bzl}" ||
            abort "Failed to generate ${product_bzl}"
    fi
}

# Internal: resolve fragment file paths and honour DEBUG_BUILD flag
_resolve_fragments() {
    local paths=()
    for frag in "${CONFIG_FRAGMENTS[@]}"; do
        local fp="${KDIR}/${frag}"
        if [[ -f "${fp}" ]]; then
            paths+=("${fp}")
        else
            warn "Fragment not found, skipping: ${frag}"
        fi
    done
    if [[ "${DEBUG_BUILD:-0}" == "1" ]]; then
        local dbg="${KDIR}/${DEBUG_FRAGMENT}"
        if [[ -f "${dbg}" ]]; then
            paths+=("${dbg}")
            msg "Debug fragment included: ${DEBUG_FRAGMENT}"
        else
            warn "Debug fragment not found: ${DEBUG_FRAGMENT}"
        fi
    fi
    printf '%s\n' "${paths[@]}"
}

# Apply base defconfig and merge all config fragments
rgn() {
    step "Defconfig"
    local base_cfg="${KDIR}/arch/arm64/configs/${CONFIG}"
    [[ -f "${base_cfg}" ]] || abort "Base defconfig not found: ${base_cfg}"

    mkdir -p "${OUT_DIR}"
    _prepare_mmi_config
    mapfile -t frag_paths < <(_resolve_fragments)

    # Print the merge plan
    echo -e "    ${CYAN}Base    ${NC} : arch/arm64/configs/${CONFIG}"
    for frag in "${CONFIG_FRAGMENTS[@]}"; do
        echo -e "    ${CYAN}Fragment${NC} : ${frag}"
    done
    [[ "${DEBUG_BUILD:-0}" == "1" ]] &&
        echo -e "    ${CYAN}Debug   ${NC} : ${DEBUG_FRAGMENT}"

    msg "Running merge_config.sh -m -r -y"
    KCONFIG_CONFIG="${OUT_DIR}/.config" \
        "${KDIR}/scripts/kconfig/merge_config.sh" \
        -m -r -y \
        "${base_cfg}" \
        "${frag_paths[@]}" || abort "Config merge failed"

    run_make olddefconfig || abort "olddefconfig failed"
    ok "Config ready → ${OUT_DIR}/.config"
}

# Save the current generated .config back to the source tree
save_defconfig() {
    [[ -f "${OUT_DIR}/.config" ]] || abort "No .config found; run 'rgn' first"
    cp -p "${OUT_DIR}/.config" "${KDIR}/arch/arm64/configs/${CONFIG}" ||
        abort "Failed to save defconfig"
    ok "Saved → arch/arm64/configs/${CONFIG}"
}

# Run menuconfig then persist changes
mcfg() {
    rgn
    step "Menuconfig"
    run_make menuconfig || abort "menuconfig failed"
    save_defconfig
    ok "Config changes saved"
}

# Set Clang LTO mode: thin | full | none
lto() {
    local mode="${1:-}"
    [[ "${mode}" == "thin" || "${mode}" == "full" || "${mode}" == "none" ]] ||
        abort "lto: expected thin | full | none, got '${mode}'"
    local cfg="${KDIR}/arch/arm64/configs/${CONFIG}"
    [[ -f "${cfg}" ]] || abort "Missing ${cfg}"
    step "LTO → ${mode}"
    case "${mode}" in
        thin) "${KDIR}/scripts/config" --file "${cfg}" -e LTO_CLANG_THIN -d LTO_CLANG_FULL -d LTO_NONE ;;
        full) "${KDIR}/scripts/config" --file "${cfg}" -e LTO_CLANG_FULL -d LTO_CLANG_THIN -d LTO_NONE ;;
        none) "${KDIR}/scripts/config" --file "${cfg}" -d LTO_CLANG_FULL -d LTO_CLANG_THIN -e LTO_NONE ;;
    esac
    rgn
    ok "LTO set to ${mode}"
}

# Bump CONFIG_LOCALVERSION in the defconfig (e.g. --upr=r3)
upr() {
    local ver="${1:-}"
    [[ -n "${ver}" ]] || abort "upr: provide a version string (e.g. r2)"
    step "Bumping localversion → -${KNAME}-${ver}"
    "${KDIR}/scripts/config" \
        --file "${KDIR}/arch/arm64/configs/${CONFIG}" \
        --set-str CONFIG_LOCALVERSION "-${KNAME}-${ver}" ||
        abort "Failed to set localversion"
    rgn
    ok "Localversion → -${KNAME}-${ver}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §11  DEVICE TREE DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════
dtree() {
    step "Device-tree candidates (${CODENAME} / ${PLATFORM} / display)"
    local found=0 root pattern file
    for root in "${DTS_ROOTS[@]}"; do
        [[ -d "${KDIR}/${root}" ]] || continue
        for pattern in "${DISPLAY_DTS_GLOBS[@]}"; do
            while IFS= read -r file; do
                found=1
                printf '  %s\n' "${file#${KDIR}/}"
            done < <(find -L "${KDIR}/${root}" -type f -iname "${pattern}" 2>/dev/null | sort)
        done
    done
    if [[ -L "${KDIR}/arch/arm64/boot/dts/vendor" ]]; then
        msg "Vendor DTS link: arch/arm64/boot/dts/vendor -> $(readlink "${KDIR}/arch/arm64/boot/dts/vendor")"
    elif [[ -d "${KDIR}/arch/arm64/boot/dts/vendor" ]]; then
        msg "Vendor DTS directory: arch/arm64/boot/dts/vendor"
    else
        warn "arch/arm64/boot/dts/vendor is missing"
    fi

    ((found == 1)) || warn "No matching device-tree source files found in-tree."
}

# Internal: collect built DTB/DTBO into DIST_DIR/dtbs
_copy_dt_outputs() {
    mkdir -p "${DIST_DIR}/dtbs"
    if [[ -d "${OUT_DIR}/arch/arm64/boot/dts" ]]; then
        find "${OUT_DIR}/arch/arm64/boot/dts" \
            -type f \( -name '*.dtb' -o -name '*.dtbo' \) -print0 |
            xargs -0 -r -I{} cp -p {} "${DIST_DIR}/dtbs/" ||
            abort "Failed to copy DTB/DTBO files"
    fi
    find "${DIST_DIR}/dtbs" -type f \( -name '*.dtb' -o -name '*.dtbo' \) -print \
        2>/dev/null | sort > "${DIST_DIR}/device-trees.list" || true
    local n; n=$(wc -l < "${DIST_DIR}/device-trees.list" 2>/dev/null || echo 0)
    ok "${n} DTB/DTBO file(s) → ${DIST_DIR}/dtbs"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §12  MODULE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# Strip debug symbols from all .ko files in DIST_DIR/modules
_strip_modules() {
    local objcopy=""
    if command -v llvm-objcopy >/dev/null 2>&1; then
        objcopy="llvm-objcopy"
    elif command -v "${CROSS_COMPILE}objcopy" >/dev/null 2>&1; then
        objcopy="${CROSS_COMPILE}objcopy"
    fi
    if [[ -z "${objcopy}" ]]; then
        warn "No objcopy found; skipping debug-symbol stripping"
        return
    fi
    msg "Stripping debug symbols (${objcopy})"
    while IFS= read -r ko; do
        "${objcopy}" --strip-debug "${ko}" ||
            warn "Could not strip: $(basename "${ko}")"
    done < <(find "${DIST_DIR}/modules" -type f -name '*.ko' | sort)
}

# Copy installed modules to DIST_DIR/modules, optionally stripping them
_copy_modules() {
    mkdir -p "${DIST_DIR}/modules"
    find "${MODULES_INSTALL_DIR}" -type f -name '*.ko' -print0 2>/dev/null |
        xargs -0 -r -I{} cp -p {} "${DIST_DIR}/modules/" ||
        abort "Failed to copy modules to dist"
    [[ "${DEBUG}" == "0" ]] && _strip_modules
    find "${DIST_DIR}/modules" -type f -name '*.ko' -print | sort \
        > "${DIST_DIR}/modules.list"
    local n; n=$(wc -l < "${DIST_DIR}/modules.list" 2>/dev/null || echo 0)
    ok "${n} module(s) → ${DIST_DIR}/modules"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §13  KERNEL IMAGE BUILD
# ═══════════════════════════════════════════════════════════════════════════════
img() {
    requirements
    rgn
    banner
    dtree
    step "Building kernel image (Image / Image.gz / Image.lz4)"

    local start end elapsed
    start=$(date +%s)
    run_make -j"${PROCS}" Image Image.gz Image.lz4 2>&1 | tee "${LOG_FILE}"
    end=$(date +%s)
    elapsed=$((end - start))

    [[ -f "${OUT_DIR}/arch/arm64/boot/Image" ]] ||
        abort "Image not produced — check ${LOG_FILE}"

    mkdir -p "${DIST_DIR}"
    for img_file in Image Image.gz Image.lz4; do
        local src="${OUT_DIR}/arch/arm64/boot/${img_file}"
        if [[ -f "${src}" ]]; then
            cp -p "${src}" "${DIST_DIR}/"
            echo -e "    ${GREEN}[✓]${NC} ${img_file}"
        fi
    done

    ok "Kernel built in $((elapsed / 60))m $((elapsed % 60))s"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §14  DTB / DTBO BUILD
# ═══════════════════════════════════════════════════════════════════════════════
dtb() {
    requirements
    rgn

    step "Building DTBs / DTBO"
    dtree

    # ---------------------------------------------------------
    # Motorola MMI device-tree configuration
    # ---------------------------------------------------------
    local -a DT_CONFIG_FLAGS=(
        CONFIG_BUILD_ARM64_DT_OVERLAY=y
        CONFIG_MMI_DEVICE_DTBS=y
    )

    msg "DT configuration:"
    echo "    CONFIG_BUILD_ARM64_DT_OVERLAY=y"
    echo "    CONFIG_MMI_DEVICE_DTBS=y"

    # ---------------------------------------------------------
    # Build kernel DTBs + DTBOs
    #
    # KBUILD_MIXED_TREE matches the Motorola MMI build flow.
    # The two CONFIG_* values are explicitly enabled for this
    # DTB/DTBO build.
    # ---------------------------------------------------------
    msg "Building kernel DTBs / DTBOs"

    run_make -j"${PROCS}" \
        dtbs \
        KBUILD_MIXED_TREE="${DIST_DIR}" \
        "${DT_CONFIG_FLAGS[@]}" \
        2>&1 | tee -a "${LOG_FILE}" ||
        abort "DTB/DTBO build failed"

    # ---------------------------------------------------------
    # Collect individual .dtb / .dtbo files
    # ---------------------------------------------------------
    mkdir -p "${DIST_DIR}"
    _copy_dt_outputs

    # ---------------------------------------------------------
    # dtbo.img is optional.
    # Some Qualcomm trees generate individual .dtbo files
    # while the Android/OEM build creates dtbo.img later.
    # ---------------------------------------------------------
    local dtbo_candidates=(
        "${OUT_DIR}/arch/arm64/boot/dtbo.img"
        "${DIST_DIR}/dtbo.img"
        "${DIST_DIR}/dtbs/dtbo.img"
        "${OUT_DIR}/dtbo.img"
    )

    local dtbo_found=""
    local candidate

    for candidate in "${dtbo_candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            dtbo_found="${candidate}"
            break
        fi
    done

    if [[ -n "${dtbo_found}" ]]; then
        if [[ "${dtbo_found}" != "${DIST_DIR}/dtbo.img" ]]; then
            cp -p "${dtbo_found}" "${DIST_DIR}/dtbo.img" ||
                abort "Failed to stage dtbo.img"
        fi

        ok "DTBO image → ${DIST_DIR}/dtbo.img"
    else
        warn "No dtbo.img generated; individual DTBO blobs are available in ${DIST_DIR}/dtbs"
    fi
}

# Build the Motorola MMI out-of-tree modules that are present in the tree.
build_mmi_modules() {
    local -a mmi_modules=(
        "../sm7435-modules/motorola/drivers/moto_reboot_reason"
        "../sm7435-modules/motorola/drivers/watchdogtest"
        "../sm7435-modules/motorola/drivers/wlan_antenna"
        "../sm7435-modules/motorola/drivers/misc/mmi_sys_temp"
        "../sm7435-modules/motorola/drivers/mmi_annotate"
        "../sm7435-modules/motorola/drivers/moto_binder"
        "../sm7435-modules/motorola/drivers/power/bm_adsp_ulog"
        "../sm7435-modules/motorola/drivers/sensors"
        "../sm7435-modules/motorola/drivers/mmi_relay"
        "../sm7435-modules/motorola/drivers/moto_mmap_fault"
        "../sm7435-modules/motorola/drivers/moto_sched"
        "../sm7435-modules/motorola/drivers/moto_mm"
        "../sm7435-modules/motorola/drivers/regulator/wl2866d"
        "../sm7435-modules/motorola/drivers/moto_f_usbnet"
        "../sm7435-modules/motorola/drivers/misc/utag"
        "../sm7435-modules/motorola/drivers/moto_netopt/con_dfpar"
        "../sm7435-modules/motorola/drivers/moto_swap"
        "../sm7435-modules/motorola/drivers/mmi_info"
        "../sm7435-modules/motorola/drivers/input/misc/goodix_fod_mmi"
        "../sm7435-modules/motorola/drivers/input/misc/anc_fps_mmi"
        "../sm7435-modules/motorola/drivers/misc/sx937x"
        "../sm7435-modules/motorola/drivers/power/mmi_charger"
        "../sm7435-modules/motorola/drivers/power/qpnp_adaptive_charge"
        "../sm7435-modules/motorola/drivers/power/qti_glink_charger"
        "../sm7435-modules/motorola/drivers/input/touchscreen/touchscreen_mmi"
        "../sm7435-modules/motorola/drivers/misc/awinic/sarsensor"
        "../sm7435-modules/motorola/drivers/input/touchscreen/goodix_berlin_mmi"
        "../sm7435-modules/motorola/drivers/input/touchscreen/focaltech_touch_v3_4"
    )

    local -a mmi_args=(
        ""
        "MODULE_KERNEL_VERSION=5.15 CONFIG_SYSFS_IMPORT_REMOVE_SELF=y"
        ""
        "MODULE_KERNEL_VERSION=5.15"
        ""
        ""
        "CONFIG_WIRELESS_CPS4035B=y"
        ""
        ""
        "KCFLAGS=-DTUNE_MMAP_READAROUND"
        "CONFIG_MOTO_MUTEX_INHERIT=y CONFIG_MOTO_RWSEM_INHERIT=y"
        ""
        "MODULE_KERNEL_VERSION=5.15 CONFIG_SGM4154X_CHARGER_NAME=sgm41516D"
        ""
        ""
        ""
        "CONFIG_HYBRIDSWAP_ZRAM=y CONFIG_HYBRIDSWAP=y CONFIG_HYBRIDSWAP_SWAPD=y CONFIG_HYBRIDSWAP_CORE=y"
        ""
        "CONFIG_INPUT_MISC_FPC1020_SAVE_TO_CLASS_DEVICE=y"
        "TARGET_BUILD_VARIANT=user"
        "MODULE_KERNEL_VERSION=5.15 CONFIG_SX937X_USB_CAL=y CONFIG_SX937X_POWER_SUPPLY_ONLINE=y"
        "MODULE_KERNEL_VERSION=5.15 CONFIG_ATL_NM40_712MAH_BATTERY_PROFILE=y"
        "MODULE_KERNEL_VERSION=5.15 CONFIG_USE_MMI_CHARGER=y"
        "CONFIG_WIRELESS_CPS4035B=y"
        "CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=y CONFIG_BOARD_USES_DOUBLE_TAP_CTRL=y CONFIG_BUILD_FOR_ANDROID_V=y"
        "CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_AW96XX_POWER_SUPPLY_ONLINE=y"
        "CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=y CONFIG_GTP_FOD=y CONFIG_GTP_LAST_TIME=y CONFIG_BOARD_USES_DOUBLE_TAP_CTRL=y CONFIG_BUILD_KERNEL_VARIANT_PERF=y"
        "CONFIG_INPUT_CHIPONE_0FLASH_MMI_ENABLE_DOUBLE_TAP=y CONFIG_GTP_LAST_TIME=y CONFIG_BOARD_USES_DOUBLE_TAP_CTRL=y CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_INPUT_TOUCHSCREEN_MMI=y MODULE_KERNEL_VERSION=5.15 CONFIG_INPUT_FOCALTECH_0FLASH_MMI_IC_NAME=ft3683g CONFIG_BOARD_USES_DOUBLE_TAP_CTRL=y CONFIG_FOCALTECH_LAST_TIME=y CONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=y CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_INPUT_FOCALTECH_V3_MMI_IC_NAME=ft3683g CONFIG_INPUT_FOCALTECH_V3_MMI_ENABLE_DOUBLE_TAP=y CONFIG_FTS_DOUBLE_TAP_CONTROL=y CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=y CONFIG_FTS_COMPATIBLE_WITH_GKI=y CONFIG_FTS_VDD_GPIO_CONTROL=y CONFIG_FTS_LAST_TIME=y CONFIG_FTS_INPUT_ID=y CONFIG_ENABLE_FTS_PALM_CANCEL=y CONFIG_INPUT_FOCAL_IC_NAME=ft3683g CONFIG_INPUT_FOCALTECH_V3_MMI_ENABLE_DOUBLE_TAP=y CONFIG_FTS_DOUBLE_TAP_CONTROL=y CONFIG_INPUT_TOUCHSCREEN_MMI=y CONFIG_DRM_PANEL_EVENT_NOTIFICATIONS=y CONFIG_FTS_COMPATIBLE_WITH_GKI=y CONFIG_SUPPORT_FTS_HIRES_X=16 CONFIG_FTS_VDD_GPIO_CONTROL=y CONFIG_FTS_LAST_TIME=y CONFIG_FTS_INPUT_ID=y CONFIG_FTS_GAME_MODE_EN=y CONFIG_FOCALTECH_REPORT_PRESSURE_DISABLE=y CONFIG_BUILD_FOR_ANDROID_V=y"
    )

    local i module_dir
    mkdir -p "${DIST_DIR}/modules"

    for i in "${!mmi_modules[@]}"; do
        module_dir="${mmi_modules[$i]}"

        if [[ ! -d "${module_dir}" ]]; then
            warn "MMI module not found, skipping: ${module_dir}"
            continue
        fi

        msg "Building MMI module: ${module_dir}"
        local -a extra_args=()
        if [[ -n "${mmi_args[$i]}" ]]; then
            IFS=' ' read -r -a extra_args <<< "${mmi_args[$i]}"
        fi

        make "${MAKE_FLAGS[@]}" -j"${PROCS}" \
            -C "${KDIR}" \
            M="${module_dir}" \
            KERNEL_SRC="${KDIR}" \
            KBUILD_MIXED_TREE="${DIST_DIR}" \
            "${extra_args[@]}" ||
            abort "MMI module build failed: ${module_dir}"

        find "${module_dir}" -type f -name '*.ko' -print0 2>/dev/null |
            xargs -0 -r -I{} cp -p {} "${DIST_DIR}/modules/" ||
            abort "Failed to copy MMI module: ${module_dir}"
    done

    find "${DIST_DIR}/modules" -type f -name '*.ko' -print | sort \
        > "${DIST_DIR}/modules.list"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §15  MODULE BUILD
# ═══════════════════════════════════════════════════════════════════════════════
mod() {
    requirements
    rgn
    step "Building kernel modules"

    run_make -j"${PROCS}" modules 2>&1 | tee -a "${LOG_FILE}" ||
        abort "Module build failed"

    msg "Installing modules → ${MODULES_INSTALL_DIR}"
    rm -rf "${MODULES_INSTALL_DIR}"
    run_make INSTALL_MOD_PATH="${MODULES_INSTALL_DIR}" modules_install ||
        abort "Module install failed"

    mkdir -p "${DIST_DIR}"
    _copy_modules

    # Motorola's OEM build prepares the external-module environment before
    # compiling Moto DLKM modules. In the OEM build, Module.symvers is copied
    # from the kernel distribution output into OUT_DIR before modules_prepare.
    msg "Preparing external-module build environment"

    [[ -f "${OUT_DIR}/Module.symvers" ]] ||
        abort "Missing ${OUT_DIR}/Module.symvers — kernel Module.symvers was not generated"

    cp -p "${OUT_DIR}/Module.symvers" "${DIST_DIR}/Module.symvers" ||
        abort "Failed to stage Module.symvers in ${DIST_DIR}"

    run_make olddefconfig ||
        abort "olddefconfig failed for external modules"

    run_make modules_prepare ||
        abort "modules_prepare failed for external modules"

    build_mmi_modules
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §16  UAPI HEADERS BUILD
# ═══════════════════════════════════════════════════════════════════════════════
hdr() {
    requirements
    rgn
    step "Building UAPI kernel headers"

    local hdr_dir="${OUT_DIR}/kernel_uapi_headers"
    run_make -j"${PROCS}" \
        INSTALL_HDR_PATH="${hdr_dir}/usr" \
        headers_install || abort "UAPI headers build failed"

    find "${hdr_dir}" '(' -name '..install.cmd' -o -name '.install' ')' -exec rm '{}' +
    tar -czf "${OUT_DIR}/kernel-uapi-headers.tar.gz" \
        --directory="${hdr_dir}" usr/ || abort "Failed to create UAPI tarball"

    mkdir -p "${DIST_DIR}"
    cp -p "${OUT_DIR}/kernel-uapi-headers.tar.gz" "${DIST_DIR}/"
    ok "UAPI headers → ${DIST_DIR}/kernel-uapi-headers.tar.gz"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §17  FULL BUILD (image + modules + DTBs)
# ═══════════════════════════════════════════════════════════════════════════════
all() {
    local start end elapsed
    start=$(date +%s)
    step "Full build — image + DTBs + modules"

    # Match the MMI build order: kernel image first, then device-tree
    # artifacts, then external/module builds.
    img
    dtb
    mod

    end=$(date +%s)
    elapsed=$((end - start))
    ok "Full build complete in $((elapsed / 60))m $((elapsed % 60))s"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §18  PACKAGING — AnyKernel3 ZIP
# ═══════════════════════════════════════════════════════════════════════════════
mkzip() {
    step "Building AnyKernel3 zip"

    # Auto-clone if requested and not already present
    if [[ ! -d "${AK3}" ]]; then
        if [[ "${FETCH_AK3:-0}" == "1" ]]; then
            msg "Cloning AnyKernel3 → ${AK3}"
            git clone --depth=1 "${AK3_REPO}" "${AK3}" ||
                abort "Failed to clone AnyKernel3 from ${AK3_REPO}"
        else
            abort "AnyKernel3 not found at '${AK3}'.\nSet FETCH_AK3=1 to auto-clone or place it manually."
        fi
    fi

    [[ -f "${DIST_DIR}/Image" || -f "${DIST_DIR}/Image.gz" ]] ||
        abort "No kernel image in ${DIST_DIR}; run 'img' first"

    msg "Staging files into AnyKernel3"
    rm -f "${AK3}"/{Image,Image.gz,Image.lz4,dtb,dtbo.img} 2>/dev/null || true
    rm -rf "${AK3}/modules"

    # Kernel images
    for img_file in Image Image.gz Image.lz4; do
        [[ -f "${DIST_DIR}/${img_file}" ]] && cp -p "${DIST_DIR}/${img_file}" "${AK3}/"
    done

    # DTBO
    [[ -f "${DIST_DIR}/dtbo.img" ]] && cp -p "${DIST_DIR}/dtbo.img" "${AK3}/"

    # DTB — prefer device-specific blob, fall back to first parrot DTB
    local dtb_file=""
    dtb_file="$(find "${DIST_DIR}/dtbs" -type f \
        \( -iname "*${CODENAME}*.dtb" -o -iname '*cusco*.dtb' \
           -o -iname "*${PLATFORM}*.dtb" \) \
        2>/dev/null | sort | head -n 1 || true)"
    if [[ -n "${dtb_file}" ]]; then
        cat "${dtb_file}" > "${AK3}/dtb" || abort "Failed to stage DTB"
        msg "DTB: $(basename "${dtb_file}")"
    else
        warn "No device-specific DTB found in ${DIST_DIR}/dtbs"
    fi

    # Modules
    if [[ -d "${DIST_DIR}/modules" ]]; then
        mkdir -p "${AK3}/modules/vendor_dlkm/lib/modules"
        find "${DIST_DIR}/modules" -maxdepth 1 -name '*.ko' \
            -exec cp -p {} "${AK3}/modules/vendor_dlkm/lib/modules/" \; 2>/dev/null || true
    fi

    # Create the zip
    local zip_out="${DIST_DIR}/${ZIP_NAME}.zip"
    (cd "${AK3}" && zip -r9 "${zip_out}" . -x '.git*' '*.zip' 'README*') ||
        abort "zip creation failed"

    local zip_size md5
    zip_size="$(du -sh "${zip_out}" | cut -f1)"
    md5="$(md5sum "${zip_out}" | cut -d' ' -f1)"

    ok "Zip ready!"
    echo ""
    echo -e "  ${BOLD}File ${NC}: ${CYAN}${ZIP_NAME}.zip${NC}"
    echo -e "  ${BOLD}Size ${NC}: ${zip_size}"
    echo -e "  ${BOLD}MD5  ${NC}: ${md5}"
    echo -e "  ${BOLD}Path ${NC}: ${zip_out}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §19  UTILITY COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

# Build a specific object / driver directory
obj() {
    local target="${1:-}"
    [[ -n "${target}" ]] || abort "Usage: ./build.sh --obj=drivers/foo/bar.o"
    rgn
    step "Building: ${target}"
    run_make -j"${PROCS}" "${target}" || abort "Failed to build ${target}"
    ok "Built ${target}"
}

# Build an out-of-tree external module directory
extmod() {
    local module_dir="${1:-}"
    [[ -d "${module_dir}" ]] || abort "External module directory not found: ${module_dir}"
    rgn
    step "External module: ${module_dir}"
    run_make -j"${PROCS}" modules_prepare || abort "modules_prepare failed"
    run_make -j"${PROCS}" M="${module_dir}" modules ||
        abort "External module build failed: ${module_dir}"
    ok "Built external module: ${module_dir}"
}

# Remove all generated output
clean() {
    step "Clean"
    rm -rf "${OUT_DIR}" "${LOG_FILE}"
    if [[ -d "${AK3}" ]]; then
        rm -f "${AK3}"/{Image,Image.gz,Image.lz4,dtb,dtbo.img,*.zip} 2>/dev/null || true
        rm -rf "${AK3}/modules"
    fi
    ok "Clean complete"
}

# Sync companion repositories (sm7435-modules, sm7435-devicetrees)
repos() {
    step "Syncing companion repositories"

    _clone_or_update() {
        local url="$1" dir="$2" branch="$3"
        if [[ -d "${dir}/.git" ]]; then
            msg "Updating $(basename "${dir}")"
            git -C "${dir}" fetch --depth=1 origin "${branch}" 2>/dev/null &&
                git -C "${dir}" checkout -B "${branch}" FETCH_HEAD 2>/dev/null || true
        else
            msg "Cloning $(basename "${dir}") [${branch}]"
            git clone --depth=1 -b "${branch}" "${url}" "${dir}" ||
                abort "Failed to clone ${url}"
        fi
        ok "$(basename "${dir}") ready"
    }

    _clone_or_update "${MODULES_REPO}"     "${MODULES_DIR}"     "${KBRANCH}"
    _clone_or_update "${DEVICETREES_REPO}" "${DEVICETREES_DIR}" "${KBRANCH}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §20  HELP MENU
# ═══════════════════════════════════════════════════════════════════════════════
helpmenu() {
    cat <<HELP
${BOLD}Usage:${NC} bash $0 <command> [command...]

${BOLD}─── Build ───────────────────────────────────────────────────────${NC}
  all         Full build: image + modules + DTBs
  img         Build kernel image (Image / Image.gz / Image.lz4)
  dtb         Build all DTBs / DTBO blobs (dtbo.img optional)
  mod         Build and install all configured modules
  hdr         Build UAPI kernel headers tarball
  mkzip       Package dist artifacts into AnyKernel3 zip

${BOLD}─── Config ──────────────────────────────────────────────────────${NC}
  rgn         Apply defconfig + merge all fragments
  mcfg        Run menuconfig and save changes
  --lto=      Set LTO mode: thin | full | none
  --upr=      Bump kernel localversion (e.g. --upr=r2)

${BOLD}─── Utilities ───────────────────────────────────────────────────${NC}
  dtree       Show device-tree source file candidates
  repos       Sync companion repos (modules, devicetrees)
  clean       Remove all build outputs and logs
  --obj=      Build a specific object or directory
  --extmod=   Build an external module directory
  help        Show this menu

${BOLD}─── Environment overrides ───────────────────────────────────────${NC}
  CLANG_DIR   Path to prebuilt clang directory
  OUT_DIR     Build output directory     [${OUT_DIR}]
  DIST_DIR    Final artifacts directory  [${DIST_DIR}]
  AK3         AnyKernel3 directory       [${AK3}]
  PROCS       Parallel job count         [${PROCS}]
  DEBUG       1 = keep module debug symbols [${DEBUG}]
  DEBUG_BUILD 1 = merge debug config fragment
  FETCH_AK3   1 = auto-clone AnyKernel3
  NO_COLOR    Set to disable colour output

${BOLD}─── Examples ────────────────────────────────────────────────────${NC}
  bash $0 all
  bash $0 img dtb mod mkzip
  bash $0 --lto=thin img mkzip
  bash $0 --upr=r3 img mkzip
  PROCS=16 bash $0 all
  DEBUG_BUILD=1 FETCH_AK3=1 bash $0 all mkzip
HELP
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §21  INTERACTIVE DIALOG MENU
# ═══════════════════════════════════════════════════════════════════════════════
ndialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        warn "'dialog' is not installed — run with arguments instead"
        helpmenu
        return
    fi

    local BACKTITLE="${KNAME} Kernel Builder — ${DEVICE} [${CODENAME}]"
    local TITLE="${KNAME} Kernel Builder"

    local OPTIONS=(
        1  "Full build            (image + DTBs + modules)"
        2  "Build kernel image    (Image / Image.gz / Image.lz4)"
        3  "Build DTBs / DTBO"
        4  "Build modules"
        5  "Build UAPI headers"
        6  "Build AnyKernel3 zip"
        7  "Full build + zip      (all-in-one)"
        8  "── Config ──────────────────────────────"
        8  "Apply / regenerate defconfig"
        9  "Open menuconfig"
        10 "Set LTO mode          (thin | full | none)"
        11 "Bump localversion"
        12 "── Utilities ───────────────────────────"
        12 "Show device-tree candidates"
        13 "Sync companion repos"
        14 "Build specific object"
        15 "Build external module"
        16 "Clean all outputs"
        17 "Exit"
    )

    local CHOICE
    CHOICE=$(dialog --clear \
        --backtitle "${BACKTITLE}" \
        --title " ${TITLE} " \
        --menu "Select an action:" 26 62 18 \
        1  "Full build  (image + DTBs + modules)" \
        2  "Build kernel image" \
        3  "Build DTBs / DTBO" \
        4  "Build modules" \
        5  "Build UAPI headers" \
        6  "Build AnyKernel3 zip" \
        7  "Full build + zip  (all-in-one)" \
        8  "Apply / regenerate defconfig" \
        9  "Open menuconfig" \
        10 "Set LTO mode" \
        11 "Bump localversion" \
        12 "Show device-tree candidates" \
        13 "Sync companion repos" \
        14 "Build specific object" \
        15 "Build external module" \
        16 "Clean all outputs" \
        17 "Exit" \
        2>&1 >/dev/tty)
    clear

    _pause() {
        echo -ne "\n${BOLD}Press ENTER to continue, or q to quit: ${NC}"
        local _r; read -r _r
        [[ "${_r}" == "q" ]] && exit 0
        clear; ndialog
    }

    _input() {
        local prompt="$1" tmpf
        tmpf="$(mktemp)"
        dialog --inputbox "${prompt}" 8 56 2>"${tmpf}" >/dev/tty
        local val; val="$(cat "${tmpf}")"; rm -f "${tmpf}"
        printf '%s' "${val}"
    }

    case "${CHOICE}" in
        1)  all;             _pause ;;
        2)  img;             _pause ;;
        3)  dtb;             _pause ;;
        4)  mod;             _pause ;;
        5)  hdr;             _pause ;;
        6)  mkzip;           _pause ;;
        7)  all; mkzip;      _pause ;;
        8)  rgn;             _pause ;;
        9)  mcfg;            _pause ;;
        10)
            local lm; lm="$(_input "LTO mode  (thin | full | none):")"
            [[ -z "${lm}" ]] && { clear; abort "No input provided"; }
            clear; lto "${lm}"; _pause
            ;;
        11)
            local vv; vv="$(_input "Version string  (e.g. r2):")"
            [[ -z "${vv}" ]] && { clear; abort "No input provided"; }
            clear; upr "${vv}"; _pause
            ;;
        12) dtree;           _pause ;;
        13) repos;           _pause ;;
        14)
            local ob; ob="$(_input "Object path  (e.g. drivers/android/binder.o):")"
            [[ -z "${ob}" ]] && { clear; abort "No input provided"; }
            clear; obj "${ob}"; _pause
            ;;
        15)
            local ex; ex="$(_input "External module path:")"
            [[ -z "${ex}" ]] && { clear; abort "No input provided"; }
            clear; extmod "${ex}"; _pause
            ;;
        16) clean;           _pause ;;
        17) echo -e "\n${BOLD}Exiting...${NC}"; sleep 1; exit 0 ;;
        *)  clear; ndialog ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
#  §22  ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════
if [[ $# -eq 0 ]]; then
    banner
    ndialog
    exit 0
fi

for arg in "$@"; do
    case "${arg}" in
        all|build)        all    ;;
        img|image)        img    ;;
        dtb|dtbs)         dtb    ;;
        mod|modules)      mod    ;;
        hdr|headers)      hdr    ;;
        mkzip|zip)        mkzip  ;;
        mcfg|menuconfig)  mcfg   ;;
        rgn|defconfig)    rgn    ;;
        dtree)            dtree  ;;
        repos)            repos  ;;
        clean)            clean  ;;
        help|-h|--help)   helpmenu; exit 0 ;;
        --obj=*)          obj    "${arg#*=}" ;;
        --extmod=*)       extmod "${arg#*=}" ;;
        --lto=*)          lto    "${arg#*=}" ;;
        --upr=*)          upr    "${arg#*=}" ;;
        *)                helpmenu; abort "Unknown argument: ${arg}" ;;
    esac
done