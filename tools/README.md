# quick-bench

Measure a text recipe on your own machine in a few minutes, and get numbers you can share.

`quick-bench.py` starts `llama-server` with the exact flags of a recipe and measures three things:

- **Prompt processing (prefill):** how fast the model reads the prompt.
- **Decode:** how fast it writes the answer.
- **Decode with a full context:** the same, with a long prompt already in the context. Speed drops as the context fills up.

It goes through `llama-server`, not `llama-bench`, so recipes that use a draft model (speculative decoding) are measured the way you would actually run them. Each measurement is a real chat request: some context, then a short Python coding task, answered with the recipe's sampling settings.

It only needs Python 3.8+ and a llama.cpp build. No packages to install.

## Run it

Download the GGUF files listed in the recipe, then:

```bash
# GPU recipes (made for an RTX 3050 6 GB)
python3 quick-bench.py minicpm5-2b gpu --models-dir ~/models
python3 quick-bench.py lfm2.5-2.6b gpu --models-dir ~/models
python3 quick-bench.py lfm2.5-24b-a2b gpu --models-dir ~/models

# CPU-only recipes
python3 quick-bench.py lfm2.5-24b-a2b cpu --models-dir ~/models --threads 6
```

| Option | What it does |
|---|---|
| `--models-dir` | Folder with the GGUF files, with their original names. Or give each file with `--model` and `--draft`. |
| `--server` | Path to `llama-server`, if it is not on your `PATH`. |
| `--threads` | CPU recipes: number of threads. Use one per performance core. Default: half the logical CPUs. |
| `--cpu-mask` | CPU recipes: pin threads to cores, e.g. `0x555` for CPUs 0, 2, 4, 6, 8, 10 (one bit per performance core, first thread of each; see `lscpu --extended`). Default: no pinning. |
| `--sizes` | Prompt lengths in tokens. `0` sends the coding task alone. Default: GPU `0,4096,32768`, CPU `0,2048,8192`. |
| `--decode` | Maximum tokens per answer. Default: GPU 1024, CPU 256. With a draft model, short answers understate decode speed. |
| `--reps` | Runs per prompt length, one coding task each (default 3). The median is reported. |
| `-- <flags>` | Anything after `--` is passed to `llama-server`, e.g. `-- -ncmoe 28` to try a lower `-ncmoe` on a GPU with more VRAM. |

A GPU run takes 2–5 minutes; a CPU run, 5–10. The GPU must be free: close anything else that uses VRAM.

## What you get

A Markdown table, ready to paste in an issue or a post:

```
### minicpm5-2b · gpu recipe

Intel(R) Core(TM) i5-9400 CPU @ 2.90GHz · GPU: NVIDIA GeForce RTX 3050, 6144 MiB · 15.5 GB RAM · llama.cpp commit 4413a19 · 5670 MiB VRAM

| Prompt | Prefill | Decode with that context (median, range) | Draft acceptance | Reference prefill / decode |
|---|---|---|---|---|
| 77 tokens | 1816.1 tok/s | 89.4 tok/s (76.7–95.5) | 48% | 1812.3 / 78.6 tok/s |
...
```

And a JSON file with every run, your CPU, GPU, RAM, llama.cpp version, the exact command and the SHA-256 of the model files (skip hashing with `--no-hash`). The server log is saved next to it.

## Reference results

quick-bench on the recipes' two test machines (2026-10-14). These are the numbers the script compares yours with. They read 5–15 % below the `llama-bench` figures in the recipes, because every request goes through `llama-server` with a chat template and sampling, and the runs go back to back. Full JSON files in [`results/`](results/).

**Desktop · RTX 3050 6 GB VRAM + 16 GB RAM** (llama.cpp commit `4413a19`, b11580)

| Recipe | Task alone: prefill / decode | 4k prompt | 32k prompt | VRAM |
|---|---|---|---|---|
| LFM2.5-24B-A2B | 52 / 29.9 tok/s | 647 / 29.5 tok/s | 753 / 24.1 tok/s | 5588 MiB |
| MiniCPM5-2B | 1812 / 78.6 tok/s | 2303 / 84.9 tok/s | 1279 / 43.6 tok/s | 5670 MiB |
| LFM2.5-2.6B | 1283 / 121.0 tok/s | 2477 / 103.2 tok/s | 2109 / 74.6 tok/s | 4606 MiB |

**Laptop · CPU only, no VRAM + 24 GB RAM** (i7-13620H, `--threads 6 --cpu-mask 0x555`, llama.cpp b11588)

| Recipe | Task alone: prefill / decode | 2k prompt | 8k prompt | RAM |
|---|---|---|---|---|
| LFM2.5-24B-A2B | 64 / 25.5 tok/s | 70 / 23.4 tok/s | 64 / 15.9 tok/s | 15.9 GB |
| MiniCPM5-2B | 110 / 25.0 tok/s | 99 / 19.4 tok/s | 66 / 10.8 tok/s | 8.0 GB |
| LFM2.5-2.6B | 130 / 24.9 tok/s | 96 / 21.6 tok/s | 88 / 16.0 tok/s | 4.2 GB |

The 24B's prefill with a tiny prompt is low on the GPU (52 tok/s) because the experts kept in RAM are sent to the GPU for every batch, however small. The laptop ran the previous release of the 24B GGUF (commit `f97fc8a`); the desktop, the current one.

## Reading the numbers

- **Decode with a draft model varies from run to run**, because the speed depends on how predictable the answer is. That is why each length runs three different tasks and reports the median and the range.
- **Compare with the reference column, not with the recipe's headline numbers.** The recipes report `llama-bench`, which measures decode bare and, on the laptop, with pauses to cool down.
- **The recipes' flags are tuned for their test machines.** If you have more VRAM or another CPU, see "Adapting it to your machine" in each recipe, and try your own flags after `--`.

## Share your results

Open an issue in this repository with the **Share results** form and paste the Markdown table (and the JSON if you like). Results from other GPUs and CPUs help everyone see how far the recipes carry over.
