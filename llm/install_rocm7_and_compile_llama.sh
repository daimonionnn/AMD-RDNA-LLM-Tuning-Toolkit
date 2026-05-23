#!/usr/bin/env bash
set -euo pipefail

# ================================================================
#  ROCm Installation & llama.cpp (HIP) Build Script
#  Supports Ubuntu 22.04, 24.04, 25.10 (and other modern distros)
#  GPU: AMD Radeon AI PRO R9700 / RX 9070 (gfx1201, RDNA 4 / Navi 48)
# ================================================================
#
#  INSTALLATION METHOD OPTIONS:
#
#  METHOD 1 (default): TheRock pip — community ROCm nightly via pip.
#    - Works on ANY Linux distro, no OS version check.
#    - Full gfx1201 / RDNA4 support (ROCm 7.x nightly).
#    - Uses your existing amdgpu kernel driver (already in kernel 6.12+).
#    - ROCm is installed into a Python venv: ./rocm-venv/
#    - Recommended for Ubuntu 25.10 / 25.04 / 24.10 users.
#    Reference: https://github.com/ROCm/TheRock/blob/main/RELEASES.md
#
#  METHOD 2: AMD official 7.2.3 apt repo (noble packages on questing).
#    - Manually adds AMD's Ubuntu 24.04 (noble) repo to apt sources.
#    - Bypasses amdgpu-install codename check entirely.
#    - Packages are ABI-compatible with Ubuntu 25.x.
#    - Requires sudo and a REBOOT.
#    - Official stable build but not officially supported on Ubuntu 25.x.
#    Usage: METHOD=2 ./install_rocm7_and_compile_llama.sh
#
#  METHOD 3: TheRock nightly native .deb packages.
#    - Adds the nightly TheRock Debian repo and installs amdrocm-core-sdk.
#    - System-wide install, suitable for all apps (not just Python).
#    - Requires sudo and fetching the latest nightly release ID.
#    Usage: METHOD=3 ./install_rocm7_and_compile_llama.sh
#
# ================================================================

METHOD="${METHOD:-1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPU_ARCH="gfx1201"
GPU_FAMILY="gfx120X-all"   # TheRock family index for gfx1200/gfx1201
AMD_ROCM_VERSION="7.2.3"
AMD_NOBLE_DEB="https://repo.radeon.com/amdgpu-install/${AMD_ROCM_VERSION}.70203/ubuntu/noble/amdgpu-install_${AMD_ROCM_VERSION}.70203-1_all.deb"
THEROCK_INDEX="https://rocm.nightlies.amd.com/v2/${GPU_FAMILY}/"

echo "================================================================"
echo " ROCm Installation & llama.cpp (HIP) Build Script"
echo " GPU Target : ${GPU_ARCH} (Radeon AI PRO R9700 / RX 9070, RDNA4)"
echo " Method     : ${METHOD}"
echo "================================================================"
echo ""

OS_CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d '=' -f 2 || echo "unknown")
echo " Detected OS codename: ${OS_CODENAME}"
echo ""

# ================================================================
# Helper: add user to render/video groups
# ================================================================
add_gpu_groups() {
    echo "-> Adding ${USER} to render and video groups (takes effect after re-login)..."
    sudo usermod -aG render "$USER" || true
    sudo usermod -aG video  "$USER" || true
}

