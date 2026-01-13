#!/bin/bash
set -e

# ==========================================
# DeepEP Installation Script for A100 (Ampere)
# ==========================================

echo "=========================================="
echo "Starting DeepEP Installation for A100"
echo "=========================================="

# 1. Environment Checks
echo "[+] Checking environment..."

# Auto-add CUDA path if nvcc not found
if ! command -v nvcc &> /dev/null; then
    echo "  - nvcc not directly in PATH, trying common locations..."
    if [ -d "/usr/local/cuda/bin" ]; then
        export PATH=$PATH:/usr/local/cuda/bin
        echo "  - Added /usr/local/cuda/bin to PATH"
    elif [ -d "/usr/local/cuda-13.0/bin" ]; then
        export PATH=$PATH:/usr/local/cuda-13.0/bin
        echo "  - Added /usr/local/cuda-13.0/bin to PATH"
    fi
fi

if ! command -v nvcc &> /dev/null; then
    echo "Error: nvcc not found. Please load CUDA module or check installation."
    exit 1
fi
echo "  - nvcc found: $(which nvcc)"
nvcc --version | grep release

if ! command -v python3.11 &> /dev/null; then
    echo "Error: python3.11 not found."
    exit 1
fi
echo "  - python3.11 found: $(which python3.11)"

# 2. Configure NVSHMEM
echo "[+] Configuring NVSHMEM..."
# Attempt to find NVSHMEM from typical locations used in previous successful installs
# or common system paths.
if [ -z "$NVSHMEM_DIR" ]; then
    echo "  NVSHMEM_DIR is not set. Attempting to locate..."
    
    # Check pip package location
    PIP_NVSHMEM_PATH=$(python3.11 -c "import nvidia.nvshmem; import os; print(os.path.dirname(nvidia.nvshmem.__file__))" 2>/dev/null || true)
    
    if [ ! -z "$PIP_NVSHMEM_PATH" ]; then
         export NVSHMEM_DIR="$PIP_NVSHMEM_PATH"
         echo "  - Found NVSHMEM via pip: $NVSHMEM_DIR"
    elif [ -d "/usr/local/cuda/targets/x86_64-linux/lib/stubs" ]; then
         # Sometimes it's bundled with CUDA? (Less likely for standalone lib)
         # Fallback to manual message
         echo "  - Warning: NVSHMEM not found via pip. Assuming system install or user will provide."
         echo "    If compilation fails, please: export NVSHMEM_DIR=/path/to/nvshmem"
    else
         echo "  - Warning: NVSHMEM not found."
         echo "    If you need Internode support, please ensure nvidia-nvshmem-cu12 is installed."
    fi
else
    echo "  - NVSHMEM_DIR is already set to: $NVSHMEM_DIR"
fi

# 3. Reset C++ Configs to Default (Safe for A100 8-GPU)
# Ensure NUM_MAX_NVL_PEERS is 8 (Standard for HGX A100)
CONFIG_FILE="csrc/kernels/configs.cuh"
if [ -f "$CONFIG_FILE" ]; then
    echo "[+] Verifying configurations in $CONFIG_FILE..."
    # Ensure it is set to 8. If it was patched to 4 for simulation, we revert it.
    sed -i 's/#define NUM_MAX_NVL_PEERS 4/#define NUM_MAX_NVL_PEERS 8/g' "$CONFIG_FILE"
    grep "NUM_MAX_NVL_PEERS" "$CONFIG_FILE"
fi

# 4. Set CUDA Architecture for A100 & Disable Hopper Features
echo "[+] Configuring CUDA Architecture..."
export TORCH_CUDA_ARCH_LIST="8.0"
export DISABLE_SM90_FEATURES=1
echo "  - TORCH_CUDA_ARCH_LIST is set to: $TORCH_CUDA_ARCH_LIST"
echo "  - DISABLE_SM90_FEATURES is set to: $DISABLE_SM90_FEATURES"

# 5. Build and Install
echo "[+] Installing DeepEP..."

# Clean old artifacts to force re-compilation
echo "  - Cleaning old build artifacts..."
rm -rf build/ deep_ep.egg-info/ dist/

# Install
# Standard pip failed. setup.py install failed. build module failed (due to old system setuptools).
# Fourth attempt: Upgrade setuptools to bypass system bugs, then build.

echo "  - Upgrading build tools (setuptools, wheel)..."
python3.11 -m pip install --upgrade --user setuptools wheel build

echo "  - Building into a wheel..."
python3.11 -m build --wheel --no-isolation

echo "  - Installing the generated wheel..."
# Find the wheel we just created
WHEEL_FILE=$(find dist -name "*.whl" | head -n 1)
if [ -z "$WHEEL_FILE" ]; then
    echo "Error: Wheel build failed, no .whl file found."
    exit 1
fi
echo "    Found wheel: $WHEEL_FILE"
python3.11 -m pip install "$WHEEL_FILE" --force-reinstall

echo "=========================================="
echo "Installation Complete!"
echo "To verify, run: python -c 'import deep_ep; print(\"DeepEP imported successfully\")'"
echo "=========================================="
