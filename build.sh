#!/bin/bash
# High-Performance Kernel 6.6 Unified Build & Packaging Script
# Set up to run directly from your main kernel root folder.

# --- ANSI Terminal Styling ---
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
CYAN="\e[1;36m"
WHITE="\e[1;37m"
NC="\e[0m"

# --- Project Metadata ---
export DEVICE="Motorola Cuscoi"
export CODENAME="cuscoi"
export BUILDER="HELLINFIX"
export DEFCONFIG="vendor/cuscoi_defconfig"
export ZIP_NAME="NebulaPrime-${CODENAME}-$(date +%Y%m%d-%H%M).zip"

# --- Paths & Workspace Structuring ---
export KDIR=$(pwd)
export OUT_DIR="$KDIR/out"
export DIST_DIR="$KDIR/dist"
export TOOLCHAIN_DIR="$KDIR/../toolchains"
export CLANG_VERSION="clang-r522817"
export CLANG_DIR="$TOOLCHAIN_DIR/$CLANG_VERSION"

# Sibling Component Mappings
DEVICETREE_URL="https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-devicetrees"
MODULES_URL="https://github.com/Moto-SM7435-Devs/android_kernel_motorola_sm7435-modules"
ANYKERNEL_URL="https://github.com/Moto-SM7435-Devs/AnyKernel3"

DEVICETREE_PATH="vendor/qcom/opensource/devicetrees"
MODULES_PATH="vendor/qcom/opensource/sm7435-modules"
ANYKERNEL_PATH="anykernel"

# Core threading optimization
export PROCS=$(nproc --all)

# --- Global Compiler Flags (Pure LLVM for Kernel 6.6) ---
export ARCH=arm64
export SUBARCH=arm64
export PATH="$CLANG_DIR/bin:$PATH"
export LLVM=1
export LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-

# --- Structural Functions ---

# Utility component checker
check_deps() {
    echo -e "${BLUE}[*] Checking vital system utilities...${NC}"
    if ! hash bc bison flex git make rsync curl zip 2>/dev/null; then
        echo -e "${RED}[✗] Core compilation packages missing. Installing via apt...${NC}"
        sudo apt-get update && sudo apt-get install -y \
            bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
            git gnupg gperf libelf-dev liblz4-tool libncurses5-dev libssl-dev \
            libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc \
            zip zlib1g-dev python3 python3-pip
    fi
}

# Auto-fetch dependencies and environment mappings
setup_workspace() {
    mkdir -p vendor/qcom/opensource
    mkdir -p "$DIST_DIR"

    if [ ! -d "$DEVICETREE_PATH/.git" ]; then
        echo -e "${YELLOW}[*] Devicetrees mapping missing. Fetching source...${NC}"
        git clone "$DEVICETREE_URL" "$DEVICETREE_PATH"
    fi

    if [ ! -d "$MODULES_PATH/.git" ]; then
        echo -e "${YELLOW}[*] External vendor modules missing. Fetching source...${NC}"
        git clone "$MODULES_URL" "$MODULES_PATH"
    fi

    if [ ! -d "$ANYKERNEL_PATH/.git" ]; then
        echo -e "${YELLOW}[*] AnyKernel3 workspace missing. Fetching repository...${NC}"
        git clone "$ANYKERNEL_URL" "$ANYKERNEL_PATH"
    fi

    if [ ! -d "$CLANG_DIR" ]; then
        echo -e "${YELLOW}[*] Target Clang missing. Downloading $CLANG_VERSION from upstream...${NC}"
        mkdir -p "$CLANG_DIR"
        curl -Lo "$TOOLCHAIN_DIR/clang.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${CLANG_VERSION}.tar.gz"
        tar -xzf "$TOOLCHAIN_DIR/clang.tar.gz" -C "$CLANG_DIR"
        rm "$TOOLCHAIN_DIR/clang.tar.gz"
    fi
    
    export KBUILD_COMPILER_STRING=$("$CLANG_DIR/bin/clang" --version | head -n 1)
}