# ================================================================
# METHOD 1: TheRock pip-based install (distro-agnostic)
# ================================================================
install_method1_therock_pip() {
    echo "================================================================"
    echo " METHOD 1: TheRock pip — ROCm nightly for ${GPU_FAMILY}"
    echo "================================================================"
    echo " This installs ROCm into a local Python venv at:"
    echo "   ${SCRIPT_DIR}/rocm-venv/"
    echo " hipcc, rocminfo, amdclang etc. will be in:"
    echo "   ${SCRIPT_DIR}/rocm-venv/bin/"
    echo ""
    read -p "Press [Enter] to continue, or [Ctrl+C] to abort..."

    # Ensure python3-venv
    if ! python3 -c "import venv" 2>/dev/null; then
        echo "-> Installing python3-venv..."
        sudo apt install -y python3-venv python3-pip
    fi

    echo "-> Creating Python venv at ${SCRIPT_DIR}/rocm-venv ..."
    python3 -m venv "${SCRIPT_DIR}/rocm-venv"
    source "${SCRIPT_DIR}/rocm-venv/bin/activate"

    echo "-> Installing ROCm (libraries + devel) for ${GPU_FAMILY} via TheRock pip index..."
    pip install --upgrade pip
    pip install --index-url "${THEROCK_INDEX}" "rocm[libraries,devel]"

    echo ""
    echo "-> Verifying ROCm installation..."
    "${SCRIPT_DIR}/rocm-venv/bin/rocminfo" | head -20 || echo "(rocminfo output truncated)"

    echo "-> Initialising rocm[devel] (expanding cmake/headers into venv)..."
    "${SCRIPT_DIR}/rocm-venv/bin/rocm-sdk" init || true

    # Locate the expanded devel tree containing hip-config.cmake etc.
    ROCM_DEVEL_PATH=$(find "${SCRIPT_DIR}/rocm-venv" -name "_rocm_sdk_devel" -type d 2>/dev/null | head -1)
    export ROCM_DEVEL_PATH
    echo "-> ROCM_DEVEL_PATH: ${ROCM_DEVEL_PATH}"

    add_gpu_groups

    echo ""
    echo "================================================================"
    echo " TheRock ROCm installed successfully into:"
    echo "   ${SCRIPT_DIR}/rocm-venv/"
    echo ""
    echo " To activate: source ${SCRIPT_DIR}/rocm-venv/bin/activate"
    echo " To verify:   rocminfo | head -30"
    echo "================================================================"
    echo ""

    # Export ROCM_HOME for the llama.cpp build
    export ROCM_HOME="${SCRIPT_DIR}/rocm-venv"
    export PATH="${ROCM_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"
    export CMAKE_PREFIX_PATH="${ROCM_HOME}"
}

# ================================================================
# METHOD 2: AMD official 7.2.3 via noble apt repo (no amdgpu-install)
# ================================================================
install_method2_amd_noble_apt() {
    echo "================================================================"
    echo " METHOD 2: AMD ROCm ${AMD_ROCM_VERSION} — noble apt repo on ${OS_CODENAME}"
    echo "================================================================"
    echo " WARNING: This adds AMD's Ubuntu 24.04 (noble) repo to your"
    echo " apt sources. It is NOT officially supported on ${OS_CODENAME},"
    echo " but the packages are ABI-compatible. Requires sudo + REBOOT."
    echo ""
    read -p "Press [Enter] to continue, or [Ctrl+C] to abort..."

    echo "-> Downloading AMD ROCm ${AMD_ROCM_VERSION} installer deb (noble)..."
    wget -O /tmp/amdgpu-install.deb "${AMD_NOBLE_DEB}"

    echo "-> Extracting and patching amdgpu-install to accept ${OS_CODENAME}..."
    # Extract the .deb and patch the codename list rather than running it directly
    mkdir -p /tmp/amdgpu-install-patched
    dpkg-deb -R /tmp/amdgpu-install.deb /tmp/amdgpu-install-patched

    # Patch the installer script to add questing/plucky to the supported list
    INSTALLER_SCRIPT=$(find /tmp/amdgpu-install-patched -name "amdgpu-install" -type f | head -1)
    if [[ -n "$INSTALLER_SCRIPT" ]]; then
        sed -i "s/noble)/noble|questing|plucky|oracular)/g" "$INSTALLER_SCRIPT" || true
        sed -i "s/jammy|noble/jammy|noble|questing|plucky|oracular/g" "$INSTALLER_SCRIPT" || true
    fi

    # Manually add the AMD ROCm noble apt repo
    echo "-> Adding AMD ROCm ${AMD_ROCM_VERSION} apt repo (noble) to sources..."
    sudo install -d -m 0755 /etc/apt/keyrings
    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
        gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \
https://repo.radeon.com/rocm/apt/${AMD_ROCM_VERSION} noble main" | \
        sudo tee /etc/apt/sources.list.d/rocm.list
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \
https://repo.radeon.com/amdgpu/${AMD_ROCM_VERSION}/ubuntu noble main" | \
        sudo tee /etc/apt/sources.list.d/amdgpu.list

    echo "-> Updating apt and installing ROCm..."
    sudo apt update
    sudo apt install -y rocm-hip-sdk rocm-dev hipcc rocm-llvm

    add_gpu_groups

    export ROCM_HOME="/opt/rocm"
    export PATH="${ROCM_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"

    echo ""
    echo "================================================================"
    echo " AMD ROCm ${AMD_ROCM_VERSION} installed to /opt/rocm"
    echo " *** YOU MUST REBOOT YOUR SYSTEM NOW FOR ROCM TO WORK ! ***"
    echo "================================================================"
    echo ""
}

