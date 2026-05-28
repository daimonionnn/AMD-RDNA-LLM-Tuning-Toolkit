#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--gpus SELECTOR] /path/to/model.gguf [additional llama-bench args]
Example: $(basename "$0") ~/models/llama-2-7b-chat.Q4_K_S.gguf

$(rdna_print_usage_block)
EOF
}

GPUS_SELECTOR="${RDNA_GPUS:-all}"
MODEL=""
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus)
            [[ $# -ge 2 ]] || { echo "[x] --gpus requires a value" >&2; exit 1; }
            GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)
            GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; EXTRA_ARGS+=("$@"); break ;;
        *)
            if [[ -z "$MODEL" && "$1" != -* ]]; then MODEL="$1"
            else EXTRA_ARGS+=("$1"); fi
            shift ;;
    esac
done

if [[ -z "$MODEL" ]]; then usage; exit 1; fi

BENCH_BIN="$REPO_DIR/llm/llama.cpp-vulkan/bin/llama-bench"

mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }
VK_INDICES="$(printf '%s\n' "${SELECTED_BDFS[@]}" | bdf_to_runtime_indices)"
export GGML_VK_VISIBLE_DEVICES="$VK_INDICES"

if [ ! -x "$BENCH_BIN" ]; then
    echo "✗ Error: $BENCH_BIN not found or not executable."
    exit 1
fi

echo "=========================================================="
echo " Starting Vulkan llama-bench"
echo " Model: $MODEL"
echo " GPUs : ${#SELECTED_BDFS[@]} (${SELECTED_BDFS[*]}) GGML_VK_VISIBLE_DEVICES=$VK_INDICES"
echo "=========================================================="

"$BENCH_BIN" -m "$MODEL" -p 128,512,1024,2048 -n 128 -ngl 99 "${EXTRA_ARGS[@]}"
