#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

# ──────────────────────────────────────────────────────────────
# Predefined model paths — override by passing a path as $1
# ──────────────────────────────────────────────────────────────
MODEL_QWEN_27B="$HOME/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf"
MODEL_GEMMA_31B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf"
MODEL_GEMMA_26B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf"

# ──────────────────────────────────────────────────────────────
# Argument parsing — accept --gpus SELECTOR anywhere; first
# positional argument is the model path. Everything else is
# forwarded to llama-cli verbatim.
# ──────────────────────────────────────────────────────────────
GPUS_SELECTOR="${RDNA_GPUS:-all}"
MODEL=""
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus)
            [[ $# -ge 2 ]] || { echo "[x] --gpus requires a value" >&2; exit 1; }
            GPUS_SELECTOR="$2"
            shift 2
            ;;
        --gpus=*)
            GPUS_SELECTOR="${1#--gpus=}"
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--gpus SELECTOR] [/path/to/model.gguf] [llama-cli args...]

$(rdna_print_usage_block)

Predefined models (used when no path is given):
  Qwen3.6 27B  : $MODEL_QWEN_27B
  Gemma4 31B   : $MODEL_GEMMA_31B
  Gemma4 26B   : $MODEL_GEMMA_26B
EOF
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            if [[ -z "$MODEL" && "$1" != -* ]]; then
                MODEL="$1"
            else
                EXTRA_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

MODEL="${MODEL:-$MODEL_QWEN_27B}"

# ──────────────────────────────────────────────────────────────
# Inference parameters
# ──────────────────────────────────────────────────────────────
CTX_SIZE=8192        # Context window (tokens)
NGL=99               # GPU layers — offload everything to VRAM
FLASH_ATTN=1         # Flash Attention
TEMP=0.6             # Temperature
TOP_P=0.95           # Top-p sampling
MIN_P=0.0            # Min-p (disabled)
# Uncomment to quantise the KV cache (saves VRAM on large contexts):
#CTK="q8_0"
#CTV="q8_0"

# ──────────────────────────────────────────────────────────────
# ROCm runtime — paths into the local venv produced by
# install_rocm7_and_compile_llama.sh
# ──────────────────────────────────────────────────────────────
LLAMA_CLI="$SCRIPT_DIR/llama.cpp-rocm/bin/llama-cli"

ROCM_VENV="$SCRIPT_DIR/rocm-venv"
ROCM_SP="$ROCM_VENV/lib/python3.13/site-packages"
export LD_LIBRARY_PATH="\
$SCRIPT_DIR/llama.cpp-rocm/lib:\
$ROCM_SP/_rocm_sdk_libraries_gfx120X_all/lib:\
$ROCM_SP/_rocm_sdk_core/lib:\
$ROCM_SP/_rocm_sdk_core/lib/llvm/lib:\
$ROCM_SP/_rocm_sdk_devel/lib:\
$ROCM_SP/_rocm_sdk_devel/lib/llvm/lib:\
${LD_LIBRARY_PATH:-}"

# Resolve --gpus into HIP device indices (BDF-sorted, iGPU-aware).
mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }
HIP_INDICES="$(printf '%s\n' "${SELECTED_BDFS[@]}" | bdf_to_runtime_indices)"
export HIP_VISIBLE_DEVICES="$HIP_INDICES"

# Workaround: ROCm/ROCm#5706 — MES firmware bug causes GPU to remain at
# ~90W during idle when HIP hardware queues are open. Limiting to 1 HW queue
# drops idle power to ~20W with no meaningful impact on single-GPU inference.
# Fixed in MES firmware >= 0x8b; Ubuntu 25.10 linux-firmware still ships 0x84.
export GPU_MAX_HW_QUEUES=1

# ──────────────────────────────────────────────────────────────
# Validate
# ──────────────────────────────────────────────────────────────
if [[ ! -x "$LLAMA_CLI" ]]; then
    echo "[x] llama-cli not found at: $LLAMA_CLI"
    echo "    Run ./install_rocm7_and_compile_llama.sh first."
    exit 1
fi

if [[ ! -f "$MODEL" ]]; then
    echo "[x] Model file not found: $MODEL"
    echo ""
    echo "    Predefined models:"
    echo "      Qwen3.6 27B  : $MODEL_QWEN_27B"
    echo "      Gemma4 31B   : $MODEL_GEMMA_31B"
    echo "      Gemma4 26B   : $MODEL_GEMMA_26B"
    echo ""
    echo "    Usage: $0 [--gpus SELECTOR] [/path/to/model.gguf] [llama-cli args...]"
    exit 1
fi

echo "=========================================================="
echo " llama.cpp ROCm inference"
echo " Backend  : ROCm/HIP (gfx1201)"
echo " Model    : $(basename "$MODEL")"
echo " GPUs     : ${#SELECTED_BDFS[@]} selected — ${SELECTED_BDFS[*]}"
echo " HIP idx  : $HIP_INDICES"
echo " Context  : ${CTX_SIZE} tokens"
echo " GPU layers: ${NGL}"
echo "=========================================================="
echo ""

# Chat template is read from the GGUF metadata — no override needed.
# Pass --chat-template <name> as an extra argument if you want to force one.
# With multiple GPUs visible, llama.cpp defaults to layer-split (-sm layer);
# override via extra args (e.g. -sm row, -mg N, -ts a,b).
exec "$LLAMA_CLI" \
    -m "$MODEL" \
    -ngl "$NGL" \
    -fa "$FLASH_ATTN" \
    -c "$CTX_SIZE" \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --min-p "$MIN_P" \
    -cnv \
    "${EXTRA_ARGS[@]}"
