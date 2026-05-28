#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$SCRIPT_DIR/../lib/rdna_detect.sh"

PCI_ID=""
GPUS_SELECTOR="${RDNA_GPUS:-}"
MEMORY_CLOCK_MHZ=""
UNDERVOLT_OFFSET_MV=""
TDP_WATTS=""
CORE_CLOCK_MAX_MHZ=""
FAN_SPEED_PCT=""
FAN_CURVE=""
FAN_AUTO=0
DRY_RUN=0
STATUS_ONLY=0
RESET_ONLY=0

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage: sudo ./$SCRIPT_NAME [options]

Tune an AMD Radeon Navi GPU through the amdgpu sysfs interface.

Options:
  --gpus SELECTOR         Which RDNA GPUs to act on. Forms:
                            all              every detected RDNA GPU (default)
                            N                first N RDNA GPUs (PCI-BDF order)
                            i,j,k            specific RDNA indices (zero-based)
                            BDF[,BDF...]     explicit PCI BDFs, e.g. 0000:03:00.0
                          Env-var fallback: RDNA_GPUS=<selector>
  --pci-id ID             Shorthand for --gpus <BDF>. PCI ID in the form
                          0000:XX:YY.Z. Mutually exclusive with --gpus.
  --memory-clock MHz      Set max memory clock. Default: unchanged
  --undervolt-offset mV   Set VDDGFX offset. Default: unchanged
  --tdp watts             Set board power cap in watts. Default: unchanged
  --core-clock-max MHz    Set max GPU core clock. Default: unchanged
  --fan-speed-pct PCT     Set fan speed to a fixed percentage (0-100). Enables manual fan control.
  --fan-curve CURVE       Set a custom 5-point fan curve. Format: "T0 P0 T1 P1 T2 P2 T3 P3 T4 P4"
                          where T=hotspot temp (°C), P=fan speed (%). Temps must be ascending.
                          Example: "25 25 50 30 70 34 85 37 100 40"
  --fan-auto              Return fan to automatic/driver-controlled speed
  --status                Print detected paths and current overdrive values, then exit
  --reset                 Reset overdrive values to driver defaults, then exit
  --dry-run               Show what would be written without changing anything
  -h, --help              Show this help message

Examples:
  sudo ./$SCRIPT_NAME                              # tune ALL detected RDNA GPUs
  sudo ./$SCRIPT_NAME --gpus 1                     # tune only the first one
  sudo ./$SCRIPT_NAME --gpus 0,2 --tdp 200         # tune RDNA indices 0 and 2
  sudo ./$SCRIPT_NAME --pci-id 0000:07:00.0 --core-clock-max 2550
  sudo ./$SCRIPT_NAME --status

Notes:
  * The kernel interface uses millivolts for voltage offset. The requested
    "-80mw" value is applied as -80 mV.
    * Overdrive must be enabled first.
        Fedora/RHEL example:
      sudo grubby --update-kernel=ALL --args="amdgpu.ppfeaturemask=0xffffffff"
        Ubuntu/Debian GRUB example:
            sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.ppfeaturemask=0xffffffff"/' /etc/default/grub
            sudo update-grub
    Then reboot.
EOF
}