# ================================================================
# METHOD 3: TheRock nightly native .deb packages
# ================================================================
install_method3_therock_deb() {
    echo "================================================================"
    echo " METHOD 3: TheRock nightly native .deb for gfx120x"
    echo "================================================================"
    echo " Fetching the latest nightly release ID from the index..."
    echo ""

    # Get the latest nightly build ID from the index page
    LATEST_RELEASE=$(curl -s https://rocm.nightlies.amd.com/packages-multi-arch/deb/ \
        | grep -oP '(?<=href=")[0-9]{8}-[0-9]+(?=/)' \
        | sort -r | head -1 || echo "")

    if [[ -z "$LATEST_RELEASE" ]]; then
        echo "ERROR: Could not auto-detect latest TheRock nightly release ID."
        echo "Please browse https://rocm.nightlies.amd.com/packages-multi-arch/deb/"
        echo "and re-run with: THEROCK_RELEASE_ID=YYYYMMDD-RUNID METHOD=3 $0"
        exit 1
    fi

    THEROCK_RELEASE_ID="${THEROCK_RELEASE_ID:-$LATEST_RELEASE}"
    echo " Using TheRock release: ${THEROCK_RELEASE_ID}"
    echo ""
    read -p "Press [Enter] to continue, or [Ctrl+C] to abort..."

    sudo apt install -y ca-certificates
    echo "deb [trusted=yes] https://rocm.nightlies.amd.com/packages-multi-arch/deb/${THEROCK_RELEASE_ID} stable main" \
        | sudo tee /etc/apt/sources.list.d/rocm-multiarch-nightly.list
    sudo apt update
    sudo apt install -y amdrocm-core-sdk-gfx120x

    add_gpu_groups

    export ROCM_HOME="/opt/rocm"
    export PATH="${ROCM_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"

    echo ""
    echo "================================================================"
    echo " TheRock native ROCm (gfx120x) installed to /opt/rocm"
    echo " *** YOU MUST REBOOT YOUR SYSTEM NOW FOR ROCM TO WORK ! ***"
    echo "================================================================"
    echo ""
}

# ================================================================
# Run the selected install method
# ================================================================
case "$METHOD" in
    1) install_method1_therock_pip ;;
    2) install_method2_amd_noble_apt ;;
    3) install_method3_therock_deb ;;
    *)
        echo "ERROR: Unknown METHOD=${METHOD}. Use METHOD=1, 2, or 3."
        exit 1
        ;;
esac

# ================================================================
# Build llama.cpp with ROCm (HIP)
# ================================================================
echo "================================================================"
echo " Building llama.cpp with ROCm / HIP for ${GPU_ARCH}..."
echo "================================================================"
echo ""

cd "${SCRIPT_DIR}"

# Determine hipcc location
if command -v hipcc &>/dev/null; then
    HIPCC_BIN=$(command -v hipcc)
