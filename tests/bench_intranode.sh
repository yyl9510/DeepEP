#!/bin/bash
# Quick DeepEP intra-node benchmark
# Usage: bash tests/bench_intranode.sh --hidden 7168 [--num-tokens 16384] [--num-sms "8 16 24 32 48 64"] [--nvl-buf "256 512"]
#
# Outputs a table sorted by per-SM efficiency for easy config selection.

set -e
cd "$(dirname "$0")/.."

# Defaults (B200 8-GPU)
HIDDEN=3072
NUM_TOKENS=16384
NUM_PROCS=8
NUM_EXPERTS=128
NUM_TOPK=8
NUM_SMS="8 16 24 32 40 48 64"
NVL_BUF="256 288 512"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hidden)       HIDDEN="$2"; shift 2;;
        --num-tokens)   NUM_TOKENS="$2"; shift 2;;
        --num-procs)    NUM_PROCS="$2"; shift 2;;
        --num-experts)  NUM_EXPERTS="$2"; shift 2;;
        --num-topk)     NUM_TOPK="$2"; shift 2;;
        --num-sms)      NUM_SMS="$2"; shift 2;;
        --nvl-buf)      NVL_BUF="$2"; shift 2;;
        -h|--help)
            echo "Usage: $0 [--hidden H] [--num-tokens T] [--num-sms \"8 16 24 ...\"] [--nvl-buf \"256 512 ...\"]"
            echo ""
            echo "Options:"
            echo "  --hidden H        Hidden dimension (default: 3072)"
            echo "  --num-tokens T    Number of tokens (default: 16384)"
            echo "  --num-procs N     Number of GPUs (default: 8)"
            echo "  --num-experts E   Number of experts (default: 128)"
            echo "  --num-topk K      Top-k value (default: 8)"
            echo "  --num-sms \"...\"   Space-separated SM counts to test (default: \"8 16 24 32 40 48 64 80 96\")"
            echo "  --nvl-buf \"...\"   Space-separated NVL buffer sizes (default: \"256 288 512\")"
            exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

# Check if num_sms + hidden would exceed the 2GB NVL buffer limit
# num_channels = num_sms / 2, buffer ~ channels * 8 * nvl_buf * hidden * 2 bytes
# Skip combinations that would OOM
SAFE_SMS=""
MAX_NVL=$(echo "$NVL_BUF" | tr ' ' '\n' | sort -n | tail -1)
for sms in $NUM_SMS; do
    channels=$((sms / 2))
    # Rough estimate: channels * 8_ranks * max_nvl_buf * hidden * 2bytes * 1.02 (topk overhead)
    est_bytes=$(python3 -c "print(int($channels * 8 * $MAX_NVL * $HIDDEN * 2 * 1.02))" 2>/dev/null)
    if [ "$est_bytes" -le 2000000000 ]; then
        SAFE_SMS="$SAFE_SMS $sms"
    else
        echo "[warn] Skipping num_sms=$sms: estimated NVL buffer ${est_bytes} bytes > 2GB (hidden=$HIDDEN, max_buf=$MAX_NVL)"
    fi
done
SAFE_SMS=$(echo "$SAFE_SMS" | xargs)

if [ -z "$SAFE_SMS" ]; then
    echo "[error] All num_sms values would exceed 2GB NVL buffer. Try smaller --nvl-buf or --hidden."
    exit 1
fi

export NCCL_DEBUG=WARNING

echo "========================================"
echo "  DeepEP Quick Benchmark"
echo "  hidden=$HIDDEN  tokens=$NUM_TOKENS  procs=$NUM_PROCS"
echo "  num_sms: $SAFE_SMS"
echo "  nvl_buf: $NVL_BUF"
echo "  Time: $(date)"
echo "========================================"

python tests/test_intranode.py \
    --num-processes $NUM_PROCS \
    --hidden $HIDDEN \
    --num-tokens $NUM_TOKENS \
    --num-experts $NUM_EXPERTS \
    --num-topk $NUM_TOPK \
    --num-sms $SAFE_SMS \
    --nvl-buffer-size $NVL_BUF
