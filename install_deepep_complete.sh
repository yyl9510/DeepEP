#!/bin/bash
set -e  # Exit on error

# DeepEP Installation Script
# Assumes the current directory is the DeepEP repository root.
# Requires: nvcc, python3 with torch and nvidia-nvshmem installed.
# Example in B200: TORCH_CUDA_ARCH_LIST="10.0" bash ./install_deepep_complete.sh

echo "=========================================="
echo "Starting DeepEP Installation"
echo "=========================================="

# 1. Environment Checks
echo "[+] Checking environment..."

if ! command -v nvcc &> /dev/null; then
    echo "Error: nvcc not found. Please ensure CUDA Toolkit is installed and in PATH."
    echo "Try: export PATH=/usr/local/cuda/bin:\$PATH"
    exit 1
fi
echo "  - nvcc found: $(which nvcc)"
nvcc --version | grep "release"

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found."
    exit 1
fi
echo "  - python3 found: $(which python3)"

if ! python3 -c "import torch" 2>/dev/null; then
    echo "Error: torch not found. Please install PyTorch first."
    exit 1
fi
echo "  - torch: $(python3 -c "import torch; print(f'version={torch.__version__}, cuda={torch.version.cuda}')")"

if ! python3 -c "import nvidia.nvshmem" 2>/dev/null; then
    echo "  - nvidia-nvshmem not found, installing..."
    CUDA_MAJOR=$(python3 -c "import torch; print(torch.version.cuda.split('.')[0])")
    pip install nvidia-nvshmem-cu${CUDA_MAJOR}
fi
NVSHMEM_LIB=$(python3 -c "import nvidia.nvshmem, os; print(os.path.join(nvidia.nvshmem.__path__[0], 'lib'))")
echo "  - nvshmem lib: $NVSHMEM_LIB"
# Prepend to LD_LIBRARY_PATH so pip nvshmem takes priority over system nvshmem
# (system version may lack symbols needed by DeepEP)
export LD_LIBRARY_PATH=$NVSHMEM_LIB:$LD_LIBRARY_PATH

# Persist nvshmem LD_LIBRARY_PATH into venv activate script
VENV_PREFIX=$(python3 -c "import sys; print(sys.prefix)")
ACTIVATE_SCRIPT="$VENV_PREFIX/bin/activate"
if [ -f "$ACTIVATE_SCRIPT" ]; then
    if ! grep -q "nvshmem" "$ACTIVATE_SCRIPT"; then
        echo "" >> "$ACTIVATE_SCRIPT"
        echo "# Added by DeepEP installer: nvshmem lib path" >> "$ACTIVATE_SCRIPT"
        echo "export LD_LIBRARY_PATH=$NVSHMEM_LIB:\$LD_LIBRARY_PATH" >> "$ACTIVATE_SCRIPT"
        echo "  - Added nvshmem lib to $ACTIVATE_SCRIPT"
    else
        echo "  - nvshmem lib already in $ACTIVATE_SCRIPT"
    fi
fi

# 2. Architecture Configuration
echo "[+] Configuring CUDA Architecture..."
if [ -z "$TORCH_CUDA_ARCH_LIST" ]; then
    export TORCH_CUDA_ARCH_LIST="9.0"
    echo "  - Defaulted TORCH_CUDA_ARCH_LIST to '9.0'."
    echo "  - NOTE: For B200 (Blackwell), set TORCH_CUDA_ARCH_LIST=10.0"
else
    echo "  - TORCH_CUDA_ARCH_LIST is set to: $TORCH_CUDA_ARCH_LIST"
fi

# 3. CUDA include paths (auto-detect via /usr/local/cuda symlink)
echo "[+] Configuring CUDA include paths..."
CUDA_TARGET_INCLUDE=$(find /usr/local/cuda/targets/*/include -maxdepth 0 2>/dev/null | head -1)
if [ ! -z "$CUDA_TARGET_INCLUDE" ]; then
    export CPATH=$CUDA_TARGET_INCLUDE:$CPATH
    export CPLUS_INCLUDE_PATH=$CUDA_TARGET_INCLUDE:$CPLUS_INCLUDE_PATH
    echo "  - CUDA target include: $CUDA_TARGET_INCLUDE"

    CCCL_INC="$CUDA_TARGET_INCLUDE/cccl"
    if [ -d "$CCCL_INC" ]; then
        export CPATH=$CCCL_INC:$CPATH
        export CXXFLAGS="-I$CCCL_INC $CXXFLAGS"
        export CFLAGS="-I$CCCL_INC $CFLAGS"
        echo "  - CCCL include: $CCCL_INC"
    fi
fi

# 4. Installation
echo "[+] Installing DeepEP..."
rm -rf build/ deep_ep.egg-info/

pip install . --no-build-isolation -v

echo "=========================================="
echo "Installation Complete"
echo "=========================================="
echo "Verify:"
python -c 'import deep_ep; print("Success: deep_ep imported")'
