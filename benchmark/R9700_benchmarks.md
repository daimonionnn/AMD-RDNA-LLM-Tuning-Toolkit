# R9700 Benchmark Results (AMD Radeon GFX1201)

## Run Parameters
- **GPU Backend:** Vulkan + Rocm 7.2.3 (reference settings + overclocked)
- **VRAM Offloading:** Full (Enabled, `-ngl 99`)
- **Flash Attention:** Enabled (`-fa 1`)
- **Context Windows (Prompt Tokens):** 1024, 4096, 32768
- **Generation Tokens:** 128
- **llama.cpp Version:** Build `073bb2c`


## Vulkan

## Model: Qwen 3.6 27B

*(Note: `llama-bench` outputs the model designator as `qwen36 27B` rather than 3.6. This is because the internal GGUF metadata architecture maps natively to the `qwen36` structure branch inside `llama.cpp`.)*

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |          pp1024 |        889.16 ± 1.01 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |          pp4096 |        868.53 ± 2.82 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |         pp32768 |        729.89 ± 1.29 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |           tg128 |         30.33 ± 0.04 |



----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf  + KV cache set to Q8 instead of FP16
----------------------------------------------------------
Command: llama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | type_k | type_v | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | -: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |          pp1024 |        874.26 ± 0.90 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |          pp4096 |        839.25 ± 2.74 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |         pp32768 |        628.97 ± 1.94 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |           tg128 |         30.04 ± 0.01 |


## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium        |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |          pp1024 |        719.26 ± 0.18 |
| gemma4 31B Q4_K - Medium        |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |          pp4096 |        694.06 ± 0.76 |
| gemma4 31B Q4_K - Medium        |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |         pp32768 |        569.66 ± 0.07 |
| gemma4 31B Q4_K - Medium        |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |           tg128 |         27.73 ± 0.04 |



## Model: Gemma4 26B
----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 26B Q4_K - Medium        |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |          pp1024 |      2936.84 ± 27.26 |
| gemma4 26B Q4_K - Medium        |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |          pp4096 |      2860.95 ± 14.30 |
| gemma4 26B Q4_K - Medium        |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |         pp32768 |       2318.21 ± 5.86 |
| gemma4 26B Q4_K - Medium        |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |           tg128 |        108.72 ± 0.52 |


## RoCm 7.2.3


## Model: Qwen 3.6 27B

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1036.56 ± 0.79 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |        974.38 ± 2.62 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        659.45 ± 1.73 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         27.42 ± 0.04 |



## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        849.32 ± 0.65 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        743.82 ± 0.19 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        467.26 ± 0.04 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         25.53 ± 0.06 |


## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3427.14 ± 37.01 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |       3018.94 ± 9.62 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1887.41 ± 9.41 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         93.39 ± 0.91 |



-----------------------------------------------------------------------------------------------------------------------------
## Memory Overclocked + Undervolt GPU benchmarks
    Memory-clock 1350
    Undervolt -75mV
    TDP 300W (same as reference)
-----------------------------------------------------------------------------------------------------------------------------


## Model: Qwen 3.6 27B
----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1076.88 ± 0.86 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1011.53 ± 1.97 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        690.40 ± 1.08 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.80 ± 0.03 |


## Model: Gemma4 31B
----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        892.00 ± 0.25 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        779.73 ± 0.18 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        488.26 ± 0.03 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         26.77 ± 0.06 |

## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3440.87 ± 20.10 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |      3042.79 ± 26.98 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1946.48 ± 4.51 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         96.61 ± 1.56 |





-----------------------------------------------------------------------------------------------------------------------------
## TDP 210W (Memory Overclocked + Undervolt) GPU benchmarks
    Memory-clock 1350
    Undervolt -75mV
    TDP 210W 
-----------------------------------------------------------------------------------------------------------------------------


## Model: Qwen 3.6 27B
----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |        962.04 ± 0.67 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |        907.26 ± 1.59 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        619.88 ± 2.20 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         26.28 ± 0.03 |



## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        795.82 ± 0.28 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        698.59 ± 0.47 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        440.89 ± 0.03 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         23.82 ± 0.04 |



## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3119.01 ± 13.34 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |      2763.28 ± 14.72 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1762.45 ± 2.80 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         90.08 ± 0.52 |




## Overclock benchmark UPDATE:

TheRock nightly 7.14.0~20260522

Benchmark run with preset /tunning/tune_r9700_max.sh
( memory-clock 1350, undervolt-offset -120m, tdp 300 )


## PCIe ASPM Performance Mode
echo "performance" | sudo tee /sys/module/pcie_aspm/parameters/policy

## Performance level
rocm-smi --setperflevel auto


---------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

gml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1147.43 ± 1.18 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1083.27 ± 1.79 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        724.73 ± 1.59 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.23 ± 0.05 |


