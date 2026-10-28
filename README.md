# Recipes

Measured recipes for running open models on modest local hardware. Each folder is one model: the exact command, the settings that won, the numbers behind them and the scripts to reproduce them.

[Versión en español](README.es.md)

## Image models

| Model | Hardware | Recipe |
|---|---|---|
| Qwen-Image 2.1 (text-to-image) | RTX 3050 6 GB · 16 GB RAM | [English](Qwen-Image-2.1/README.md) · [Español](Qwen-Image-2.1/README.es.md) |
| Qwen-Image 2.1 Turbo (text-to-image, 8 steps) | RTX 3050 6 GB · 16 GB RAM | [English](Qwen-Image-2.1-Turbo/README.md) · [Español](Qwen-Image-2.1-Turbo/README.es.md) |
| FLUX.3 Image Klein (text-to-image, 8 steps) | RTX 3050 6 GB · 16 GB RAM | [English](FLUX.3-Image-Klein/README.md) · [Español](FLUX.3-Image-Klein/README.es.md) |

## Text models

Four models with [llama.cpp](https://github.com/ggml-org/llama.cpp) and 128k context, each measured on two machines. Each recipe covers both.

### Measured with a GPU

Desktop: **RTX 3050 6 GB VRAM** · i5-9400 · **16 GB RAM** · llama.cpp b11580 (CUDA)

| Model | Setup | Decode | Prompt processing | Coding agent (Pi) | Recipe |
|---|---|---|---|---|---|
| LFM2.5-24B-A2B | QAD-Q4_0, experts partly in RAM | 33.7 tok/s | 906 tok/s | 6 / 9 | [English](LFM2.5-24B-A2B/README.md) · [Español](LFM2.5-24B-A2B/README.es.md) |
| MiniCPM5-2B | Q4_K_M + DSpark draft | 93.8 tok/s | 2356 tok/s | **7 / 9** | [English](MiniCPM5-2B/README.md) · [Español](MiniCPM5-2B/README.es.md) |
| LFM2.5-2.6B | Q4_K_M + DSpark draft | **128 tok/s** | 2477 tok/s | 1 / 9 | [English](LFM2.5-2.6B/README.md) · [Español](LFM2.5-2.6B/README.es.md) |
| LFM3-1.7B ¹ | Q4_K_M | 120 tok/s | **~4450 tok/s** | 5 / 9 ² | [English](LFM3-1.7B/README.md) · [Español](LFM3-1.7B/README.es.md) |

### Measured on CPU only

Laptop: **no GPU** · i7-13620H · **24 GB RAM** · llama.cpp b11588 (CPU)

| Model | Setup | Decode | Prompt processing | RAM with 128k | Coding benchmark | Recipe |
|---|---|---|---|---|---|---|
| LFM2.5-24B-A2B | QAD-Q4_0 | 26–30 tok/s | ~72 tok/s | 15.6 GB | **7.0 / 11** | [English](LFM2.5-24B-A2B/README.md) · [Español](LFM2.5-24B-A2B/README.es.md) |
| MiniCPM5-2B | IQ4_NL | 28–30 tok/s | ~98 tok/s | 7.0 GB | 6.3 / 11 | [English](MiniCPM5-2B/README.md) · [Español](MiniCPM5-2B/README.es.md) |
| LFM2.5-2.6B | QAD-Q4_0 | 29.2 tok/s | ~98 tok/s | 3.7 GB | 6.3 / 11 | [English](LFM2.5-2.6B/README.md) · [Español](LFM2.5-2.6B/README.es.md) |
| LFM3-1.7B ¹ | QAD-Q4_0 | **37 tok/s** | **~153 tok/s** | **2.6 GB** | 4.7 / 11 | [English](LFM3-1.7B/README.md) · [Español](LFM3-1.7B/README.es.md) |

**Try it on your machine:** [`tools/quick-bench.py`](tools/README.md) runs a recipe and measures prefill, decode and decode with a full context in a few minutes, with a table you can share.

Prompt processing on the GPU is with a 4k prompt; on the CPU, with 512–2048 tokens. The coding benchmark is 11 Python tasks with hidden tests (mean of 3 runs); the agent test is Pi on a small project, 3 tasks × 3 runs.

¹ LFM3-1.7B: llama.cpp b11940 on both machines, and coding benchmark with 8192 tokens per answer, like the others (6.0 / 11 with 32,768). It needs `max_tokens` 32768 to do well: see its recipe. ² With Pi 1.4.0; the others with Pi 1.0.3.

Contributions, especially results from other hardware, are welcome: see [CONTRIBUTING](CONTRIBUTING.md).

The scripts in this repository are MIT-licensed. Model weights are not included and keep their own licenses; each recipe says which.
