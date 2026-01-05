#!/bin/bash
set -e

echo "============================================================"
echo "DeepEP B200 Benchmark Script"
echo "============================================================"
echo "This script will:"
echo "1. Run Intranode (Single Node) benchmarks."
echo "2. Run Internode (Multi-Node) benchmarks in SIMULATION mode on 1 node."
echo "============================================================"

# Ensure we are in the DeepEP directory
cd "$(dirname "$0")"

# 1. Intranode Benchmark
echo ""
echo "[1/2] Running Intranode Benchmark (8 GPUs)..."
echo "Expected H100 Baseline: ~153 GB/s (B200 should be significantly higher)"
echo "------------------------------------------------------------"
# Default arguments used in the repo examples
python tests/test_intranode.py --num-processes 8
echo "------------------------------------------------------------"
echo "[+] Intranode Benchmark Complete."

# 2. Internode Benchmark (Simulation)
echo ""
echo "[2/2] Running Internode Benchmark (Simulation on 1 Node)..."
echo "Note: This simulates the Internode kernel logic but runs on a single node."
echo "      Real Internode performance requires physical RDMA traffic between nodes."
echo "------------------------------------------------------------"

# Create a temporary simulation script
# We patch the assertion to allow num_ranks=8 (1 node)
cp tests/test_internode.py tests/test_internode_sim.py

# Sed command explanation:
# Find: assert num_local_ranks == 8 and num_ranks > 8
# Replace: assert num_local_ranks == 8 and num_ranks >= 8
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/num_ranks > 8/num_ranks >= 8/g' tests/test_internode_sim.py
else
  sed -i 's/num_ranks > 8/num_ranks >= 8/g' tests/test_internode_sim.py
fi

# Run the simulation
# We explicitly set WORLD_SIZE=1 for safety, though script defaults to it.
export WORLD_SIZE=1
python tests/test_internode_sim.py --num-processes 8

# Cleanup
rm tests/test_internode_sim.py

echo "------------------------------------------------------------"
echo "[+] Internode Simulation Complete."
echo ""
echo "============================================================"
echo "Benchmark Run Finished."
echo "Compare your 'GB/s (NVL)' and 'GB/s (RDMA)' results with the H100 baselines."
echo "H100 Intranode: ~153 GB/s"
echo "H100 Internode: ~43 GB/s (Limited by RDMA)"
echo "============================================================"