# Source Sanitization 
clean_sources() {
    echo -e "\n${YELLOW}[*] Cleaning out/ build directories and caching targets...${NC}"
    rm -rf "$OUT_DIR" "$DIST_DIR"
    rm -f "$ANYKERNEL_PATH/Image" "$ANYKERNEL_PATH/dtb"
    rm -rf "$ANYKERNEL_PATH/modules"
    echo -e "${GREEN}[✓] Workspace cleared successfully.${NC}"
}

# Configuration Handler (Direct Defconfig Initialization)
generate_config() {
    echo -e "${GREEN}[+] Initializing Defconfig Layout for Cuscoi...${NC}"
    
    if [ ! -f "arch/arm64/configs/$DEFCONFIG" ]; then
        echo -e "${RED}[✗] Target defconfig path missing: arch/arm64/configs/$DEFCONFIG${NC}"
        exit 1
    fi

    mkdir -p "$OUT_DIR"

    echo -e "${CYAN}[*] Applying Unified Defconfig ($DEFCONFIG)...${NC}"
    make O="$OUT_DIR" "$DEFCONFIG"

    echo -e "${GREEN}[✓] Defconfig successfully constructed inside /out!${NC}"
}

# Interactive configuration tweaking 
menu_config() {
    check_deps
    setup_workspace
    generate_config
    echo -e "${YELLOW}[*] Launching interactive menuconfig console...${NC}"
    make O="$OUT_DIR" menuconfig
    
    # Save the modified config back to the target config for permanence
    cp -rf "$OUT_DIR/.config" "arch/arm64/configs/$DEFCONFIG"
    echo -e "${GREEN}[✓] Modifications successfully saved into $DEFCONFIG!${NC}"
}

