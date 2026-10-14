# MiniCPM5-2B on a 6 GB GPU and on a CPU-only laptop

A measured recipe for running [MiniCPM5-2B](https://huggingface.co/openbmb/MiniCPM5-2B) locally with [llama.cpp](https://github.com/ggml-org/llama.cpp), with 128k context, on two machines:

| | **Desktop** (GPU) | **Laptop** (CPU only) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB VRAM** | **None** (integrated graphics, not used) |
| CPU | Intel i5-9400, 6 cores | Intel i7-13620H, 6 performance + 4 efficiency cores |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, official CPU build |

MiniCPM5-2B is a small agentic model from OpenBMB, with optional reasoning. In our tests it was **the best coding agent of the three recipes** (LFM2.5-24B-A2B, LFM2.5-2.6B and this one) and the fastest at it. On the desktop it uses OpenBMB's DSpark draft model to decode faster.

Every number on this page was measured on those two machines. The scripts that produced them are in [`scripts/`](scripts/) and the raw results in [`bench/`](bench/).

[Versión en español](README.es.md)

> [!NOTE]
> **License.** The model, the GGUF files and the DSpark draft are under Apache 2.0.

## At a glance

| | **Desktop** · RTX 3050 6 GB + 16 GB RAM | **Laptop** · CPU only + 24 GB RAM |
|---|---|---|
| Quantization | Q4_K_M + DSpark draft | IQ4_NL |
| Decode | **93.8 tok/s** | **28–30 tok/s** |
| Prompt processing | **2356 tok/s** (4k prompt) · 851 (64k prompt) | **~98 tok/s** (2048-token prompt) |
| Memory with 128k | 5.6 GB of VRAM | **7.0 GB** of RAM |
| Before the recipe | ~84 tok/s with 64k of context | 26.0 tok/s with Q4_K_M |
| Coding benchmark (11 tasks) | 5.3 / 11 (Q4_K_M) | 6.3 / 11 (IQ4_NL) |
| Coding agent (Pi, 9 runs) | **7 / 9**, the best of the three recipes | not measured |

## Desktop recipe · RTX 3050 6 GB VRAM + 16 GB RAM

```bash
llama-server \
  -m MiniCPM5-2B-Q4_K_M.gguf \
  -md MiniCPM5-2.6B-DSpark.gguf \
  --spec-type draft-dspark --spec-draft-n-max 9 --spec-draft-n-min 0 \
  --spec-draft-p-min 0.5 \
  -ngl 99 -ngld 99 -fa on \
  -np 1 -c 131072 \
  -ub 256 -b 1024 \
  -ctk q8_0 -ctv q8_0 -ctkd q4_0 -ctvd q4_0 \
  --temp 1.0 --top-p 0.95 --min-p 0.0 \
  --reasoning on
```

Use `--reasoning off` for direct answers without a thinking block.

| Flag | Why |
|---|---|
| `-md … --spec-type draft-dspark` | Speculative decoding: the small DSpark model proposes tokens and MiniCPM5-2B checks them in one pass. The output keeps the main model's quality. |
| `--spec-draft-p-min 0.5` | DSpark's confidence head: the draft stops proposing when it is unsure. llama.cpp's default (0) leaves it off. **84.0 → 96.9 tok/s.** 0.3 gave 88.0 and 0.7 gave 83.8. |
| `-c 131072` with `-ctk q8_0 -ctv q8_0` | 128k context. MiniCPM5-2B has 42 attention layers (LFM2.5 has 8), so its KV cache is large: without quantizing it, 128k does not fit in 6 GB. |
| `-ctkd q4_0 -ctvd q4_0` | The draft's KV cache, in q4_0. OpenBMB only publishes the draft in F16 (0.65 GB), so it takes more room than usual. With q8_0 here the server does not start. |
| `-ub 256 -b 1024` | Smaller batches shrink the compute buffer, the last piece needed to fit 128k. Prompt processing is still above 2000 tok/s with short prompts. |
| `--temp 1.0 --top-p 0.95 --min-p 0.0` | OpenBMB's recommended sampling. The `min-p` matters: llama.cpp's default (0.05) causes repetition loops. |

It uses 5625 MiB of the 6 GB, so nothing else can share the GPU.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-speed-dark.webp">
  <img alt="Decode speed on the RTX 3050 with and without the DSpark draft" src="assets/gpu-speed.webp">
</picture>

**Long prompts are its weak point.** Prompt processing falls from 2356 tok/s with a 4k prompt to 851 with 64k (−64 %), because every one of its 42 attention layers has to read the whole context. LFM2.5-2.6B, with only 8 attention layers, loses 28 %.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/prefill-context-dark.webp">
  <img alt="Prompt processing against prompt length for MiniCPM5-2B and LFM2.5-2.6B" src="assets/prefill-context.webp">
</picture>

`--spec-type ngram-mod` (reusing repeated text as a draft) only helped when the answer repeated the prompt, so it is not in the recipe.

## Laptop recipe · CPU only, no VRAM + 24 GB RAM

```bash
llama-server \
  -m MiniCPM5-2B-IQ4_NL.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 1.0 --top-p 0.95 --min-p 0.0 \
  --reasoning on
```

| Flag | Why |
|---|---|
| IQ4_NL | +7 % decode over Q4_K_M with almost the same fidelity (see the chart). Q4_0 is faster still (+12 %) but loses more than twice as much: discarded. |
| `-t 6` | One thread per performance core. |
| `-C 0x555 --cpu-strict 1` | Pins each thread to its own performance core. With IQ4_NL it made no measurable difference (28.2 against 28.2 and 29.7 against 29.2 tok/s); it is kept for consistency with the other recipes and is optional. |
| `-lm none` | Loads the model into RAM instead of mapping the file: **7.0 GB instead of 7.8 GB** with 128k. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-quants-dark.webp">
  <img alt="Decode speed and fidelity of Q4_K_M, IQ4_NL and Q4_0 on the laptop" src="assets/cpu-quants.webp">
</picture>

Fidelity is measured as the KL divergence from the Q8_0 file on wikitext-2: how far each quantization's predictions drift from the near-lossless version. Lower is closer.

| Quantization | Bits per weight | Size | KL vs Q8_0 | Same top token as Q8_0 |
|---|---|---|---|---|
| Q4_K_M | 5.14 | 1.62 GB | 0.043 | 89.4 % |
| **IQ4_NL** | 5.10 | 1.61 GB | **0.047** | 88.7 % |
| Q4_0 | 4.82 | 1.52 GB | 0.110 | 83.5 % |

Prompt processing is the same for the three (~96–98 tok/s with a 2048-token prompt). The laptop's speed also depends on heat: a hot CPU loses 2–3 tok/s within a couple of minutes.

## Quality

The coding benchmark is 11 Python functions checked by hidden pytest tests, 3 runs per configuration. The agent test is [Pi](https://github.com/badlogic/pi-mono) working on a small Python project (a 200-line expense tracker) with 3 tasks: add a feature, fix a bug described by a user, and refactor without changing behaviour. 3 runs per task, with the desktop recipes at 128k. Pi ran in a sandbox (bubblewrap) that only let it write to its copy of the project.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.webp">
  <img alt="Coding agent with Pi: tasks passed out of 9" src="assets/agent.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.webp">
  <img alt="Coding benchmark: mean tasks passed out of 11" src="assets/coding.webp">
</picture>

- **Agent: 7 / 9, the best of the three, in 138 s per task on average** (LFM2.5-24B-A2B: 6 / 9 in 293 s). It fixed the bug in all 3 runs and did all 3 refactors right, the task where LFM2.5-24B-A2B failed every time. Its two failures were the same detail: an invalid date did not end the program with exit code 2, as the task asked.
- **Coding benchmark: 6.3 / 11 with IQ4_NL and 5.3 with Q4_K_M**, a tie within the noise: the laptop quantization does not lose quality. Both were served on the desktop GPU; the score depends on the file, not on the machine. With the recommended temperature (1.0) the score swings a lot between runs, from 3 to 8.

## Subagents

A subagent plugin works with `-np 1`. The main session and the subagent take turns on the same server, and llama.cpp's `--cache-ram` (on by default) keeps the waiting conversation in RAM, so resuming does not reprocess it. **Do not set `--cache-ram 0`.** With `-np 2` the 128k would be split between two sessions. Measured with LFM2.5-24B-A2B on both machines: about 2–3 s per switch, against 40 s (desktop) and 2 minutes (laptop) without the cache. Details in the [LFM2.5-24B-A2B recipe](../LFM2.5-24B-A2B/README.md#subagents).

## Adapting it to your machine

The numbers above are for these two machines. What carries over:

- **The quantization choice, the draft settings (`p-min 0.5`) and the sampling** do not depend on the hardware.
- **More VRAM (desktop):** with 8 GB you should be able to drop `-ub 256 -b 1024` and use `q8_0` for the draft cache too, and with 12 GB or more leave the KV cache unquantized (not measured). With less than 6 GB, lower `-c`.
- **Another CPU (laptop):** use one thread per performance core. `-C` made no difference here; skip it if your CPU has no efficiency cores.
- **`-lm none`** saves almost 1 GB with any CPU.
- **A draft model on a CPU** was not tested with this model; the laptop recipe does not use one.

## Files

| File | Used by | Size | SHA-256 |
|---|---|---|---|
| [`MiniCPM5-2B-Q4_K_M.gguf`](https://huggingface.co/bartowski/MiniCPM5-2B-GGUF/blob/31fee03/MiniCPM5-2B-Q4_K_M.gguf) (bartowski, commit `31fee03`) | Desktop | 1.62 GB · 5.14 bits per weight | `967d467b…db755f0de` |
| [`MiniCPM5-2.6B-DSpark.gguf`](https://huggingface.co/openbmb/MiniCPM5-2B-DSpark-GGUF/blob/a261d2b/MiniCPM5-2.6B-DSpark.gguf) (OpenBMB, commit `a261d2b`) | Desktop | 0.65 GB · F16 | `57df0864…a3f0c26` |
| [`MiniCPM5-2B-IQ4_NL.gguf`](https://huggingface.co/bartowski/MiniCPM5-2B-GGUF/blob/31fee03/MiniCPM5-2B-IQ4_NL.gguf) (bartowski, commit `31fee03`) | Laptop | 1.61 GB · 5.10 bits per weight | `a2bd3ddc…9b9fce41` |

Full hashes in [`SHA256SUMS`](SHA256SUMS). The draft file is called `2.6B` in OpenBMB's repository, but it is the draft for MiniCPM5-2B.

## Reproduce the measurements

**Quick check on your machine:** [`../tools/quick-bench.py`](../tools/README.md) runs this recipe and measures prefill, decode and decode with a full context in a few minutes:

```bash
python3 ../tools/quick-bench.py minicpm5-2b gpu --models-dir ~/models   # or: cpu --threads <performance cores>
```

The scripts are in [`scripts/`](scripts/), named after the round they belong to, and each round's raw data is in [`bench/`](bench/) under the same name. Desktop rounds start with `2.3`, laptop rounds with `2.4`. The desktop scripts run inside the [llama-swap](https://github.com/mostlygeek/llama-swap) Docker image (`unified-cuda13`, llama.cpp b11580); the laptop scripts use the official CPU build b11588. The fidelity test (2.4c) used llama.cpp b11028 with CUDA on the desktop. The scripts assume the model paths of the test machines: edit the variables at the top.

The coding benchmark results (one JSON per run, with the generated code) are in [`bench/3.2-minibench/`](bench/3.2-minibench/) and the agent test results in [`bench/3.3-pi/`](bench/3.3-pi/).

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own license, Apache 2.0.
