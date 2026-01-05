#!/bin/bash
set -e  # Exit on error

# DeepEP Installation Script
# Assumes the current directory is the DeepEP repository root.
# Example in B200: export TORCH_CUDA_ARCH_LIST="10.0" ./install_deepep_complete.sh

echo "=========================================="
echo "Starting DeepEP Installation"
echo "=========================================="

# 1. Environment Checks
echo "[+] Checking environment..."

# Check for nvcc
if ! command -v nvcc &> /dev/null; then
    echo "Error: nvcc not found. Please ensure CUDA Toolkit is installed and in PATH."
    echo "Try: export PATH=/usr/local/cuda/bin:\$PATH"
    exit 1
fi
echo "  - nvcc found: $(which nvcc)"
nvcc --version | grep "release"

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found."
    exit 1
fi
echo "  - python3 found: $(which python3)"

# 2. NVSHMEM Configuration
echo "[+] Configuring NVSHMEM..."
cd /usr/local/lib/python3.12/dist-packages/nvidia/nvshmem/lib/
sudo ln -s libnvshmem_host.so.3 libnvshmem_host.so
ls -l libnvshmem_host.so
# 正常应显示：libnvshmem_host.so -> libnvshmem_host.so.3

# Try to find NVSHMEM from typical pip install location if not set
if [ -z "$NVSHMEM_DIR" ]; then
    echo "  NVSHMEM_DIR is not set. Attempting to locate installed nvidia-nvshmem packet..."
    # Attempt to find via python
    NVSHMEM_PATH=$(python3 -c "import nvidia.nvshmem as n; import os; print(os.path.dirname(n.__file__))" 2>/dev/null || true)
    
    if [ ! -z "$NVSHMEM_PATH" ]; then
        export NVSHMEM_DIR="$NVSHMEM_PATH"
        echo "  - Auto-detected NVSHMEM_DIR: $NVSHMEM_DIR"
    else
        echo "  - Warning: NVSHMEM not found via pip. If you need internode support, please install it:"
        echo "    pip install nvidia-nvshmem-cu12"
        echo "    OR export NVSHMEM_DIR=/path/to/nvshmem"
        echo "  - Proceeding without explicit NVSHMEM_DIR (DeepEP might disable internode features)."
    fi
else
    echo "  - NVSHMEM_DIR is set to: $NVSHMEM_DIR"
fi

# 3. Architecture Configuration
echo "[+] Configuring CUDA Architecture..."
# Check for B200 (sm_100) or H100 (sm_90)
# Defaulting to 9.0 (H100) as a safe baseline for modern GPUs, but 10.0 is for Blackwell.
# If compiling for B200, users should preferably use 10.0 or 9.0+PTX.

if [ -z "$TORCH_CUDA_ARCH_LIST" ]; then
    echo "  TORCH_CUDA_ARCH_LIST not set. Detecting..."
    # Simple heuristic: if nvcc supports > 12.0, default to 9.0. 
    # For B200 specifically, we recommend setting this manually to "10.0" if supported, or "9.0" strictly.
    export TORCH_CUDA_ARCH_LIST="9.0" 
    echo "  - Defaulted TORCH_CUDA_ARCH_LIST to '9.0' (Hopper + forward compat)."
    echo "  - NOTE: For B200 (Blackwell), ensure you are using CUDA 12.8+ or 13.0."
else
    echo "  - TORCH_CUDA_ARCH_LIST is set to: $TORCH_CUDA_ARCH_LIST"
fi

# 4. Installation
echo "[+] Installing DeepEP..."
# Using pip install . --no-build-isolation to use the current environment's packages
# and avoid issues with isolated build environment missing Torch.

# Optional: Clean previous builds
if [ -d "build" ]; then
    echo "  - Cleaning old build artifacts..."
    rm -rf build dist *.egg-info
fi

echo "  - Running pip install..."
# export CPATH=/usr/local/cuda/include:$CPATH
# export CPLUS_INCLUDE_PATH=/usr/local/lib/python3.12/dist-packages/nvidia/nvshmem/include:$CPLUS_INCLUDE_PATH
export TARGET_CUDA_INCLUDE=/usr/local/cuda-13.0/targets/x86_64-linux/include
export CPATH=$TARGET_CUDA_INCLUDE:$CPATH
export CPLUS_INCLUDE_PATH=$TARGET_CUDA_INCLUDE:$CPLUS_INCLUDE_PATH

export MY_CCCL_INC=/usr/local/cuda-13.0/targets/x86_64-linux/include/cccl
export CPATH=$MY_CCCL_INC:$CPATH
export CXXFLAGS="-I$MY_CCCL_INC $CXXFLAGS"
export CFLAGS="-I$MY_CCCL_INC $CFLAGS"

rm -rf build/ deep_ep.egg-info/

pip install . --no-build-isolation -v

echo "=========================================="
echo "Installation Complete"
echo "=========================================="
echo "To verify:"
echo "python -c 'import deep_ep; print(\"Success: deep_ep imported\")'"
