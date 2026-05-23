#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 /path/to/model.gguf [additional llama-bench args]"
    exit 1
fi

MODEL="$1"
shift

BENCH_BIN="$(dirname "$0")/../llm/llama.cpp-rocm/bin/llama-bench"
export LD_LIBRARY_PATH="$(dirname "$0")/../llm/llama.cpp-rocm/lib:${LD_LIBRARY_PATH:-}"

if [ ! -x "$BENCH_BIN" ]; then
    echo "✗ Error: $BENCH_BIN not found or not executable. Did you compile llama.cpp-rocm?"
    exit 1
fi

echo "=========================================================="
echo " Starting ROCm7 llama-bench"
echo " Model: $MODEL"
echo "=========================================================="

"$BENCH_BIN" -m "$MODEL" -p 128,512,1024,2048 -n 128 -ngl 99 "$@"
