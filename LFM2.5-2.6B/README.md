# LFM2.5-2.6B on a 6 GB GPU and on a CPU-only laptop

A measured recipe for running [LFM2.5-2.6B](https://huggingface.co/LiquidAI/LFM2.5-2.6B) locally with [llama.cpp](https://github.com/ggml-org/llama.cpp), with 128k context, on two machines:

| | **Desktop** (GPU) | **Laptop** (CPU only) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB VRAM** | **None** (integrated graphics, not used) |
| CPU | Intel i5-9400, 6 cores | Intel i7-13620H, 6 performance + 4 efficiency cores |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, official CPU build |

LFM2.5-2.6B is a small hybrid model from Liquid AI (mostly convolution layers, 8 attention layers). It is **the fastest and lightest of the three recipes**: 128 tok/s on the desktop, 3.7 GB of RAM with 128k on the laptop. But in our agent test it was **not usable as a coding agent** (see [Quality](#quality)).

Every number on this page was measured on those two machines. The scripts that produced them are in [`scripts/`](scripts/) and the raw results in [`bench/`](bench/).

[Versión en español](README.es.md)

> [!NOTE]
> **License.** The weights are under the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/main/LICENSE): free for research and for commercial use by companies with less than 10 million USD in annual revenue.

## At a glance

| | **Desktop** · RTX 3050 6 GB + 16 GB RAM | **Laptop** · CPU only + 24 GB RAM |
|---|---|---|
| Quantization | Q4_K_M + DSpark draft | QAD-Q4_0 |
| Decode | **128 tok/s** | **29.2 tok/s** |
| Prompt processing | **2477 tok/s** (4k prompt) · 1795 (64k prompt) | **98 tok/s** (2048-token prompt) |
| Memory with 128k | 4.5 GB of VRAM | **3.7 GB** of RAM |
| Before the recipe | 96k of context in 5.0 GB of VRAM | 26.8 tok/s with Q4_K_M |
| Coding benchmark (11 tasks) | 5.7 / 11 (Q4_K_M) | 6.3 / 11 (QAD-Q4_0) |
| Coding agent (Pi, 9 runs) | **1 / 9** | not measured |

## Desktop recipe · RTX 3050 6 GB VRAM + 16 GB RAM

```bash
llama-server \
  -m LFM2.5-2.6B-Q4_K_M.gguf \
  -md LFM2.5-2.6B-DSpark-Q4_K_M.gguf \
  --spec-type draft-dspark --spec-draft-n-max 9 --spec-draft-n-min 0 \
  -ngl 99 -ngld 99 -fa on \
  -np 1 -c 131072 \
  -ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Flag | Why |
|---|---|
| `-md … --spec-type draft-dspark` | Speculative decoding with Liquid AI's DSpark draft: it proposes tokens and LFM2.5-2.6B checks them in one pass. **73 → 128 tok/s (+75 %).** The output keeps the main model's quality. |
| `--spec-draft-n-max 9` | Up to 9 proposed tokens per step. 9 beat 5 and 7 in two separate rounds (at temperature 0.1 and 0). Turning on the confidence head (`--spec-draft-p-min` 0.3 or 0.5) made it slower, so it stays at the default (0). |
| `-c 131072` with `-ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0` | 128k with the KV cache in q8_0, for the model and the draft. It takes **less** VRAM than the previous 96k without quantization (4561 against 4999 MiB) at the same speed. 128k unquantized does not fit. |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.1` | Liquid AI's recommended sampling. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-speed-dark.webp">
  <img alt="Decode speed on the RTX 3050 with and without the DSpark draft" src="assets/gpu-speed.webp">
</picture>

**It handles long prompts well.** Prompt processing goes from 2477 tok/s with a 4k prompt to 1795 with 64k (−28 %). With only 8 attention layers, a long context costs it much less than MiniCPM5-2B (−64 %).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/prefill-context-dark.webp">
  <img alt="Prompt processing against prompt length for LFM2.5-2.6B and MiniCPM5-2B" src="assets/prefill-context.webp">
</picture>

**It always thinks first.** Its chat template always opens a thinking block, and `--reasoning off` has no effect on it, because the template has no switch for it. Getting direct answers needs a modified template that closes the block straight away.

## Laptop recipe · CPU only, no VRAM + 24 GB RAM

```bash
llama-server \
  -m LFM2.5-2.6B-QAD-Q4_0.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Flag | Why |
|---|---|
| QAD-Q4_0 | Liquid AI's quantization-aware Q4_0: **+9 % decode over Q4_K_M** (29.2 against 26.8 tok/s) and slightly closer to Q8_0 (see below). |
| repacking (on by default) | llama.cpp rearranges Q4_0 weights at load time for the CPU's vector instructions. **Do not use `--repack 0`** (or `--no-repack`): prompt processing drops by 43 % (98 → 56 tok/s). |
| `-t 6 -C 0x555 --cpu-strict 1` | One thread per performance core, each pinned to its own core. Measured with Q4_K_M, speed levels off between 4 and 6 threads (25.1 and 26.7 tok/s) and drops with 8, when efficiency cores join (24.5). |
| `-lm none` | Loads the model into RAM instead of mapping the file: **3.7 GB instead of 4.9 GB** with 128k. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-quants-dark.webp">
  <img alt="Decode speed and fidelity of Q4_K_M and QAD-Q4_0 on the laptop" src="assets/cpu-quants.webp">
</picture>

Fidelity is measured as the KL divergence from the Q8_0 file on wikitext-2: how far each quantization's predictions drift from the near-lossless version. Lower is closer.

| Quantization | Bits per weight | Size | KL vs Q8_0 | Same top token as Q8_0 |
|---|---|---|---|---|
| Q4_K_M | 4.97 | 1.67 GB | 0.157 | 81.4 % |
| **QAD-Q4_0** | 4.73 | 1.59 GB | **0.141** | 82.2 % |

One oddity: on wikitext-2 the Q8_0 file has a high perplexity (50–54) and the 4-bit files a lower one (45–47). We checked it with two builds and two machines (CPU and CUDA): it is real, not a bug in the test. Both 4-bit files drift from Q8_0 by a similar amount, which is what the KL shows.

A draft model is not used on the laptop: in an early test on this CPU, a DSpark draft made an LFM2.5 model slower (12.9 against 31.9 tok/s). The laptop's speed also depends on heat: a hot CPU loses about 2 tok/s within a couple of minutes.

## Quality

The coding benchmark is 11 Python functions checked by hidden pytest tests, 3 runs per configuration. The agent test is [Pi](https://github.com/badlogic/pi-mono) working on a small Python project (a 200-line expense tracker) with 3 tasks: add a feature, fix a bug described by a user, and refactor without changing behaviour. 3 runs per task, with the desktop recipes at 128k. Pi ran in a sandbox (bubblewrap) that only let it write to its copy of the project.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.webp">
  <img alt="Coding benchmark: mean tasks passed out of 11" src="assets/coding.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.webp">
  <img alt="Coding agent with Pi: tasks passed out of 9" src="assets/agent.webp">
</picture>

- **Coding benchmark: 6.3 / 11 with QAD-Q4_0 and 5.7 with Q4_K_M**, a tie within the noise: the laptop quantization does not lose quality. Both were served on the desktop GPU; the score depends on the file, not on the machine.
- **Agent: 1 / 9. Not usable as a coding agent.** It said tasks were done when they were not: in two bug-fix runs it changed nothing, and in two other runs it broke tests that passed before and still finished. In an earlier test without a sandbox it also wrote files outside its project folder. If you try it as an agent, run it in a sandbox.
- For coding agents on the same hardware, [MiniCPM5-2B](../MiniCPM5-2B/README.md) got 7 / 9 at a similar size.

## Subagents

A subagent plugin works with `-np 1`. The main session and the subagent take turns on the same server, and llama.cpp's `--cache-ram` (on by default) keeps the waiting conversation in RAM, so resuming does not reprocess it. **Do not set `--cache-ram 0`.** Measured with LFM2.5-24B-A2B on both machines: about 2–3 s per switch, against 40 s (desktop) and 2 minutes (laptop) without the cache. Details in the [LFM2.5-24B-A2B recipe](../LFM2.5-24B-A2B/README.md#subagents).

## Adapting it to your machine

The numbers above are for these two machines. What carries over:

- **The quantization choice, the draft settings (`n-max 9`) and the sampling** do not depend on the hardware.
- **More VRAM (desktop):** with 8 GB or more, 128k should fit without quantizing the KV cache (not measured). The draft model is small (0.20 GB); keep it.
- **Another CPU (laptop):** QAD-Q4_0 with repacking needs a CPU with AVX2 (any recent x86). Use one thread per performance core; for `-C`, set one bit per performance core, taking only the first thread of each (check `lscpu --extended`).
- **`-lm none`** saves about 1 GB with any CPU.

## Files

| File | Used by | Size | SHA-256 |
|---|---|---|---|
| [`LFM2.5-2.6B-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/e7caca5/LFM2.5-2.6B-Q4_K_M.gguf) (Liquid AI, commit `e7caca5`) | Desktop | 1.67 GB · 4.97 bits per weight | `02a8b7e1…c697f52ed` |
| [`LFM2.5-2.6B-DSpark-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-DSpark-GGUF/blob/7bc2896/LFM2.5-2.6B-DSpark-Q4_K_M.gguf) (Liquid AI, commit `7bc2896`) | Desktop | 0.20 GB | `63786b76…e34b79a3cd` |
| [`LFM2.5-2.6B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/e7caca5/LFM2.5-2.6B-QAD-Q4_0.gguf) (Liquid AI, commit `e7caca5`) | Laptop | 1.59 GB · 4.73 bits per weight | `a247afd6…d8d40b03` |

Full hashes in [`SHA256SUMS`](SHA256SUMS).

## Reproduce the measurements

The scripts are in [`scripts/`](scripts/), named after the round they belong to, and each round's raw data is in [`bench/`](bench/) under the same name. Desktop rounds start with `2.5`, laptop rounds with `2.6` (and `2.0`, a RAM test). The desktop scripts run inside the [llama-swap](https://github.com/mostlygeek/llama-swap) Docker image (`unified-cuda13`, llama.cpp b11580); the laptop scripts use the official CPU build b11588. The fidelity test (2.6b) used llama.cpp b11028 with CUDA on the desktop, and 2.6c repeated part of it on the laptop. The scripts assume the model paths of the test machines: edit the variables at the top.

The coding benchmark results (one JSON per run, with the generated code) are in [`bench/3.2-minibench/`](bench/3.2-minibench/) and the agent test results in [`bench/3.3-pi/`](bench/3.3-pi/).

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own license, the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/main/LICENSE).
