#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

# ──────────────────────────────────────────────────────────────
# Predefined model paths — override by passing a path as $1
# ──────────────────────────────────────────────────────────────
MODEL_QWEN_27B="$HOME/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf"
MODEL_GEMMA_31B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf"
MODEL_GEMMA_26B="$HOME/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf"

# Default model
MODEL="${1:-$MODEL_QWEN_27B}"

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
# Vulkan runtime — uses the pre-compiled llama.cpp-vulkan build
# ──────────────────────────────────────────────────────────────
LLAMA_CLI="$SCRIPT_DIR/llama.cpp-vulkan/bin/llama-cli"
export LD_LIBRARY_PATH="$SCRIPT_DIR/llama.cpp-vulkan/lib:${LD_LIBRARY_PATH:-}"

# Target the discrete R9700 (gfx1201); skip the Cezanne iGPU
export GGML_VK_VISIBLE_DEVICES="1"

# ──────────────────────────────────────────────────────────────
# Validate
# ──────────────────────────────────────────────────────────────
if [[ ! -x "$LLAMA_CLI" ]]; then
    echo "[x] llama-cli not found at: $LLAMA_CLI"
    echo "    Expected pre-compiled binary in llama.cpp-vulkan/bin/."
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
    echo "    Usage: $0 [/path/to/model.gguf]"
    exit 1
fi

echo "=========================================================="
echo " llama.cpp Vulkan inference"
echo " Backend  : Vulkan (RADV GFX1201)"
echo " Model    : $(basename "$MODEL")"
echo " Context  : ${CTX_SIZE} tokens"
echo " GPU layers: ${NGL}"
echo "=========================================================="
echo ""

# Chat template is read from the GGUF metadata — no override needed.
# Pass --chat-template <name> as an extra argument if you want to force one.
exec "$LLAMA_CLI" \
    -m "$MODEL" \
    -ngl "$NGL" \
    -fa "$FLASH_ATTN" \
    -c "$CTX_SIZE" \
    --temp "$TEMP" \
    --top-p "$TOP_P" \
    --min-p "$MIN_P" \
    -cnv \
    "$@"
