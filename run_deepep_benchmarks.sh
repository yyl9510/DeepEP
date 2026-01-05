#!/bin/bash
set -e

cd "$(dirname "$0")"

# 1. Run Intranode Benchmark for single node (验证 NVLink 性能) 
echo ">>> [1/2] Running Intranode Benchmark..."
python tests/test_intranode.py --num-processes 8

# 2. Run Internode Simulation for two nodes (验证 RDMA/Internode 算子逻辑)
echo -e "\n>>> [2/2] Running Internode Simulation..."

NCCL_DEBUG=WARNING python tests/test_internode.py --num-processes 8

echo -e "\n>>> All Benchmarks Finished."