elif [[ -f "${SCRIPT_DIR}/rocm-venv/bin/hipcc" ]]; then
    HIPCC_BIN="${SCRIPT_DIR}/rocm-venv/bin/hipcc"
    source "${SCRIPT_DIR}/rocm-venv/bin/activate"
elif [[ -f "/opt/rocm/bin/hipcc" ]]; then
    HIPCC_BIN="/opt/rocm/bin/hipcc"
    export ROCM_HOME="/opt/rocm"
    export PATH="${ROCM_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"
else
    echo "ERROR: hipcc not found. ROCm installation may have failed."
    exit 1
fi

echo "-> Using hipcc: ${HIPCC_BIN}"
echo "-> ROCM_HOME  : ${ROCM_HOME:-/opt/rocm}"
echo ""

echo "-> Compiling llama.cpp with ROCm (HIP) for ${GPU_ARCH}..."
cd "${SCRIPT_DIR}/llama.cpp-src"

# Always wipe the build dir to avoid stale CMake cache entries
rm -rf build
mkdir -p build && cd build

# Resolve a real C++ compiler — prefer amdclang++ from the venv, fall back to g++
if [[ -f "${ROCM_HOME:-}/bin/amdclang++" ]]; then
    CXX_COMPILER="${ROCM_HOME}/bin/amdclang++"
    C_COMPILER="${ROCM_HOME}/bin/amdclang"
    # CMake 3.31+ requires amdclang as HIP compiler, not the hipcc wrapper
    HIP_COMPILER="${ROCM_HOME}/bin/amdclang"
elif command -v g++ &>/dev/null; then
    CXX_COMPILER="$(command -v g++)"
    C_COMPILER="$(command -v gcc)"
    HIP_COMPILER="${HIPCC_BIN}"
elif command -v clang++ &>/dev/null; then
    CXX_COMPILER="$(command -v clang++)"
    C_COMPILER="$(command -v clang)"
    HIP_COMPILER="${HIPCC_BIN}"
else
    echo "ERROR: No C++ compiler found. Install gcc or clang."
    exit 1
fi
echo "-> C   compiler : ${C_COMPILER}"
echo "-> C++ compiler : ${CXX_COMPILER}"
echo "-> HIP compiler : ${HIP_COMPILER}"

# For methods 2/3, devel files are under /opt/rocm; for method 1 they are in the venv
ROCM_DEVEL_PATH="${ROCM_DEVEL_PATH:-${ROCM_HOME:-/opt/rocm}}"

cmake .. \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS="${GPU_ARCH}" \
    -DCMAKE_C_COMPILER="${C_COMPILER}" \
    -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
    -DCMAKE_HIP_COMPILER="${HIP_COMPILER}" \
    -DCMAKE_INSTALL_PREFIX="${SCRIPT_DIR}/llama.cpp-rocm" \
    -DCMAKE_PREFIX_PATH="${ROCM_HOME};${ROCM_DEVEL_PATH}"
cmake --build . --config Release -j "$(nproc)"
cmake --install .

echo ""
echo "================================================================"
echo " Done! llama.cpp (ROCm/HIP) installed in:"
echo "   ${SCRIPT_DIR}/llama.cpp-rocm/"
echo ""
if [[ "$METHOD" == "1" ]]; then
    echo " IMPORTANT: Before running, activate the ROCm venv:"
    echo "   source ${SCRIPT_DIR}/rocm-venv/bin/activate"
    echo " Or prefix commands with:"
    echo "   LD_LIBRARY_PATH=${SCRIPT_DIR}/rocm-venv/lib \\"
    echo "   HSA_OVERRIDE_GFX_VERSION=12.0.1 \\"
    echo "   ${SCRIPT_DIR}/llama.cpp-rocm/bin/llama-cli ..."
else
    echo " *** REBOOT YOUR SYSTEM NOW FOR ROCM TO FULLY WORK ! ***"
fi
echo "================================================================"
