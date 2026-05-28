#!/usr/bin/env bash
# force_pcie_link.sh — Force a PCIe root port to retrain at a higher link speed.
#
# Use case: on B450 + Cezanne (Ryzen 5xxxG) with 2× R9700 in x8/x4/x4
# bifurcation, the BIOS pins the second GPU's root port to PCIe Gen1 x4 with
# "Hardware Autonomous Speed Disable" set. This script flips the Target Link
# Speed to the requested generation, clears SpeedDis, and triggers a link
# retrain. On this hardware the link can stably reach Gen2 x4 (~2× the
# bandwidth of the BIOS default).
#
# IMPORTANT — this change is NOT persistent across reboot. The BIOS reloads
# its defaults every boot, so re-run this script after each reboot (or wire
# it up as a systemd oneshot).
#
# Safety: if the link cannot train to the requested speed, it stays at
# whatever it could train (no harm done). If the bus hangs entirely you may
# need a hard reset — BIOS defaults will be restored on boot.
#
# Defaults are tuned for the documented test system (root port 00:02.4,
# target Gen3 which trains to Gen2 in practice). Override via flags.

set -euo pipefail

ROOT_PORT="${RDNA_ROOT_PORT:-00:02.4}"
TARGET_GEN="${RDNA_TARGET_GEN:-3}"   # 1=Gen1, 2=Gen2, 3=Gen3
EXPRESS_CAP_OFFSET=""                # auto-detect if empty

usage() {
    cat <<EOF
Usage: $(basename "$0") [--root-port BDF] [--target-gen N] [--help]

Options:
  --root-port BDF   PCIe root port to retrain (default: $ROOT_PORT)
                    Find with: lspci -tv  (look for the bridge above your GPU)
  --target-gen N    Target PCIe generation: 1, 2, or 3 (default: $TARGET_GEN)
  --help            Show this help

Environment variables (override flags):
  RDNA_ROOT_PORT    Same as --root-port
  RDNA_TARGET_GEN   Same as --target-gen

Examples:
  # Default: retrain 00:02.4 to Gen3 (will settle at Gen2 on B450+R9700 cable)
  sudo $(basename "$0")

  # Retrain a different port to Gen2
  sudo $(basename "$0") --root-port 00:01.1 --target-gen 2
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root-port) ROOT_PORT="$2"; shift 2 ;;
        --root-port=*) ROOT_PORT="${1#*=}"; shift ;;
        --target-gen) TARGET_GEN="$2"; shift 2 ;;
        --target-gen=*) TARGET_GEN="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root (writes to PCIe config space)." >&2
    echo "Re-run with: sudo $0 $*" >&2
    exit 1
fi

case "$TARGET_GEN" in
    1|2|3) ;;
    *) echo "Invalid --target-gen: $TARGET_GEN (must be 1, 2, or 3)" >&2; exit 1 ;;
esac

if ! command -v setpci >/dev/null 2>&1; then
    echo "setpci not found. Install pciutils: sudo apt install pciutils" >&2
    exit 1
fi

if ! lspci -s "$ROOT_PORT" >/dev/null 2>&1 || [[ -z "$(lspci -s "$ROOT_PORT")" ]]; then
    echo "Root port $ROOT_PORT not found." >&2
    echo "Available bridges:" >&2
    lspci | grep -i 'pci bridge' >&2
    exit 1
fi

# Find the PCIe Express capability offset (it's variable per device).
# lspci output line looks like: "Capabilities: [58] Express (v2) Root Port..."
# NOTE: uses grep -oP rather than awk's 3-arg match() — the latter is a
# gawk extension and fails on Ubuntu's default mawk with
# "awk: line 2: syntax error at or near ,".
EXPRESS_CAP_OFFSET=$(lspci -vvv -s "$ROOT_PORT" 2>/dev/null \
    | grep -oP 'Capabilities: \[\K[0-9a-fA-F]+(?=\] Express)' \
    | head -n1)