# Core Compilation Pipeline
build_artifacts() {
    set -e # Crash function if intermediate commands break
    
    check_deps
    setup_workspace
    generate_config

    # Output Build Parameter Sheet
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${CYAN}  KERNEL COMPILATION DASHBOARD                     ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${WHITE}  Target Device  : ${DEVICE} [${CODENAME}]${NC}"
    echo -e "${WHITE}  Build User     : ${BUILDER}@$(hostname)${NC}"
    echo -e "${WHITE}  Thread Cores   : ${PROCS} Processors${NC}"
    echo -e "${WHITE}  Compiler Info  : ${KBUILD_COMPILER_STRING}${NC}"
    echo -e "${WHITE}  Git Branch     : $(git rev-parse --abbrev-ref HEAD)${NC}"
    echo -e "${WHITE}  Last Commit    : $(git log -1 --format=\"%h : %s\" 2>/dev/null)${NC}"
    echo -e "${BLUE}===================================================${NC}"

    echo -e "${YELLOW}[*] Compiling core Kernel Image & System DTBs...${NC}"
    make -j"$PROCS" O="$OUT_DIR"

    # Scans for out-of-tree sub-modules containing a Makefile or Kbuild layout up to 2 layers deep
    if [ -d "$MODULES_PATH" ]; then
        echo -e "${YELLOW}[*] Detecting and building out-of-tree vendor module subgroups...${NC}"
        
        find "$KDIR/$MODULES_PATH" -maxdepth 2 -type f \( -name "Makefile" -o -name "Kbuild" \) | while read -r sub_makefile; do
            MOD_SUBDIR=$(dirname "$sub_makefile")
            echo -e "${CYAN}[*] Compiling module driver: $(basename "$MOD_SUBDIR")${NC}"
            make -j"$PROCS" O="$OUT_DIR" M="$MOD_SUBDIR" modules
        done
    fi

    echo -e "${YELLOW}[*] Populating deployment package folder...${NC}"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$DIST_DIR/"
    if [ -d "$OUT_DIR/arch/arm64/boot/dts" ]; then
        find "$OUT_DIR/arch/arm64/boot/dts/" -name "*.dtb" -exec cp {} "$DIST_DIR/" \;
        find "$OUT_DIR/arch/arm64/boot/dts/" -name "*.dtbo" -exec cp {} "$DIST_DIR/" \;
    fi
    
    # Sweep out/ and source trees to backup objects to /dist
    find "$OUT_DIR" -name "*.ko" -exec cp {} "$DIST_DIR/" \; 2>/dev/null
    find "$KDIR/$MODULES_PATH" -name "*.ko" -exec cp {} "$DIST_DIR/" \; 2>/dev/null

    echo -e "${BLUE}===================================================${NC}"
    echo -e "${CYAN}  ANYKERNEL3 AUTOMATED PACKAGING                   ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${YELLOW}[*] Cleaning previous staging files from AnyKernel workspace...${NC}"
    rm -f "$ANYKERNEL_PATH/Image" "$ANYKERNEL_PATH/dtb"
    rm -rf "$ANYKERNEL_PATH/modules"

    echo -e "${YELLOW}[*] Dropping newly built kernel core Image...${NC}"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$ANYKERNEL_PATH/"

    echo -e "${YELLOW}[*] Harvesting device hardware DTB component...${NC}"
    # Resolves and renames the matching target hardware file to 'dtb'
    if ! find "$OUT_DIR/arch/arm64/boot/dts/" -name "*cuscoi*.dtb" -exec cp {} "$ANYKERNEL_PATH/dtb" \; 2>/dev/null; then
        find "$OUT_DIR/arch/arm64/boot/dts/" -name "*parrot*.dtb" -exec cp {} "$ANYKERNEL_PATH/dtb" \; 2>/dev/null
    fi

    echo -e "${YELLOW}[*] Aligning compiled vendor modules to vendor_dlkm layout...${NC}"
    mkdir -p "$ANYKERNEL_PATH/modules/vendor_dlkm/lib/modules/"
    find "$DIST_DIR" -name "*.ko" -exec cp {} "$ANYKERNEL_PATH/modules/vendor_dlkm/lib/modules/" \;

    echo -e "${GREEN}[+] Packaging flashable output distribution: $ZIP_NAME${NC}"
    
    # Shift execution to internal zip scope
    cd "$ANYKERNEL_PATH"
    zip -r9 "$DIST_DIR/$ZIP_NAME" * -x .git* README.md *placeholder
    cd "$KDIR"
}

# --- Runtime Execution Interface Menu ---
case "$1" in
    "clean")
        clean_sources
        ;;
    "menuconfig")
        menu_config
        ;;
    *)
        # Default fallback: Execute whole compilation matrix with tracking log
        BUILD_START=$(date +"%s")
        
        # Open pipeline capture block
        build_artifacts 2>&1 | tee build.log
        
        # Verify result status utilizing PIPESTATUS array mapping
        BUILD_RESULT=${PIPESTATUS[0]}
        BUILD_END=$(date +"%s")
        DIFF=$((BUILD_END - BUILD_START))

        echo ""
        if [ $BUILD_RESULT -eq 0 ]; then
            echo -e "${GREEN}***************************************************${NC}"
            echo -e "${GREEN}  SUCCESS: Kernel Compilation & Packaging Completed!${NC}"
            echo -e "${GREEN}  Total Build Duration: $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s).${NC}"
            echo -e "${GREEN}  Flashable Zip Ready Inside: /dist/${ZIP_NAME}     ${NC}"
            echo -e "${GREEN}***************************************************${NC}"
            exit 0
        else
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            echo -e "${RED}  CRITICAL ERROR: Build execution terminated!      ${NC}"
            echo -e "${RED}  Total Time Elapsed: $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s).${NC}"
            echo -e "${RED}  Check terminal errors or parse 'build.log'.      ${NC}"
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            exit $BUILD_RESULT
        fi
        ;;
esac
