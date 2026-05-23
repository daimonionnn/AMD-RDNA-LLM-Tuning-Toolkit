# R9700 Overclocking / Undervolting Findings

Community findings from [RDNA4 Llama Experiments — Squeezing Every Token/s from the R9700](https://github.com/ggml-org/llama.cpp/discussions/21043).

---

## LACT Settings (reported by zedbytes)

| Setting | Value |
|---|---|
| Power limit | 210 W |
| GPU Clock Offset | -500 MHz |
| Max VRAM Clock | 2518 MHz |
| Min VRAM Clock | 194 MHz |
| GPU Voltage Offset | -88 mV |

---

## Safe Power Boost (reported by digitalscream)

- Set power limit to **330 W** and profile to **COMPUTE** in LACT
- Result: +6% TG on dual-GPU setup (102 → 110 t/s)

> **WARNING:** Do NOT touch memory clocks in LACT — the detected defaults are wrong.
> Changing them can cause fans to max out, GPU to become undetectable, and may
> require booting into recovery mode and deleting `/etc/lact/config.yaml` to recover.

---

## Performance Level

### Option A — sysfs (per card)

```bash
echo "high" > /sys/class/drm/card1/device/power_dpm_force_performance_level
```

### Option B — rocm-smi

```bash
rocm-smi --setperflevel auto
```

> **Finding (yiwiz-sai):** `auto` outperforms `high` during sustained compute workloads.
> Under full LLM inference load, `auto` reaches 3000+ MHz SCLK while using only ~20 W
> idle (vs ~50 W for `high`). Use `auto` unless you have a specific reason for `high`.

---

## PCIe ASPM Performance Mode

**+10.8% decode speed on dense models (27B)** by eliminating PCIe L1 exit latency.

```bash
echo "performance" | sudo tee /sys/module/pcie_aspm/parameters/policy
```

To make persistent, add to kernel boot parameters in `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm.policy=performance"
```

Then run `sudo update-grub`.

> **Note:** Only dense models benefit significantly (+10.8%). MoE models see ~0% gain
> because they batch work more efficiently and hide PCIe latency.

---

## Disable ECC (~1 t/s decode gain)

Add to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`:

```
amdgpu.ras_enable=0
```

Run `sudo update-grub` and reboot. Verify with:

```bash
cat /sys/module/amdgpu/parameters/ras_enable
```

---

## Recommended GRUB Cmdline (combined)

```
GRUB_CMDLINE_LINUX_DEFAULT="amdgpu.runpm=0 pcie_aspm.policy=performance amdgpu.ras_enable=0"
```

> `amdgpu.runpm=0` is added to prevent GPU wake-up issues (without it, `rocminfo`
> may fail to detect the GPU on some systems).

---

## Notes

- The R9700 uses a 256-bit memory bus (640 GB/s) — LLM decode is **memory-bandwidth bound**.
  Overclocking the GPU core has diminishing returns; VRAM clock and PCIe bandwidth matter more.
- Under ROCm/HIP with straight compute (no rendering), the GPU can auto-overclock to 3.4 GHz+.
- Trying to squeeze an extra 50–150 MHz from VRAM is the most impactful hardware-level change.