log() {
    printf '[*] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

die() {
    printf '[x] %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

reexec_as_root_if_needed() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        need_cmd sudo
        exec sudo -E bash "$0" "$@"
    fi
}

auto_detect_pci_id() {
    local detected
    detected=$(lspci -Dnnd 1002: | awk '/VGA compatible controller|Display controller|3D controller/ { print $1; exit }')
    [[ -n "$detected" ]] || die "Could not auto-detect an AMD GPU PCI ID. Use --pci-id."
    printf '%s\n' "$detected"
}

validate_pci_id() {
    [[ "$1" =~ ^0000:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]] || die "Invalid PCI ID: $1"
}

require_integer() {
    local value="$1"
    local name="$2"
    [[ "$value" =~ ^-?[0-9]+$ ]] || die "$name must be an integer, got: $value"
}

find_card_name() {
    local pci_id="$1"
    local drm_dir="/sys/bus/pci/devices/$pci_id/drm"
    [[ -d "$drm_dir" ]] || die "PCI device $pci_id not found or it has no DRM node."

    local card_name
    card_name=$(find "$drm_dir" -maxdepth 1 -mindepth 1 -printf '%f\n' | grep -E '^card[0-9]+$' | sort | head -n 1 || true)
    [[ -n "$card_name" ]] || die "Could not resolve a DRM card for $pci_id"
    printf '%s\n' "$card_name"
}

find_hwmon_dir() {
    local card_path="$1"
    find "$card_path/device/hwmon" -mindepth 1 -maxdepth 1 -type d -name 'hwmon*' | head -n 1 || true
}

find_gpu_od_fan_dir() {
    local card_path="$1"
    local d="$card_path/device/gpu_od/fan_ctrl"
    [[ -d "$d" ]] && printf '%s\n' "$d" || true
}

read_file_trimmed() {
    local path="$1"
    [[ -r "$path" ]] || return 1
    tr -d '\000\r' < "$path"
}

kernel_cmdline_has_ppfeaturemask() {
    grep -q 'amdgpu\.ppfeaturemask=' /proc/cmdline
}

die_overdrive_unavailable() {
    local pci_id="$1"
    local card_path="$2"
    local node="$card_path/device/pp_od_clk_voltage"

    if [[ ! -e "$node" ]]; then
        warn "The overdrive sysfs node does not exist for $pci_id: $node"
        if kernel_cmdline_has_ppfeaturemask; then
            die "Overdrive is still unavailable for this GPU even though a ppfeaturemask is present. Check whether this kernel/driver exposes pp_od_clk_voltage for your R9700."
        fi

        die "Overdrive is not enabled for this GPU. Your current kernel command line does not include amdgpu.ppfeaturemask. Enable it, reboot, then try again. On Ubuntu/Debian, add amdgpu.ppfeaturemask=0xffffffff to GRUB and run update-grub."
    fi

    if [[ ! -w "$node" ]]; then
        die "Found $node, but it is not writable. Run the script with sudo/root and make sure overdrive is enabled."
    fi
}

write_value() {
    local value="$1"
    local path="$2"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] echo "%s" > %s\n' "$value" "$path"
        return 0
    fi

    printf '%s\n' "$value" > "$path"
}

extract_range_pair() {
    local label="$1"
    local source="$2"
    sed -nE "s/^(OD_)?${label}(_OFFSET)?:[[:space:]]*([-0-9]+)M[hH][zZ]?[[:space:]]+([-0-9]+)M[hH][zZ]?.*$/\3 \4/p" <<< "$source" | head -n 1
}

extract_voltage_range() {
    local source="$1"
    sed -nE 's/^(OD_)?VDDGFX_OFFSET:[[:space:]]*([-0-9]+)m[vV][[:space:]]+([-0-9]+)m[vV].*$/\2 \3/p' <<< "$source" | head -n 1
}

assert_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local label="$4"

    if (( value < min || value > max )); then
        die "$label $value is outside the supported range [$min, $max]"
    fi
}

