#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

# llm/ directory sits alongside benchmark/ under the repo root
LLM_DIR="$REPO_DIR/llm"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--gpus SELECTOR] [--no-per-gpu-sweep]

$(rdna_print_usage_block)

  --no-per-gpu-sweep  When >1 GPU is selected, skip the individual per-GPU
                      passes and only run the combined multi-GPU pass.
                      Default: per-GPU passes + combined pass.
EOF
}

GPUS_SELECTOR="${RDNA_GPUS:-all}"
PER_GPU_SWEEP=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus)
            [[ $# -ge 2 ]] || { echo "[x] --gpus requires a value" >&2; exit 1; }
            GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)
            GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        --no-per-gpu-sweep)
            PER_GPU_SWEEP=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "[x] Unknown argument: $1" >&2
            usage >&2; exit 1 ;;
    esac
done

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

# Workaround: ROCm/ROCm#5706 — MES firmware bug causes GPU to remain at
# ~90W during idle when HIP hardware queues are open. Limiting to 1 HW queue
# drops idle power to ~20W with no meaningful impact on single-GPU inference.
# Fixed in MES firmware >= 0x8b; Ubuntu 25.10 linux-firmware still ships 0x84.
export GPU_MAX_HW_QUEUES=1

MODELS=(
    "$MODEL_QWEN_27B"
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

# Resolve GPU selection.
mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }

# Build the list of passes. Each entry is "label|BDF1,BDF2,...".
PASSES=()
if (( ${#SELECTED_BDFS[@]} == 1 )); then
    PASSES+=("single GPU ${SELECTED_BDFS[0]}|${SELECTED_BDFS[0]}")
else
    if (( PER_GPU_SWEEP )); then
        for bdf in "${SELECTED_BDFS[@]}"; do
            PASSES+=("solo $bdf|$bdf")
        done
    fi
    combined="$(IFS=,; echo "${SELECTED_BDFS[*]}")"
    PASSES+=("combined ${#SELECTED_BDFS[@]} GPUs ($combined)|$combined")
fi

{
    echo "=========================================================="
    echo " AMD RDNA LLM Benchmark Suite (ROCm)                       "
    echo " Enabled Features: Flash Attention, VRAM KV Offload        "
    echo " Context Windows:  $CONTEXT_SIZES                          "
    echo " GPUs selected:    ${#SELECTED_BDFS[@]} (${SELECTED_BDFS[*]})"
    echo " Benchmark passes: ${#PASSES[@]}"
    echo " Output Log:       $RESULTS_FILE                           "
    echo "=========================================================="
} | tee -a "$RESULTS_FILE"

for pass in "${PASSES[@]}"; do
    label="${pass%%|*}"
    bdf_csv="${pass##*|}"

    # Convert BDF list -> runtime indices.
    HIP_INDICES="$(printf '%s\n' ${bdf_csv//,/ } | bdf_to_runtime_indices)"
    export HIP_VISIBLE_DEVICES="$HIP_INDICES"

    {
        echo ""
        echo "##########################################################"
        echo "# PASS: $label"
        echo "# BDFs: $bdf_csv"
        echo "# HIP_VISIBLE_DEVICES=$HIP_INDICES"
        echo "##########################################################"
    } | tee -a "$RESULTS_FILE"

    for MODEL in "${MODELS[@]}"; do
        if [[ ! -f "$MODEL" ]]; then
            {
                echo ""
                echo "[!] WARNING: Model file not found: $MODEL"
                echo "    Skipping benchmark for this model..."
            } | tee -a "$RESULTS_FILE"
            continue
        fi

        MODEL_NAME="$(basename "$MODEL")"
        {
            echo ""
            echo "----------------------------------------------------------"
            echo " Benchmarking Model: $MODEL_NAME"
            echo "----------------------------------------------------------"
        } | tee -a "$RESULTS_FILE"

        COMMAND=(
            "$LLAMA_BENCH"
            "-m" "$MODEL"
            "-ngl" "99"
            "-fa" "1"
            "-p" "$CONTEXT_SIZES"
            "-n" "$GEN_TOKENS"
        )

        {
            echo "Command: ${COMMAND[*]}"
            echo ""
        } | tee -a "$RESULTS_FILE"

        "${COMMAND[@]}" 2>&1 | tee -a "$RESULTS_FILE"
    done
done

{
    echo ""
    echo "=========================================================="
    echo " Benchmarks completed!"
    echo " Results have been saved to: $RESULTS_FILE"
    echo "=========================================================="
} | tee -a "$RESULTS_FILE"