if [[ -z "$EXPRESS_CAP_OFFSET" ]]; then
    echo "Could not find PCIe Express capability on $ROOT_PORT." >&2
    exit 1
fi

# Compute register offsets from the Express capability base.
# Link Control  = cap_base + 0x10
# Link Control 2 = cap_base + 0x30
LNK_CTL_OFF=$(printf "%x" $((0x$EXPRESS_CAP_OFFSET + 0x10)))
LNK_CTL2_OFF=$(printf "%x" $((0x$EXPRESS_CAP_OFFSET + 0x30)))

echo "=== Target root port: $ROOT_PORT ==="
lspci -s "$ROOT_PORT"
echo "    PCIe Express cap offset = 0x$EXPRESS_CAP_OFFSET"
echo "    LnkCtl  register offset = 0x$LNK_CTL_OFF"
echo "    LnkCtl2 register offset = 0x$LNK_CTL2_OFF"
echo

echo "=== Current link state ==="
lspci -vvv -s "$ROOT_PORT" | grep -E 'LnkCap:|LnkSta:|LnkCtl2:' | sed 's/^/    /'
echo

# Read current LnkCtl2.
LNKCTL2_BEFORE=$(setpci -s "$ROOT_PORT" "$LNK_CTL2_OFF.W")
echo "LnkCtl2 before = 0x$LNKCTL2_BEFORE"

# Mask 0x2F = bits[3:0] (Target Link Speed) + bit 5 (Hardware Autonomous
# Speed Disable). We set Target = $TARGET_GEN and clear bit 5.
NEW_VALUE=$(printf "%02x" "$TARGET_GEN")
echo "=== Setting Target Link Speed = Gen$TARGET_GEN, clearing SpeedDis ==="
setpci -s "$ROOT_PORT" "$LNK_CTL2_OFF.W=$NEW_VALUE:2F"
LNKCTL2_AFTER=$(setpci -s "$ROOT_PORT" "$LNK_CTL2_OFF.W")
echo "LnkCtl2 after  = 0x$LNKCTL2_AFTER"
echo

echo "=== Triggering link retrain (LnkCtl bit 5) ==="
setpci -s "$ROOT_PORT" "$LNK_CTL_OFF.W=20:20"
sleep 1

# Second retrain attempt often helps the link climb one more gen.
setpci -s "$ROOT_PORT" "$LNK_CTL_OFF.W=20:20"
sleep 1
echo

echo "=== Final link state ==="
lspci -vvv -s "$ROOT_PORT" | grep -E 'LnkCap:|LnkSta:|LnkCtl2:' | sed 's/^/    /'
echo

# Extract negotiated speed for a friendly summary line.
# (grep -oP for the same mawk-compatibility reason as above.)
FINAL_SPEED=$(lspci -vvv -s "$ROOT_PORT" \
    | grep -m1 'LnkSta:' \
    | grep -oP 'Speed \K[0-9.]+GT/s')
case "$FINAL_SPEED" in
    2.5GT/s) FINAL_GEN="Gen1" ;;
    5GT/s)   FINAL_GEN="Gen2" ;;
    8GT/s)   FINAL_GEN="Gen3" ;;
    16GT/s)  FINAL_GEN="Gen4" ;;
    32GT/s)  FINAL_GEN="Gen5" ;;
    *)       FINAL_GEN="?" ;;
esac

echo "==============================================================="
echo "  Negotiated link: $FINAL_SPEED ($FINAL_GEN)  (requested Gen$TARGET_GEN)"
echo "==============================================================="

if [[ "$FINAL_GEN" == "Gen$TARGET_GEN" ]]; then
    echo "  Target speed reached."
elif [[ "$FINAL_SPEED" != "" ]]; then
    echo "  Link could not train to Gen$TARGET_GEN — signal integrity limit"
    echo "  of the riser/cable. Settled at the best achievable speed."
else
    echo "  WARNING: could not read final link state."
fi
echo
echo "NOTE: this setting resets on reboot. Re-run after every boot, or"
echo "      install as a systemd oneshot (see force-pcie-link.service)."