show_status() {
    local pci_id="$1"
    local card_name="$2"
    local card_path="$3"
    local hwmon_dir="$4"

    printf 'PCI ID      : %s\n' "$pci_id"
    printf 'DRM card    : %s\n' "$card_name"
    printf 'Card path   : %s\n' "$card_path"
    if [[ -n "$hwmon_dir" ]]; then
        printf 'HWMON path  : %s\n' "$hwmon_dir"
    else
        printf 'HWMON path  : not found\n'
    fi
    printf '\npp_od_clk_voltage:\n'
    read_file_trimmed "$card_path/device/pp_od_clk_voltage" || true
    printf '\npower_dpm_force_performance_level:\n'
    read_file_trimmed "$card_path/device/power_dpm_force_performance_level" || true
    if [[ -n "$hwmon_dir" && -r "$hwmon_dir/power1_cap" ]]; then
        local power_uw power_w
        power_uw=$(<"$hwmon_dir/power1_cap")
        power_w=$(( power_uw / 1000000 ))
        printf '\npower1_cap  : %s uW (~%s W)\n' "$power_uw" "$power_w"
    fi
    if [[ -n "$hwmon_dir" && -r "$hwmon_dir/pwm1" ]]; then
        local pwm_val pct
        pwm_val=$(<"$hwmon_dir/pwm1")
        pct=$(( pwm_val * 100 / 255 ))
        printf '\nfan pwm     : %s (~%s%%)\n' "$pwm_val" "$pct"
    fi
    local gpu_od_fan_dir
    gpu_od_fan_dir="$(find_gpu_od_fan_dir "$card_path")"
    if [[ -n "$gpu_od_fan_dir" && -r "$gpu_od_fan_dir/fan_curve" ]]; then
        printf '\nfan_curve (gpu_od):\n'
        cat "$gpu_od_fan_dir/fan_curve"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gpus)
                [[ $# -ge 2 ]] || die "--gpus requires a value"
                GPUS_SELECTOR="$2"
                shift 2
                ;;
            --pci-id)
                [[ $# -ge 2 ]] || die "--pci-id requires a value"
                PCI_ID="$2"
                shift 2
                ;;
            --memory-clock)
                [[ $# -ge 2 ]] || die "--memory-clock requires a value"
                MEMORY_CLOCK_MHZ="$2"
                shift 2
                ;;
            --undervolt-offset)
                [[ $# -ge 2 ]] || die "--undervolt-offset requires a value"
                UNDERVOLT_OFFSET_MV="$2"
                shift 2
                ;;
            --tdp)
                [[ $# -ge 2 ]] || die "--tdp requires a value"
                TDP_WATTS="$2"
                shift 2
                ;;
            --core-clock-max)
                [[ $# -ge 2 ]] || die "--core-clock-max requires a value"
                CORE_CLOCK_MAX_MHZ="$2"
                shift 2
                ;;
            --fan-speed-pct)
                [[ $# -ge 2 ]] || die "--fan-speed-pct requires a value"
                FAN_SPEED_PCT="$2"
                shift 2
                ;;
            --fan-curve)
                [[ $# -ge 2 ]] || die "--fan-curve requires a value"
                FAN_CURVE="$2"
                shift 2
                ;;
            --fan-auto)
                FAN_AUTO=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --status)
                STATUS_ONLY=1
                shift
                ;;
            --reset)
                RESET_ONLY=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

apply_to_gpu() {
    local PCI_ID="$1"
    validate_pci_id "$PCI_ID"

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then require_integer "$MEMORY_CLOCK_MHZ" "memory clock"; fi
    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then require_integer "$UNDERVOLT_OFFSET_MV" "undervolt offset"; fi
    if [[ -n "$TDP_WATTS" ]]; then require_integer "$TDP_WATTS" "TDP"; fi
    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then require_integer "$CORE_CLOCK_MAX_MHZ" "core clock max"; fi
    if [[ -n "$FAN_SPEED_PCT" ]]; then
        require_integer "$FAN_SPEED_PCT" "fan speed"
        (( FAN_SPEED_PCT >= 0 && FAN_SPEED_PCT <= 100 )) || die "Fan speed must be 0-100, got: $FAN_SPEED_PCT"
    fi
    if [[ -n "$FAN_CURVE" ]]; then
        local fc_arr
        read -r -a fc_arr <<< "$FAN_CURVE"
        [[ ${#fc_arr[@]} -eq 10 ]] || die "--fan-curve requires exactly 10 values (T0 P0 T1 P1 ... T4 P4), got ${#fc_arr[@]}"
        local i prev_t=-1
        for (( i=0; i<10; i+=2 )); do
            require_integer "${fc_arr[$i]}" "fan curve temp[$((i/2))]"
            require_integer "${fc_arr[$((i+1))]}" "fan curve speed[$((i/2))]"
            (( fc_arr[i] > prev_t )) || die "Fan curve temperatures must be strictly ascending (point $((i/2)))"
            prev_t=${fc_arr[$i]}
        done
    fi
    if [[ "$FAN_AUTO" -eq 1 && ( -n "$FAN_SPEED_PCT" || -n "$FAN_CURVE" ) ]]; then
        die "--fan-auto cannot be combined with --fan-speed-pct or --fan-curve"
    fi
    if [[ -n "$FAN_SPEED_PCT" && -n "$FAN_CURVE" ]]; then
        die "--fan-speed-pct and --fan-curve are mutually exclusive"
    fi

    local card_name card_path hwmon_dir gpu_od_fan_dir od_dump od_range mclk_range sclk_range vddgfx_range
    local mclk_min mclk_max sclk_min sclk_max vddgfx_min vddgfx_max

    card_name="$(find_card_name "$PCI_ID")"
    card_path="/sys/class/drm/$card_name"
    hwmon_dir="$(find_hwmon_dir "$card_path")"
    gpu_od_fan_dir="$(find_gpu_od_fan_dir "$card_path")"

    [[ -w "$card_path/device/power_dpm_force_performance_level" ]] || die "Cannot write to $card_path/device/power_dpm_force_performance_level"
    die_overdrive_unavailable "$PCI_ID" "$card_path"

    if [[ "$STATUS_ONLY" -eq 1 ]]; then
        show_status "$PCI_ID" "$card_name" "$card_path" "$hwmon_dir"
        exit 0
    fi

    log "Target GPU: $card_name ($PCI_ID)"
    log "Using card path: $card_path"

    if [[ "$RESET_ONLY" -eq 1 ]]; then
        log "Resetting overdrive clock/voltage values to defaults"
        write_value "manual" "$card_path/device/power_dpm_force_performance_level"
        write_value "r" "$card_path/device/pp_od_clk_voltage"
        write_value "auto" "$card_path/device/power_dpm_force_performance_level"

        if [[ -n "$hwmon_dir" ]]; then
            local cap_default="$hwmon_dir/power1_cap_default"
            local cap_node="$hwmon_dir/power1_cap"
            if [[ -r "$cap_default" && -w "$cap_node" ]]; then
                local default_uw
                default_uw=$(<"$cap_default")
                log "Resetting power cap to default: $(( default_uw / 1000000 )) W"
                write_value "$default_uw" "$cap_node"
            else
                warn "Could not reset power cap: power1_cap_default not readable or power1_cap not writable"
            fi
            if [[ -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
                log "Resetting fan control to automatic"
                write_value "2" "$hwmon_dir/pwm1_enable"
            fi
        fi
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            log "Resetting gpu_od fan curve to driver defaults"
            write_value "r" "$gpu_od_fan_dir/fan_curve"
        fi

        log "Reset complete"
        exit 0
    fi

    od_dump="$(read_file_trimmed "$card_path/device/pp_od_clk_voltage")"
    od_range="$(sed -n '/^OD_RANGE:/,$p' <<< "$od_dump")"

    mclk_range="$(extract_range_pair 'MCLK' "$od_range")"
    [[ -n "$mclk_range" ]] || die "Could not read MCLK range from pp_od_clk_voltage"
    read -r mclk_min mclk_max <<< "$mclk_range"

    sclk_range="$(extract_range_pair 'SCLK' "$od_range")"
    [[ -n "$sclk_range" ]] || die "Could not read SCLK range from pp_od_clk_voltage"
    read -r sclk_min sclk_max <<< "$sclk_range"

    vddgfx_range="$(extract_voltage_range "$od_range")"
    [[ -n "$vddgfx_range" ]] || die "Could not read VDDGFX offset range from pp_od_clk_voltage"
    read -r vddgfx_min vddgfx_max <<< "$vddgfx_range"

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then assert_in_range "$MEMORY_CLOCK_MHZ" "$mclk_min" "$mclk_max" "Memory clock"; fi
    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then assert_in_range "$UNDERVOLT_OFFSET_MV" "$vddgfx_min" "$vddgfx_max" "Undervolt offset"; fi
    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then assert_in_range "$CORE_CLOCK_MAX_MHZ" "$sclk_min" "$sclk_max" "Core clock max"; fi

    log "Switching GPU to manual performance mode"
    write_value "manual" "$card_path/device/power_dpm_force_performance_level"

    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then
        log "Applying undervolt offset: ${UNDERVOLT_OFFSET_MV} mV"
        write_value "vo $UNDERVOLT_OFFSET_MV" "$card_path/device/pp_od_clk_voltage"
    else
        log "Leaving undervolt offset unchanged"
    fi

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then
        log "Applying max memory clock: ${MEMORY_CLOCK_MHZ} MHz"
        write_value "m 1 $MEMORY_CLOCK_MHZ" "$card_path/device/pp_od_clk_voltage"
    else
        log "Leaving max memory clock unchanged"
    fi

    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then
        log "Applying max core clock: ${CORE_CLOCK_MAX_MHZ} MHz"
        write_value "s 1 $CORE_CLOCK_MAX_MHZ" "$card_path/device/pp_od_clk_voltage"
    else
        log "Leaving max core clock unchanged"
    fi

    log "Committing overdrive changes"
    write_value "c" "$card_path/device/pp_od_clk_voltage"

    if [[ -n "$TDP_WATTS" ]]; then
        if [[ -z "$hwmon_dir" || ! -e "$hwmon_dir/power1_cap" ]]; then
            warn "Could not find power1_cap under $card_path/device/hwmon; skipping TDP change"
        else
            local power_cap_min power_cap_max target_power_uw
            target_power_uw=$(( TDP_WATTS * 1000000 ))
            power_cap_min=$(<"$hwmon_dir/power1_cap_min")
            power_cap_max=$(<"$hwmon_dir/power1_cap_max")
            assert_in_range "$target_power_uw" "$power_cap_min" "$power_cap_max" "Power cap (uW)"

            log "Applying board power cap: ${TDP_WATTS} W"
            write_value "$target_power_uw" "$hwmon_dir/power1_cap"
        fi
    else
        log "Leaving board power cap unchanged"
    fi

    if [[ -n "$FAN_SPEED_PCT" ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            # Clamp to hardware minimum of 25%
            local clamped_pct=$FAN_SPEED_PCT
            if (( clamped_pct < 25 )); then
                warn "Fan speed ${FAN_SPEED_PCT}% is below hardware minimum 25%; clamping to 25%"
                clamped_pct=25
            fi
            log "Setting flat fan curve: ${clamped_pct}% across all temperature points (gpu_od)"
            write_value "0 25 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "1 50 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "2 70 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "3 85 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "4 100 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
        elif [[ -n "$hwmon_dir" && -w "$hwmon_dir/pwm1" ]]; then
            local pwm_max=255
            [[ -r "$hwmon_dir/pwm1_max" ]] && pwm_max=$(<"$hwmon_dir/pwm1_max")
            local pwm_val=$(( FAN_SPEED_PCT * pwm_max / 100 ))
            if [[ -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
                log "Enabling manual fan control"
                write_value "1" "$hwmon_dir/pwm1_enable"
            fi
            log "Setting fan speed: ${FAN_SPEED_PCT}% (pwm ${pwm_val}/${pwm_max})"
            write_value "$pwm_val" "$hwmon_dir/pwm1"
        else
            warn "No writable fan control interface found for $card_name; skipping fan control"
        fi
    elif [[ -n "$FAN_CURVE" ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            local fc_arr
            read -r -a fc_arr <<< "$FAN_CURVE"
            log "Setting fan curve (gpu_od):"
            local i pt
            for (( i=0, pt=0; i<10; i+=2, pt++ )); do
                local t=${fc_arr[$i]} p=${fc_arr[$((i+1))]}
                if (( p < 25 )); then
                    warn "Fan curve point ${pt}: speed ${p}% below hardware minimum 25%; clamping"
                    p=25
                fi
                log "  point ${pt}: ${t}C → ${p}%"
                write_value "${pt} ${t} ${p}" "$gpu_od_fan_dir/fan_curve"
            done
        else
            warn "gpu_od fan_curve interface not available for $card_name; skipping fan curve"
        fi
    elif [[ "$FAN_AUTO" -eq 1 ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            log "Restoring gpu_od fan curve to driver defaults"
            write_value "r" "$gpu_od_fan_dir/fan_curve"
        elif [[ -n "$hwmon_dir" && -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
            log "Restoring automatic fan control"
            write_value "2" "$hwmon_dir/pwm1_enable"
        else
            warn "No writable fan control interface found for $card_name; skipping fan auto restore"
        fi
    else
        log "Leaving fan control unchanged"
    fi

    printf '\n'
    show_status "$PCI_ID" "$card_name" "$card_path" "$hwmon_dir"
}

main() {
    parse_args "$@"
    reexec_as_root_if_needed "$@"

    need_cmd lspci
    need_cmd find
    need_cmd grep
    need_cmd sed
    need_cmd awk

    if [[ -n "$PCI_ID" && -n "$GPUS_SELECTOR" ]]; then
        die "--pci-id and --gpus are mutually exclusive"
    fi

    local -a targets=()
    if [[ -n "$PCI_ID" ]]; then
        validate_pci_id "$PCI_ID"
        targets=("$PCI_ID")
    else
        # Default to "all" when nothing is specified.
        local selector="${GPUS_SELECTOR:-all}"
        mapfile -t targets < <(rdna_resolve_selector "$selector") \
            || die "Failed to resolve --gpus selector '$selector'"
    fi

    if (( ${#targets[@]} == 0 )); then
        die "No GPUs selected."
    fi

    log "Selected ${#targets[@]} GPU(s): ${targets[*]}"

    local idx=0 bdf
    for bdf in "${targets[@]}"; do
        idx=$((idx + 1))
        printf '\n==========================================================\n'
        printf ' GPU %d/%d: %s\n' "$idx" "${#targets[@]}" "$bdf"
        printf '==========================================================\n'
        apply_to_gpu "$bdf"
    done
}

main "$@"
