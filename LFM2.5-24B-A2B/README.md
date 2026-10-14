# LFM2.5-24B-A2B on a 6 GB GPU and on a CPU-only laptop

A measured recipe for running [LFM2.5-24B-A2B](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B) locally with [llama.cpp](https://github.com/ggml-org/llama.cpp), with 128k context, on two machines:

| | **Desktop** (GPU) | **Laptop** (CPU only) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB VRAM** | **None** (integrated graphics, not used) |
| CPU | Intel i5-9400, 6 cores | Intel i7-13620H, 6 performance + 4 efficiency cores |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, official CPU build |

LFM2.5-24B-A2B is a mixture-of-experts model from Liquid AI: 24B parameters in total, about 2B active per token, and a hybrid design (mostly convolution layers, few attention layers). It is trained for coding agents such as [Pi](https://github.com/badlogic/pi-mono) and OpenCode. It does not fit in 6 GB of VRAM, but because only 2B parameters are active per token, it runs at a usable speed with most experts in system RAM, or entirely on a CPU.

Every number on this page was measured on those two machines. The scripts that produced them are in [`scripts/`](scripts/) and the raw results in [`bench/`](bench/).

[Versión en español](README.es.md)

> [!NOTE]
> **License.** The weights are under the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/main/LICENSE): free for research and for commercial use by companies with less than 10 million USD in annual revenue.

## At a glance

| | **Desktop** · RTX 3050 6 GB + 16 GB RAM | **Laptop** · CPU only + 24 GB RAM |
|---|---|---|
| Decode, empty context | **33.7 tok/s** | **26–30 tok/s** |
| Decode, 110k tokens of context | 15.0 tok/s | not measured |
| Prompt processing | **906 tok/s** (4096-token prompt) | **~72 tok/s** |
| Memory | 5.5 GB of VRAM; the rest of the experts stay in RAM | **15.6 GB** of RAM with 128k |
| Before the recipe | 335 tok/s prompt processing | 23.4 tok/s decode, 16.7 GB of RAM |
| Coding benchmark (11 tasks) | 7.0 / 11, the best of the three recipes | same GGUF, same score |
| Coding agent (Pi, 9 runs) | 6 / 9 | not measured |

## Desktop recipe · RTX 3050 6 GB VRAM + 16 GB RAM

```bash
llama-server \
  -m LFM2.5-24B-A2B-QAD-Q4_0.gguf \
  -ngl 99 -ncmoe 32 \
  -b 2048 -ub 2048 \
  -np 1 -c 131072 \
  -ctk q8_0 -ctv q8_0 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.05
```

| Flag | Why |
|---|---|
| `-ngl 99 -ncmoe 32` | All layers go to the GPU except the experts of 32 layers, which stay in RAM. 32 is the value that leaves room for `-ub 2048` with 128k of context. |
| `-b 2048 -ub 2048` | Processes the prompt in batches of 2048 tokens. The experts in RAM are sent to the GPU once per batch, so bigger batches mean fewer transfers: **prompt processing goes from 335 to 906 tok/s**. Decode does not change. |
| `-ctk q8_0 -ctv q8_0` | Quantized KV cache, needed to fit 128k in 6 GB. |
| `-np 1` | One conversation at a time. It still works with subagents: see [below](#subagents). |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.05` | Liquid AI's recommended sampling. |

It uses 5553 MiB of the 6 GB. Flash attention is on by default.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-prefill-dark.webp">
  <img alt="Prompt processing on the RTX 3050 with different -ub and -ncmoe values" src="assets/gpu-prefill.webp">
</picture>

**Decode slows down as the context fills up.** From 33.7 tok/s with an empty context to 15.0 tok/s with 110,000 tokens. The 110k test used the real server, which reserves all its memory at start-up, so the recipe does hold a full 128k context.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-context-dark.webp">
  <img alt="Decode speed with 0, 32k, 64k and 110k tokens of context" src="assets/gpu-context.webp">
</picture>

## Laptop recipe · CPU only, no VRAM + 24 GB RAM

```bash
llama-server \
  -m LFM2.5-24B-A2B-QAD-Q4_0.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 0.1 --top-k 50 --repeat-penalty 1.05
```

| Flag | Why |
|---|---|
| `-t 6` | One thread per performance core. More threads (12 or 16) do not process prompts faster on this laptop. |
| `-C 0x555 --cpu-strict 1` | Pins each thread to its own performance core (CPUs 0, 2, 4, 6, 8, 10), so none lands on an efficiency core or two on the same core. +4 to +13 % decode, less than the effect of heat. |
| `-lm none` | Loads the model into RAM instead of mapping the file. Without it the model ends up partly twice in memory: **16.7 GB with the default, 15.6 GB with `none`**. |
| `-fa on` | Flash attention. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-memory-dark.webp">
  <img alt="Memory with 128k context: -lm auto, -lm none and --no-repack" src="assets/cpu-memory.webp">
</picture>

**What limits this laptop is heat and power, not the flags.** The CPU reaches 90–95 °C in less than a minute, and the decode speed drops by 2–3 tok/s within a couple of minutes. That is why the decode figure is a range (26–30 tok/s). Prompt processing stays at ~72 tok/s whatever the threads or batch size, because the manufacturer's power policy (applied by `thermald`) caps the CPU at 25 W sustained. With `thermald` stopped and a 35 W limit, prompt processing rose by 10 % and the CPU ran 9 °C hotter; that is not part of the recipe.

## Quality

The coding benchmark is 11 Python functions checked by hidden pytest tests, 3 runs per model. The agent test is [Pi](https://github.com/badlogic/pi-mono) working on a small Python project (a 200-line expense tracker) with 3 tasks: add a feature, fix a bug described by a user, and refactor without changing behaviour. 3 runs per task, with the desktop recipes at 128k. Pi ran in a sandbox (bubblewrap) that only let it write to its copy of the project.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.webp">
  <img alt="Coding benchmark: mean tasks passed out of 11" src="assets/coding.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.webp">
  <img alt="Coding agent with Pi: tasks passed out of 9" src="assets/agent.webp">
</picture>

- **Coding benchmark: 7.0 / 11** (8, 6 and 7), the best of the three models, though only by 0.7 tasks. It passed the date-parsing and LRU-cache tasks in all 3 runs; the two small models never passed the first and passed the second 3 times in 12 runs. But it failed list flattening every time, which the small models passed 11 times in 12.
- **Agent: 6 / 9.** It solved all 3 feature tasks and all 3 bug fixes. It failed all 3 refactors in the same way: the weekly report should go from Monday to Sunday, and it sorted it alphabetically. The project's visible tests did not catch it. Writing and fixing code: reliable. Protecting behaviour that no test covers: not.
- One run varies by ±1–2 tasks, so the difference with MiniCPM5-2B (7 / 9) is within the noise.

## Subagents

A subagent plugin works with this recipe and `-np 1`. The main session and the subagent take turns on the same server, and llama.cpp's `--cache-ram` (on by default, up to 8 GB) keeps the waiting conversation in RAM. When the main session resumes, only the new tokens are processed. **Do not set `--cache-ram 0`.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/subagents-dark.webp">
  <img alt="Time to resume the main session after a subagent, with and without --cache-ram" src="assets/subagents.webp">
</picture>

`-np 2 --kv-unified` (two sessions sharing one 128k cache) lets both run at the same time, but each at half speed: the last one finishes no earlier than with `-np 1` (8.8 against 9.7 s on the desktop, 14.5 against 14.2 s on the laptop). The test simulated the traffic with a script ([`scripts/subagentes.py`](scripts/subagentes.py)), not with a real plugin.

## Adapting it to your machine

The numbers above are for these two machines. What carries over:

- **The GGUF and the sampling** are the same on any hardware.
- **More VRAM (desktop):** lower `-ncmoe` one step at a time until the server no longer starts, then go back one. Each step moves the experts of one more layer to the GPU and speeds up decoding. With 8 GB or more you may also drop `-ctk q8_0 -ctv q8_0`.
- **`-b 2048 -ub 2048`** helps whenever experts stay in RAM (`-ncmoe` above 0). If you run out of VRAM, lower `-ub` before raising `-ncmoe`.
- **Another CPU (laptop):** use one thread per performance core (`-t`). For `-C`, set one bit per performance core, taking only the first thread of each core: check `lscpu --extended`. CPUs without efficiency cores can skip `-C`.
- **`-lm none`** saves about 1 GB with any CPU.
- **Heat and power** depend on the laptop. If prompt processing does not grow with more threads, look at the power limit, not at llama.cpp.

## Files

| File | Size | SHA-256 |
|---|---|---|
| [`LFM2.5-24B-A2B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/0912d33/LFM2.5-24B-A2B-QAD-Q4_0.gguf) (Liquid AI, commit `0912d33`) | 13.58 GB · 4.53 bits per weight | `d1c03f73…934fbabf8a5` |

Full hash in [`SHA256SUMS`](SHA256SUMS). QAD means quantization-aware distillation: Liquid AI trained this Q4_0 to recover what quantization loses.

> [!IMPORTANT]
> **Liquid AI replaced this file on 2026-10-13** with new weights (390 of 428 tensors changed; same size, types and metadata). Most measurements on this page used the previous file (commit `f97fc8a`, SHA-256 `89617cc4…`). We checked the new one on the desktop: same speed (903 tok/s prompt processing, 33.5 tok/s decode) and slightly lower perplexity (16.55 against 16.87 on wikitext-2). The coding benchmark and the agent test have not been repeated with it yet. Data: [`bench/2.1f-gguf-nuevo/`](bench/2.1f-gguf-nuevo/).

## Reproduce the measurements

The scripts are in [`scripts/`](scripts/), named after the round they belong to, and each round's raw data is in [`bench/`](bench/) under the same name. Desktop rounds start with `2.1`, laptop rounds with `2.2`. The desktop scripts run inside the [llama-swap](https://github.com/mostlygeek/llama-swap) Docker image (`unified-cuda13`, llama.cpp b11580); the laptop scripts use the official CPU build b11588. They assume the model paths of the test machines: edit the variables at the top.

The coding benchmark results (one JSON per run, with the generated code) are in [`bench/3.2-minibench/`](bench/3.2-minibench/) and the agent test results in [`bench/3.3-pi/`](bench/3.3-pi/).

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own license, the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/main/LICENSE).
