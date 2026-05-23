#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# llm/ directory sits alongside benchmark/ under the repo root
LLM_DIR="$SCRIPT_DIR/../llm"

# Find llama-bench (fallback to global PATH if not found)
LLAMA_BENCH="$LLM_DIR/llama.cpp-rocm/bin/llama-bench"

# Export shared library paths: llama.cpp-rocm libs + all ROCm venv lib trees
ROCM_VENV="$LLM_DIR/rocm-venv"
ROCM_SP="$ROCM_VENV/lib/python3.13/site-packages"
export LD_LIBRARY_PATH="\
$LLM_DIR/llama.cpp-rocm/lib:\
$ROCM_SP/_rocm_sdk_libraries_gfx120X_all/lib:\
$ROCM_SP/_rocm_sdk_core/lib:\
$ROCM_SP/_rocm_sdk_core/lib/llvm/lib:\
$ROCM_SP/_rocm_sdk_devel/lib:\
$ROCM_SP/_rocm_sdk_devel/lib/llvm/lib:\
${LD_LIBRARY_PATH:-}"

if [[ ! -x "$LLAMA_BENCH" ]]; then
    LLAMA_BENCH=$(command -v llama-bench || echo "")
    if [[ -z "$LLAMA_BENCH" ]]; then
        echo "Error: llama-bench executable not found."
        echo "Please compile llama.cpp or set the LLAMA_BENCH path properly."
        exit 1
    fi
fi

# Define the models explicitly
MODEL_QWEN_27B="$HOME/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf"
MODEL_GEMMA_31B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf"
MODEL_GEMMA_26B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf"

# Apply ROCm environment overrides for RDNA compatibility
export HIP_VISIBLE_DEVICES="0" # Explicitly select the RDNA GPU (gfx12)

# Workaround: ROCm/ROCm#5706 — MES firmware bug causes GPU to remain at
# ~90W during idle when HIP hardware queues are open. Limiting to 1 HW queue
# drops idle power to ~20W with no meaningful impact on single-GPU inference.
# Fixed in MES firmware >= 0x8b; Ubuntu 25.10 linux-firmware still ships 0x84.
export GPU_MAX_HW_QUEUES=1

MODELS=(
    "$MODEL_QWEN_27B"
    "$MODEL_GEMMA_31B"
    "$MODEL_GEMMA_26B"
)

# Benchmark parameters
#   -ngl 99 : Offload all layers to VRAM (GPU)
#   -fa     : Enable Flash Attention
#   -p      : Prompt tokens (context sizes to test)
#   -n      : Generation tokens for decode speed evaluation

CONTEXT_SIZES="1024,4096,32768"
GEN_TOKENS="128"

RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

echo "==========================================================" | tee -a "$RESULTS_FILE"
echo " AMD RDNA LLM Benchmark Suite                              " | tee -a "$RESULTS_FILE"
echo " Enabled Features: Flash Attention, VRAM KV Offload        " | tee -a "$RESULTS_FILE"
echo " Context Windows:  $CONTEXT_SIZES                          " | tee -a "$RESULTS_FILE"
echo " Output Log:       $RESULTS_FILE                           " | tee -a "$RESULTS_FILE"
echo "==========================================================" | tee -a "$RESULTS_FILE"

for MODEL in "${MODELS[@]}"; do
    if [[ ! -f "$MODEL" ]]; then
        echo "" | tee -a "$RESULTS_FILE"
        echo "[!] WARNING: Model file not found: $MODEL" | tee -a "$RESULTS_FILE"
        echo "    Skipping benchmark for this model..." | tee -a "$RESULTS_FILE"
        continue
    fi
    
    MODEL_NAME="$(basename "$MODEL")"
    echo "" | tee -a "$RESULTS_FILE"
    echo "----------------------------------------------------------" | tee -a "$RESULTS_FILE"
    echo " Benchmarking Model: $MODEL_NAME" | tee -a "$RESULTS_FILE"
    echo "----------------------------------------------------------" | tee -a "$RESULTS_FILE"
    
    # Run llama-bench with the specified flags
    COMMAND=(
        "$LLAMA_BENCH"
        "-m" "$MODEL"
        "-ngl" "99"
        "-fa" "1"
 #       "-ctk" "q8_0"
 #       "-ctv" "q8_0"
        "-p" "$CONTEXT_SIZES"
        "-n" "$GEN_TOKENS"
    )
    
    echo "Command: ${COMMAND[*]}" | tee -a "$RESULTS_FILE"
    echo "" | tee -a "$RESULTS_FILE"
    
    # Execute benchmark and append output to log
    "${COMMAND[@]}" 2>&1 | tee -a "$RESULTS_FILE"
done

echo "" | tee -a "$RESULTS_FILE"
echo "==========================================================" | tee -a "$RESULTS_FILE"
echo " Benchmarks completed!" | tee -a "$RESULTS_FILE"
echo " Results have been saved to: $RESULTS_FILE" | tee -a "$RESULTS_FILE"
echo "==========================================================" | tee -a "$RESULTS_FILE"
