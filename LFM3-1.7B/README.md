# LFM3-1.7B on a 6 GB GPU and on a CPU-only laptop

A measured recipe for running [LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF) locally with [llama.cpp](https://github.com/ggml-org/llama.cpp), with 128k context, on two machines:

| | **Desktop** (GPU) | **Laptop** (CPU only) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB VRAM** | **None** (integrated graphics, not used) |
| CPU | Intel i5-9400, 6 cores | Intel i7-13620H, 6 performance + 4 efficiency cores |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11940, CUDA | b11940, official CPU build |

LFM3-1.7B is a small hybrid model from Liquid AI: 13 convolution layers and 11 attention layers, 6 of them with full attention. Its KV cache takes only 12 KiB per token, so **its full 262,144-token context fits on a 6 GB GPU**. It always thinks before answering, and **it needs room to do it**: with a limit of 8192 tokens per answer it got 70 % in our JSON extraction test, and with 32,768 it got 95 % (see [Give it room to think](#give-it-room-to-think)).

Every number on this page was measured on those two machines. The scripts that produced them are in [`scripts/`](scripts/) and the raw results in [`bench/`](bench/).

[Versión en español](README.es.md)

> [!NOTE]
> **License.** The weights are under the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/main/LICENSE): free for research and for commercial use by companies with less than 10 million USD in annual revenue.

## At a glance

| | **Desktop** · RTX 3050 6 GB + 16 GB RAM | **Laptop** · CPU only + 24 GB RAM |
|---|---|---|
| Quantization | Q4_K_M | QAD-Q4_0 |
| Decode | **120 tok/s** · 92 at 32k | **37 tok/s** · 29 at 8k · 15 at 32k |
| Prompt processing | **~4450 tok/s** (4k prompt) | **153 tok/s** (2048-token prompt) · 138 (8k prompt) |
| Memory with 128k | **2884 MiB** of VRAM (262k fits in 4547 MiB) | **2.6 GB** of RAM (3.5 GB after an 8k prompt) |
| Extract to JSON (24 items) | **95 %** of fields right, valid JSON in 71 of 72 answers | same model, see [Quality](#quality) |
| Coding benchmark (11 tasks) | 6.0 / 11 (5.0 with 8192 tokens) | 4.7 / 11 with 8192 tokens (Q4_K_M: 5.0) |
| Coding agent (Pi, 9 runs) | 5 / 9 | not measured |

## Give it room to think

LFM3-1.7B writes a thinking block before every answer, and for some tasks the block is long: up to 30,000 tokens to extract a JSON from a long invoice. **If the client caps the answer at 8192 tokens, the model often runs out while still thinking and returns nothing.** Many clients and benchmarks use 8192 or less by default.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/token-limit-dark.webp">
  <img alt="Extract to JSON score with a limit of 8192 and of 32768 tokens per answer" src="assets/token-limit.webp">
</picture>

| | `max_tokens` 8192 | `max_tokens` 32768 |
|---|---|---|
| Extract to JSON (3 runs) | 67–72 % | **91.5–96.7 %** |
| Items cut off without an answer | 6–7 of 24 per run | 1 of 72 |
| Spanish / English items | 56 / 85 % | 93 / 96 % |
| Coding benchmark (3 runs) | 5.0 / 11 | **6.0 / 11** |
| Coding tests passed | 46 of 106 on average | 88 of 106 |

The Spanish items were not harder to get right: they only made the model think longer. When it finished thinking, it got about 96 % of the fields right in both languages. **Set `max_tokens` to 32768 in your client.** The cost is time: the longest JSON answers took about 5 minutes on the desktop, and would take about 17 on the laptop.

## Desktop recipe · RTX 3050 6 GB VRAM + 16 GB RAM

```bash
llama-server \
  -m LFM3-1.7B-Q4_K_M.gguf \
  -ngl 99 -np 1 -c 131072 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Flag | Why |
|---|---|
| Q4_K_M | Closer to the original than QAD-Q4_0 (KL divergence from BF16 0.117 against 0.186) for 6 % less decode speed (120.5 against 128.3 tok/s). The two tied on the coding benchmark (5.0 and 4.7 / 11 with 8192 tokens). Q8_0 is almost lossless (KL 0.003) but 35 % slower. |
| KV cache in f16 (the default) | **Do not quantize it.** With `q8_0`, decode drops by 36–45 % with long contexts (35.1 against 54.6 tok/s at 128k), and the memory it saves is not needed. |
| `-c 131072` | 128k is what we used for the agent test. The full **262,144 also fits: 4547 MiB of VRAM**. |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.1` | Liquid AI's recommended sampling. `--repeat-penalty 1.0` scored the same on the coding benchmark (6.0 / 11). |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-context-dark.webp">
  <img alt="Decode speed on the RTX 3050 with an empty context, 32k, 128k and 240k" src="assets/gpu-context.webp">
</picture>

There is no DSpark draft model for LFM3 yet (as of 2026-10-28), so this recipe has no speculative decoding.

## Laptop recipe · CPU only, no VRAM + 24 GB RAM

```bash
llama-server \
  -m LFM3-1.7B-QAD-Q4_0.gguf \
  -lm none \
  -t 6 -tb 16 -fa off \
  -np 1 -c 131072 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Flag | Why |
|---|---|
| QAD-Q4_0 | Liquid AI's quantization-aware Q4_0: the fastest on this CPU (35.4 against 33.9 tok/s for Q4_K_M), and it tied with Q4_K_M on the coding benchmark. It drifts further from the original (KL 0.186 against 0.117). |
| `-lm none` | Loads the model into RAM instead of mapping the file: **2.6 GB instead of 3.4 GB** with 128k, at the same speed (37.5 against 37.7 tok/s). |
| `-t 6` | Decode is fastest with one thread per performance core: 38–41 tok/s with 6 threads, 35.5 with 16. |
| `-tb 16` | Prompt processing, on the other hand, uses all 16 threads well: **+17 %** (118 → 138 tok/s with a 7850-token prompt, 66.5 → 56.9 s until the first token). Decode does not change. |
| `-fa off` | Without FlashAttention, decode with context is much faster on this CPU: **+19 % at 8k and +77 % at 32k** (15.2 against 8.5 tok/s). The price is memory: the compute buffer grows to 4.3 GiB at 128k (0.2 GiB with FlashAttention). Prompt processing is 6–15 % slower. |
| `-c 131072` | With `-fa off`, the full 262,144 needs an 8.5 GiB compute buffer plus 3 GiB of KV cache. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-flash-attn-dark.webp">
  <img alt="Laptop decode speed with FlashAttention on and off, with an empty context, 8k and 32k" src="assets/cpu-flash-attn.webp">
</picture>

Other things we measured on the laptop that did not help: a larger micro-batch (`-ub` 1024 or 2048 is the same or 6–7 % slower than the default 512), and n-gram speculative decoding (`--spec-type ngram-mod` or `ngram-simple`, +3–4 % when extracting to JSON, because most of the answer is new thinking text).

## Quality

All quality tests ran on the desktop GPU with Q4_K_M, 3 runs each; the score depends on the file, not on the machine. The KL divergence was measured for the three candidate files:

| Quantization | Bits per weight | Size | KL vs BF16 | Same top token as BF16 | Perplexity vs BF16 |
|---|---|---|---|---|---|
| Q8_0 | 8.51 | 1.85 GB | 0.003 | 97.1 % | +0.0 % |
| **Q4_K_M** (desktop) | ~5.05 | 1.10 GB | **0.117** | 83.2 % | +2.5 % |
| **QAD-Q4_0** (laptop) | 4.82 | 1.05 GB | 0.186 | 79.4 % | +18 % |

**Coding.** The coding benchmark is 11 Python functions checked by hidden pytest tests. The agent test is [Pi](https://github.com/badlogic/pi-mono) working on a small Python project (a 200-line expense tracker) with 3 tasks: add a feature, fix a bug described by a user, and refactor without changing behaviour. Pi ran in a sandbox (bubblewrap) that only let it write to its copy of the project.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.webp">
  <img alt="Coding benchmark: mean tasks passed out of 11, with the token limit of each run" src="assets/coding.webp">
</picture>

- **Coding benchmark: 6.0 / 11 with 32,768 tokens.** Compared at the same 8192-token limit, it is below the other small recipes: 5.0 against 6.3 for MiniCPM5-2B and LFM2.5-2.6B.
- **It misspells names.** In one task it often names the function `compressir_repeticiones` instead of `comprimir_repeticiones`, so every test fails. It also happens with the unquantized BF16 file (1 of 10 runs; 3 of 10 with Q4_K_M) and without repetition penalty: it comes from the model.
- **Agent: 5 / 9** (feature 0/3, bug fix 3/3, refactor 2/3), with Pi 1.4.0 and 16,384 tokens per turn. In two feature runs it used up the turn thinking and changed nothing. With 32,768 per turn it got 4 / 9: the feature task still failed, and once it deleted two functions and broke the project. The other recipes were tested with Pi 1.0.3, so the numbers are not directly comparable (MiniCPM5-2B 7 / 9, LFM2.5-2.6B 1 / 9). Liquid AI itself does not recommend it for agentic coding.

**Tasks other than code.** Three tests we built for this recipe, with Spanish and English texts. Summaries and translations were run with an 8192-token limit (0–3 answers of 18 or 120 were cut off).

| Test | Result |
|---|---|
| **Extract to JSON** · 24 synthetic texts (invoices, emails, contracts, chats) and a JSON schema | **95 %** of fields right with 32k tokens (91.5–96.7 %), valid JSON in 71 of 72 answers |
| **Summarize** · 18 synthetic texts of 320–960 words, judged by checks and by an LLM judge (Claude Sonnet) | It covers about 3/4 of the facts (judge: 0.75–0.78). But in 10–13 of 18 summaries it **changes a relation between true facts**: something announced becomes done, a cause is attributed to something else. Sometimes it summarizes a Spanish text in English. Check its summaries before relying on them. |
| **Translate** · 120 sentences from [WMT24++](https://huggingface.co/datasets/google/wmt24pp), chrF (0–100, similarity to a human translation) | Spanish ↔ English **~59**, stable across runs. French, German and Portuguese 53–63. Chinese ~30 and Japanese 23–27. |

## Adapting it to your machine

The numbers above are for these two machines. What carries over:

- **`max_tokens` 32768 and the sampling** do not depend on the hardware.
- **Less VRAM (desktop):** with 128k the recipe takes 2884 MiB of VRAM, so it should fit on a 4 GB GPU (not measured). On any NVIDIA GPU, keep the KV cache in f16.
- **Another CPU (laptop):** use one thread per performance core for `-t` and all threads for `-tb`. Whether `-fa off` wins depends on the CPU: compare both with your context length. **`-lm none`** saves about 0.8 GB with any CPU.
- **Version.** We measured with llama.cpp b11940. Liquid AI's model card now says b11960 or newer; the only LFM3 change between the two is video input for the multimodal models, which this text recipe does not use.

## Files

| File | Used by | Size | SHA-256 |
|---|---|---|---|
| [`LFM3-1.7B-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/b3f2ae5/LFM3-1.7B-Q4_K_M.gguf) (Liquid AI, commit `b3f2ae5`) | Desktop | 1.10 GB · ~5.05 bits per weight | `3793e1e6…b05c93c4` |
| [`LFM3-1.7B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/b3f2ae5/LFM3-1.7B-QAD-Q4_0.gguf) (Liquid AI, commit `b3f2ae5`) | Laptop | 1.05 GB · 4.82 bits per weight | `43a7d09a…e572a7452` |

Full hashes in [`SHA256SUMS`](SHA256SUMS). The same files, with the same hashes, are in the repository's current commit.

## Reproduce the measurements

**Quick check on your machine:** [`../tools/quick-bench.py`](../tools/README.md) runs this recipe and measures prefill, decode and decode with a full context in a few minutes:

```bash
python3 ../tools/quick-bench.py lfm3-1.7b gpu --models-dir ~/models   # or: cpu --threads <performance cores>
```

The scripts are in [`scripts/`](scripts/), named after the round they belong to, and each round's raw data is in [`bench/`](bench/) under the same name. Desktop rounds are `2.0`, `2.1` and `3.x`; laptop rounds are `2.0` and `2.2a`–`2.2f`. The desktop used llama.cpp b11940 built with CUDA 13; the laptop, the official CPU build b11940. The scripts assume the model paths of the test machines: edit the variables at the top.

The coding benchmark results (one JSON per run, with the generated code) are in [`bench/3.2-minibench/`](bench/3.2-minibench/) and [`bench/3.2b-minibench-32k/`](bench/3.2b-minibench-32k/), the agent test in [`bench/3.3-pi/`](bench/3.3-pi/) (16,384 tokens per turn) and [`bench/3.3-pi-32k/`](bench/3.3-pi-32k/), and the JSON, summary and translation tests in [`bench/3.4-pruebas-generales/`](bench/3.4-pruebas-generales/) and [`bench/3.4b-json-32k/`](bench/3.4b-json-32k/).

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own license, the [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/main/LICENSE).
