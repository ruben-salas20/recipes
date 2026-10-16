# Qwen-Image 2.1 on a 6 GB GPU

A measured recipe for running [Qwen-Image 2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) locally on an **RTX 3050 with 6 GB of VRAM and 16 GB of RAM**, using [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). No ComfyUI, no Python stack: one compiled binary and three model files.

> [!TIP]
> **We recommend the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md) instead of this one.** It takes ~60 s per image against ~148 s, and in a blind test it won 10 of 12 comparisons against this recipe. This page stays for anyone who wants the full 25-step model.

Every number on this page was measured on that machine. The scripts that produced them are in [`scripts/`](scripts/) and the raw results, one CSV per round, are in [`bench/`](bench/).

[Versión en español](README.es.md)

![Images generated with the recipe](assets/showcase-v2.webp)
*The previous recipe (1.4 MP, sd.cpp `f89d9b1`), seed 42, no cherry-picking. Top: product shot, portrait, ad with Spanish text. Bottom: concept art, anime illustration.*

> [!IMPORTANT]
> **The model weights are licensed for non-commercial use only.** The [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (section 2) allows research and evaluation. Commercial use, including ads or product photos for a business, needs a separate license from Qwen (`model-business@notice.qwencloud.com`). This guide covers running the model, not what you are allowed to do with its output.

## The recipe

```bash
sd-cli \
  --diffusion-model qwen_image_2.1-Q4_0.gguf \
  --vae qwen_image_2.1_vae_bf16.safetensors \
  --llm Qwen3VL-8B-Instruct-Q4_K_M.gguf \
  --params-backend "te=disk,diffusion=cpu,vae=cpu" \
  --offload-to-cpu --vae-tiling --vae-tile-size 512 \
  --cfg-scale 1 --sampling-method euler --steps 25 \
  -W 1024 -H 1024 \
  -p "your prompt" -o out.png
```

- **`--params-backend "te=disk,…"`** streams the text encoder from the file to the GPU without copying it into the program's RAM. It saves ~49 s per image and the image comes out pixel-for-pixel identical.
- **`--vae-tile-size 512`** decodes in 512 px tiles instead of 256: the VAE goes from ~22 to ~13 s, with no visible seams.
- **No EasyCache** (`--cache-mode easycache`). It saves ~45 % of the time, but in a blind test the image without it won 10 of 12 comparisons, and it renders the fine text of infographics worse (14 of 21 texts against 16). See [Why these settings](#why-these-settings).
- **Don't add `--diffusion-fa`**: it is deprecated. Flash attention is on by default (`--flash-attn auto`).

| | |
|---|---|
| Use it for | Anyone who wants the full 25-step model; for everyday use, the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md) |
| Diffusion model | Q4_0 |
| Text encoder | Q4_K_M, read from disk |
| Steps | 25 |
| Square | 1024 × 1024 |
| Portrait 9:16 | 768 × 1344 |
| Landscape 16:9 | 1344 × 768 |
| Time per image | **~148 s** (mean 148.0 s, range 146.2–150.1) |
| Peak program RAM | 5.2 GB |

Use CFG 1. The time is wall clock for the whole run: loading, text encoding, sampling and VAE decoding. Means over 6 prompts × 3 seeds. Sizes must be multiples of 32. As with the Turbo recipe, the speed depends on the files fitting in the OS cache (about 10 GB of free RAM); see the [Turbo recipe's warning](../Qwen-Image-2.1-Turbo/README.md#the-recipe).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/before-after-dark.webp">
  <img alt="Seconds per image before and now: regular from 273 to 148 s, Turbo from 145 to 60 s" src="assets/before-after.webp">
</picture>

## Setup

### 1. Build stable-diffusion.cpp with CUDA

Use [`8cd731e`](https://github.com/leejet/stable-diffusion.cpp/commit/8cd731e) (2026-10-15). The current recipe was measured on it; later versions have not been tested. You need at least [`0a9340c`](https://github.com/leejet/stable-diffusion.cpp/commit/0a9340c5) (2026-09-25), which fixes the white patches described under [Resolved issues](#resolved-issues).

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
git checkout 8cd731e && git submodule update --init --recursive
cmake -B build -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
# binaries: build/bin/sd-cli and build/bin/sd-server
```

`86` is the RTX 30-series architecture. Use `89` for RTX 40 or drop the flag to let CMake detect it.

### 2. Download the model files

| Part | File | Size | SHA-256 |
|---|---|---|---|
| Diffusion model | [`qwen_image_2.1-Q4_0.gguf`](https://huggingface.co/leejet/Qwen-Image-2.1-GGUF/blob/main/qwen_image_2.1-Q4_0.gguf) (leejet) | 4.2 GB | `8d992dc9…cf29e9147` |
| Text encoder | [`Qwen3VL-8B-Instruct-Q4_K_M.gguf`](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/blob/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf) (Qwen) | 5.0 GB | `67d1659b…0e9e2` |
| VAE | [`qwen_image_2.1_vae_bf16.safetensors`](https://huggingface.co/Comfy-Org/Qwen-Image-2.1/blob/main/vae/qwen_image_2.1_vae_bf16.safetensors) (Comfy-Org) | 0.68 GB | `bb21f747…e4876b7c9` |

Full hashes are in [`SHA256SUMS`](SHA256SUMS). The VAE is specific to 2.1: the Qwen-Image 1 and Wan 2.2 VAEs do not work.

### 3. Free the GPU

The recipe uses the whole card. Close anything else holding VRAM (an LLM server, Whisper) before generating, or the run fails with an out-of-memory error.

## Why these settings

### October 2026 round: from 273 to 148 s

On sd.cpp `8cd731e`, changing one flag at a time from the previous recipe (1.4 MP). The previous recipe copied the weights (~9 GB) into the program's RAM; with that, the files no longer fit in the OS cache as well, and every image re-read ~9 GB from the hard disk. Raw data: [`bench/final-1016/`](bench/final-1016/); the blind tests are in the [Turbo folder](../Qwen-Image-2.1-Turbo/bench/cata-1016/).

| Change | Time per image | Image |
|---|---|---|
| Previous recipe on sd.cpp `8cd731e`, without `--diffusion-fa` | 271 s | The same scene |
| **Text encoder from disk** (`te=disk`) | **222 s** | Pixel-for-pixel identical |
| **512 px VAE tiles** | −9 s (VAE from ~22 to ~13 s) | Almost identical (LPIPS 0.001), no seams |
| **1 MP instead of 1.4 MP** | **148.0 s** (the current recipe) | 3 of 9 images with perfect text, against 6 of 9 at 1.4 MP. In the blind test, the 1.4 MP version did not win a single comparison against Turbo either |

LPIPS measures how different two images look to a person: 0 is identical, and the higher, the more different.

What we tried and left out of the recipe, all at 1 MP:

| Option | Time per image | Result |
|---|---|---|
| EasyCache, default threshold (0.20) | ~80 s | Breaks fine text: 3 of 7 texts in the infographic, with scribbles |
| EasyCache, threshold 0.15 | ~80 s | 14 of 21 texts against 16; **in the blind test, the recipe without EasyCache won 10 of 12** (2 ties) |
| EasyCache, threshold 0.05 | ~100 s | Almost identical to the recipe (LPIPS < 0.01), 15 of 21 texts |
| 20 steps | ~123 s | 16 of 21 texts; the composition changes more (LPIPS up to 0.09) |

EasyCache skips the computation of steps where the image barely changes; the threshold sets how much change is tolerated. An LPIPS of 0.015–0.045 (threshold 0.15) was enough for the difference to show in a blind test.

### First round

These results come from the first round, on sd.cpp `c92d73c` (2026-09-22) and `c678dfe`. Since then sd.cpp corrected Qwen-Image 2.1's noise schedule ([#2048](https://github.com/leejet/stable-diffusion.cpp/pull/2048)), so the same seed gives a slightly different image. Speed and memory did not change in our checks; the quality numbers were re-measured in the final round (next section). Raw data: [`bench/fase1/`](bench/fase1/), [`bench/fase1b/`](bench/fase1b/) and [`bench/fase2/`](bench/fase2/).

Measured with the same ad prompt at 768 × 1344, seed 42, one flag changed at a time:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/speed-dark.webp">
  <img alt="The same ad with four configurations and their times" src="assets/speed.webp">
</picture>

| Change | Time | s/step | Result |
|---|---|---|---|
| Baseline (Q4_0, 25 steps, CFG 1) | 316 s | 10.5 | — |
| **+ `--diffusion-fa`** | **221 s** | **6.8** | **−30 % total, −35 % sampling**, visually identical |
| + FA, 20 steps | 193 s | 7.0 | Near-identical to 25 steps on this prompt |
| + FA, 15 steps | 166 s | 7.5 | Still close |
| Q4_K instead of Q4_0 | 327 s | 11.0 | A different image, not a better one |
| Q5_0 instead of Q4_0 | 333 s | 11.2 | Same, and +0.8 GB of RAM |
| + FA, 1.4 MP (896 × 1568) | 293 s | 9.5 | The only one that spelled "Envío" right |
| 2.4 MP (1152 × 2048) without FA | — | — | **Out of memory** (asked for 11.6 GB of VRAM) |
| + FA, 2.4 MP | 502 s | 17.1 | Fits, but see below |

- **Flash attention is the single biggest win.** It was not on by default at the time. It also makes 2.4 MP fit in 6 GB.
- **CFG 1, not 6.** The sd.cpp example uses `--cfg-scale 6.0`; the official ComfyUI template uses 1. With CFG above 1 every step runs twice, so CFG 1 is about twice as fast. In our tests it also followed the prompt's style better (CFG 6 ignored "soft pastel colors").
- **Resolution matters more than steps.** At 1024 × 576 images came out washed out; at ~1 MP they did not. At ~1 MP, 15, 20 and 25 steps looked nearly the same.
- **Q4_K and Q5_0 gave no improvement** over Q4_0.
- **1.4 MP beat 2.4 MP on text in that round.**

In that round we compared three candidates (draft at 15 steps and ~1 MP, default, and max at ~2.4 MP). The max recipe took 8 min 25 s and did worse than the default on every measure, so more pixels are not worth it at Q4_0. The draft recipe (15 steps, 2 min 45 s) is no longer recommended: if you want speed, use the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md), which is faster and better.

![Ad button text across the three earlier recipes](assets/text-accuracy.webp)
*Small text in the first round: only the default recipe spelled "Envío" with its accent in all three seeds.*

## Quality results

Measured with the current recipe: 6 prompts × 3 seeds, 18 images, compared with the Turbo recipe. The full table and the blind tests are in the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md#comparison-with-the-regular-recipe).

- **Blind preference: 1 of 12 comparisons** against the Turbo recipe (10 for Turbo and 1 tie). 12 pairs in random order, one voter. In the previous round, at 1.4 MP, this recipe won 9 of 18 against the two Turbo variants of the time; with the same images of this recipe, it now loses. The explanation is in the Turbo recipe: the voter's judgement changed, not the images.
- **Text: 3 of 9 images perfect.** The 9 text images are the ad, the product shot and the medical illustration (3 seeds each). Failures: two ads ("Envio" without the accent) and two medical illustrations (a repeated "Tibia" in one; a repeated "Menisco", "Cartíllago" and an illegible label in another). Turbo got 6 of 9 on the same test images. Text was checked letter by letter, at full size, not with OCR.
- **Infographics: we don't recommend them.** In an infographic with 7 texts, 16 of 21 right in Spanish and 21 of 21 in English, the same as Turbo, but the figures are unrelated to the text or explain nothing. See the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md#what-it-is-good-for).
- **White patches: 0 of 18 images.**

## What it is good for

Tested prompts: product shots, portraits, ads with Spanish text, concept art, anime illustration and city scenes. Text rendering is the model's strong point on ads and product labels, accents included, but long lists of small labels (the medical illustration) still fail.

**Technical and academic images.** We tested 12 subjects across disciplines, without text in the image, 2 seeds each, at 15 steps (first round). Raw data: [`bench/tecnico/`](bench/tecnico/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/technical-dark.webp">
  <img alt="12 technical subjects with a verdict for each" src="assets/technical.webp">
</picture>

- **Usable (7):** heart, cell, flower, suspension bridge, prism, Earth's layers, solar system. Large, well-known structures come out right.
- **Illustrative (4):** knee (the kneecap sits in the wrong place), engine, dodecahedron, circuit. Recognizable, fine for a general audience; a specialist would spot errors.
- **Not usable (1):** caffeine. The molecule was not caffeine in either seed.

The Turbo model did better on the same test (8 / 3 / 1); see the [Turbo recipe](../Qwen-Image-2.1-Turbo/README.md#what-it-is-good-for).

In short: good for textbook-style figures of big, familiar structures. Not reliable where details must be exact: specific molecules, precise mechanical parts or the spatial relation between parts. **Generate without labels and add them yourself:** when asked for labels, the model spells them well but points them at the wrong part.

## Resolved issues

**White patches: fixed in sd.cpp [`0a9340c`](https://github.com/leejet/stable-diffusion.cpp/commit/0a9340c5) ([#2054](https://github.com/leejet/stable-diffusion.cpp/pull/2054)).** With earlier versions, some images got a hard-edged rectangle of pure white, 12–16 px wide:

![A white patch on a knee illustration](assets/white-patch.webp)

- **Cause:** FP16 overflow in the Qwen-Image 2.1 VAE's convolutions. The fix scales their inputs down and restores the outputs afterwards.
- **Verified:** we regenerated 3 images that had patches, with the same seeds and settings, on `3f8527a`. All 3 came out clean, at the same speed. Upgrading is the whole fix; no flag is needed. In the final round, 0 of 18 images with this recipe had one.
- It affected 12 of the 54 images of the first comparison, always aligned to the model's 16 px grid.
- **A correction:** an earlier version of this page said GPU precision in the VAE had been ruled out, because decoding on the CPU gave the same patch. That conclusion was wrong: the overflow happens in FP16 convolutions on that path too, so the test did not isolate what we thought it did.

Thanks to leejet for the fix and for answering our report on Hugging Face.

## Other things to know

- **Keep `--vae-tiling`.** Decoding a 1 MP image in one piece needs more than 6 GB and sd.cpp falls back to tiling anyway. Since [`19bbbca`](https://github.com/leejet/stable-diffusion.cpp/commit/19bbbca1), `--vae-tile-size` is measured in image pixels, not latent cells: if you copied `--vae-tile-size 24x24` from an older version of this page, remove it. **Never decode on the CPU without tiling:** at 1024² it used all 16 GB of RAM and the kernel killed the process.
- **The first images after a reboot or a model switch are slower** if the weights live on a hard disk: ~10 GB have to be read to fill the OS cache. In our tests the first one took about 20 s longer.
- **Don't benchmark while downloading.** Downloads to the same disk evict the weights from the cache, and the recipe reads them from disk again.
- **The VRAM column always shows ~5.1–5.2 GB.** sd.cpp fills whatever is free and streams the rest from RAM. It is what it uses, not what it needs; the minimum VRAM has not been measured.
- **Output PNGs are RGBA** even for opaque images, because Qwen-Image 2.1 supports transparency.

## Reproduce the measurements

```bash
../Qwen-Image-2.1-Turbo/scripts/final-1016.sh normal   # the current recipe: 6 prompts × 3 seeds (resumable)
scripts/bench.sh <round> <name> <model> <steps> <prompt_id> [W H] [-- extra sd-cli args]
scripts/fase1.sh      # speed and memory, one variable at a time (first round)
scripts/fase1b.sh     # flash-attention combinations (first round)
scripts/fase2.sh      # 3 early recipes × 6 prompts × 3 seeds (first round, ~5 h, resumable)
scripts/tecnico.sh    # 12 technical subjects × 2 seeds (first round)
```

`bench.sh` takes either the suffix of a model file or the full path to a `.gguf`. The `LLM` environment variable selects the text encoder; by default it is the Q4_K_M. The scripts of the current round (`final-1016.sh`) and of the previous one (`final.sh`) are in the [Turbo folder](../Qwen-Image-2.1-Turbo/scripts/).

Prompts are in [`prompts/`](prompts/). Every run appends one row to a `resultados.csv` with the time, the peak RAM and VRAM and the exact flags; the images and logs are written next to it but are not included in this repo. Data by round: [`bench/final-1016/`](bench/final-1016/) (the current recipe), [`bench/fase1/`](bench/fase1/), [`bench/fase1b/`](bench/fase1b/), [`bench/fase2/`](bench/fase2/) (with the first blind test in [`bench/fase2/ciego/`](bench/fase2/ciego/)) and [`bench/tecnico/`](bench/tecnico/). The scripts assume the model paths of the test machine; edit `D` and `SD` at the top of `bench.sh`.

## Test machine

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5.8 GiB usable), driver 595.71.05, CUDA 13.0 |
| CPU / RAM | 6 cores, 16 GB |
| Storage | Weights on a 7200 rpm hard disk |
| OS | Ubuntu 24.04 |
| sd.cpp | Current recipe: `8cd731e` (2026-10-15). Previous round: `f89d9b1` (2026-10-09). First round: `c92d73c` (phase 2) and `c678dfe` (phase 1 and the technical test; one image compared across both was bit-identical). White-patch fix verified on `3f8527a` |

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own licenses: Qwen-Image 2.1 and the VAE under the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (non-commercial); the Qwen3-VL text encoder under Apache 2.0.
