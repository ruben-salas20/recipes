# FLUX.3 Image Klein on a 6 GB GPU

A measured recipe to run [FLUX.3 Image Klein](https://huggingface.co/black-forest-labs/flux-3-image-klein) (Black Forest Labs, October 2026) locally on an **RTX 3050 with 6 GB of VRAM and 16 GB of RAM**, with [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). No ComfyUI and no Python environment: one compiled binary and three model files.

Klein is the distilled version of FLUX.3 Image: a 5.5 B-parameter transformer meant for 16 steps with CFG 1. It uses the FLUX.2 VAE and Qwen3-VL 4B as its text encoder.

**About 39 s per 1 MP image, with 4.9 GB of RAM and 4.9 GB of VRAM.** Its strength is Spanish text inside the image: ads, product labels, posters. Editing with reference images is not usable on 6 GB.

Every number on this page was measured on that machine. The scripts that produced them are in [`scripts/`](scripts/) and the raw results, one CSV per round, in [`bench/`](bench/).

[Versión en español](README.es.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/showcase-dark.webp">
  <img alt="Six styles with the recipe: product, portrait, medical illustration, ad, city and anime" src="assets/showcase.webp">
</picture>

*The 6 test prompts with the recipe and seed 42, not cherry-picked: it is the first and only image of each.*

> [!IMPORTANT]
> **Weights license: [FLUX Kommunity License v1.0](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/LICENSE.md).** Non-commercial use is free. Generated images can be used commercially if whoever generates them meets the license's conditions (among others, revenue below the limit it sets, reviewing the images before sharing them, and labeling them as AI-generated where the law requires it). Read it in full before using the images for a business. The Hugging Face repository is gated: you have to accept the license to download the weights. This guide explains how to run the model, not what you may do with its output.

## The recipe

```bash
sd-cli \
  --diffusion-model flux-3-image-klein-q6_K.gguf \
  --vae ae.safetensors \
  --llm Qwen3VL-4B-Instruct-Q8_0.gguf \
  --params-backend "te=disk,diffusion=cpu,vae=cpu" \
  --offload-to-cpu --vae-tiling \
  --cache-mode easycache \
  --cfg-scale 1 --sampling-method euler --steps 8 \
  -W 1024 -H 1024 \
  -p "your prompt" -o output.png
```

- **`--cache-mode easycache`** skips the computation of steps in which the image barely changes. At 16 steps it saved a third of the time and the image hardly changed.
- **`--params-backend "te=disk,…"`** moves the text encoder from the file to VRAM, uses it and frees it, without keeping it in RAM. As fast as keeping it in RAM, with 2.2 GB less RAM.
- **8 steps** instead of the documented 16: it won a blind test against 16 steps (see [Why these settings](#why-these-settings)).
- **Do not add `--diffusion-fa`**: it is deprecated. Flash attention is on by default (`--flash-attn auto`) and it is required: without it the model does not fit.

| | Recipe | More detail | Less memory |
|---|---|---|---|
| For | Everyday use | Portraits and illustration with fine detail | Machines with little free RAM or VRAM |
| Diffusion model | Q6_K | Q6_K | Q5_K |
| Steps | 8 | 16 | 16 (8 steps not measured) |
| Time per image | **~39 s** (mean 38.6; range 34-54) | ~52 s | ~49 s |
| Peak process RAM | 4.9 GB | 4.9 GB | 4.3 GB |
| Peak VRAM | 4.9 GB | 4.9 GB | 4.3 GB |

All three use EasyCache, the encoder from disk and CFG 1. Time is wall-clock and covers the whole run: loading, text encoding, sampling and VAE. Means over 6 prompts × 3 seeds. Tested sizes: 1024 × 1024, 768 × 1344 and 1344 × 768.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/recipes-dark.webp">
  <img alt="The recipe and its two variants with the same ad and product shot" src="assets/recipes.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/speed-dark.webp">
  <img alt="Seconds per image for each setting" src="assets/speed.webp">
</picture>

## Installation

### 1. Build stable-diffusion.cpp with CUDA

Use [`8cd731e`](https://github.com/leejet/stable-diffusion.cpp/commit/8cd731e) (2026-10-15), the commit that added FLUX.3 Image Klein (PR #2143). Everything on this page was measured with it; later versions have not been tested.

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
git checkout 8cd731e && git submodule update --init --recursive
cmake -B build -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
# binary: build/bin/sd-cli
```

`86` is the RTX 30 series architecture. Use `89` for RTX 40 cards, or drop the option to let CMake detect it.

### 2. Download the weights

From BFL's repository (accept the license on the model page first) and from Qwen's official repository:

| Part | File | Size | SHA-256 |
|---|---|---|---|
| Transformer, original | [`model.safetensors`](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/model.safetensors) (BFL, BF16) | 11.1 GB | `c3e9813c…fee0bd7c` |
| VAE | [`ae.safetensors`](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/ae.safetensors) (BFL) | 0.34 GB | `868fe7b3…066ce8f3` |
| Text encoder | [`Qwen3VL-4B-Instruct-Q8_0.gguf`](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/blob/main/Qwen3VL-4B-Instruct-Q8_0.gguf) (Qwen) | 4.28 GB | `054721f4…27863eb1` |

Full hashes are in [`SHA256SUMS`](SHA256SUMS).

### 3. Convert the transformer to GGUF

BFL publishes the transformer in BF16 (11.1 GB), which does not fit on the GPU. sd.cpp converts it in a few minutes, using no more than 2.6 GB of RAM:

```bash
build/bin/sd-cli -M convert -m model.safetensors -o flux-3-image-klein-q6_K.gguf --type q6_K
build/bin/sd-cli -M convert -m model.safetensors -o flux-3-image-klein-q5_K.gguf --type q5_K   # «Less memory» variant
```

| Type | Size | Bits per weight | Conversion time | SHA-256 of the result |
|---|---|---|---|---|
| Q6_K | 4.67 GB | 6.74 | 2 min 9 s | `cae4ed97…af3d444d` |
| Q5_K | 3.95 GB | 5.70 | 5 min 17 s | `c3f1cb07…6d58b4d6` |

With the same sd.cpp commit you should get the same SHA-256. Ready-made GGUF files exist in [`Abiray/flux-3-image-klein-sd-GGUF`](https://huggingface.co/Abiray/flux-3-image-klein-sd-GGUF), aimed at ComfyUI. Each file is 22,112 bytes larger than ours of the same type, which points to the same tensors with extra metadata. Their `_S` and `_M` pairs have exactly the same size, and their per-type quality table is not measured. We have not checked whether sd.cpp loads them.

### 4. Free the GPU

The recipe uses almost the whole card. Close any other program using VRAM (an LLM server, Whisper) before generating: sd.cpp does not split the model and, if it does not fit, it fails.

## Why these settings

Each round changed one thing only, with the ad, product and portrait prompts and seeds 42 and 7. To measure how far one image moves from another we used [LPIPS](https://github.com/richzhang/PerceptualSimilarity): 0 is identical, and below ~0.02 differences are hard to see. LPIPS says how much the image changes, not whether it gets better or worse. Data in [`bench/`](bench/).

| Round | What was tested | Result |
|---|---|---|
| Quantization | Q6_K, Q5_K and Q4_K (Q8_0 and BFL's FP8 do not fit) | Q5_K moves little from Q6_K (LPIPS 0.040) and Q4_K more (0.097: another face, another slate). Going down a type barely speeds up (−6 % and −8 %); what you gain is memory |
| Text encoder | Q4_K_M in RAM, Q8_0 in RAM and Q8_0 from disk | Q8_0 in RAM is slower (93-107 s): not everything fits in the system cache and it rereads the disk. From disk, as fast as Q4_K_M and with 2.2 GB less RAM |
| Steps | 16, 12 and 8 | 12 steps −22 %; 8 steps −42 %, with the text right |
| Resolution | 1 MP and 1.4 MP | 1.4 MP improves skin detail a little but takes 37 % longer. It stays at 1 MP |
| EasyCache | Off and on | Skips 6 of 16 steps: −33 % time with LPIPS 0.019 |
| Flash attention | `auto`, `on` and `off` | `auto` already turns it on; without it the model does not fit |

**The blind test.** Three variants (Q6_K at 8 steps, Q6_K at 16 and Q5_K at 16) with the 6 prompts × 3 seeds, at the same size and in random order. One person voted.

| Prompt | Q6_K · 8 steps | Q6_K · 16 steps | Q5_K · 16 steps | Tie |
|---|---|---|---|---|
| Ad | **3** | 0 | 0 | 0 |
| City | **3** | 0 | 0 | 0 |
| Medical | 1 | 0 | 1 | 1 |
| Anime | 0 | **2** | 0 | 1 |
| Portrait | 0 | **2** | 1 | 0 |
| Product | 0 | 1 | 0 | 2 |
| **Total** | **7** | **5** | **2** | **4** |

How much to trust it: 8 steps won 7 of the 14 rows with a winner, with a single voter and 18 rows. It is a clear signal, not proof. That is why the recipe uses 8 steps and keeps 16 as a variant for fine detail, where it won (portraits and anime). Votes and key in [`bench/4-cata/ciego/`](bench/4-cata/ciego/).

## What it is good for

**Spanish text inside the image.** This is its strength. With the recipe, the 15 texts of the 3 ads and the 3 product shots (seeds 42, 7 and 123) came out right letter by letter, accents and opening marks included, checked at full size. Illustrations with many small labels fail: in the knee, the labels are spelled right but point to the wrong parts, and one is missing.

**Infographics: half done.** We tried a poster with 7 Spanish texts (title, 5 items and a source line) with 3 seeds. All 21 texts came out right, but the icons do not illustrate the content: they are generic silhouettes or blobs.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/infographic-dark.webp">
  <img alt="Three infographics with correct text and icons unrelated to the text" src="assets/infographic.webp">
</picture>

**Technical and academic images: illustrative only.** 12 topics from different fields, no text in the image, seeds 42 and 7. Data: [`bench/5-tecnico/`](bench/5-tecnico/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/technical-dark.webp">
  <img alt="12 technical topics with their verdict" src="assets/technical.webp">
</picture>

- **Illustrative (10):** the topic is recognizable and fine for a general audience, but a specialist would spot errors. For example, a misplaced kneecap, an engine with parts that make no sense, more layers than the Earth has, or a ninth planet.
- **Not usable (2):** caffeine, with a made-up molecule, and the dodecahedron, without pentagonal faces.
- At 16 steps, the same verdicts.

**Editing with reference images: not usable on 6 GB.** With Q6_K it does not fit even with shrunk references. With Q5_K and shrunk references (0.5 MP with one reference, 0.25 MP with two) it fits and takes ~47 s, but every edit leaves noise. When combining two images, the hands also come out wrong. Changing the time of day only half worked. We have not investigated whether the noise comes from shrinking the references, from 8 steps or from Q5_K.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/editing-noise-dark.webp">
  <img alt="Enlarged crops: noise on the shirt after editing and malformed hands when combining" src="assets/editing-noise.webp">
</picture>

## Other things worth knowing

- **Q8_0 and BFL's FP8 do not run on the GPU** with `8cd731e`. sd.cpp keeps the whole transformer in a single block even when it does not fit (Q8_0 asks for 5761 MB with about 5700 free), and `--max-vram` does not change that. Q8_0 works with the transformer on the CPU (`--backend diffusion=cpu`), but takes 19 min per image at 512 × 512.
- **Actions and details in the prompt are followed only partly.** «A man walking» came out standing with seed 42 and walking with seed 7; «flying vehicles» came out as cars. Sometimes it adds black cinema bars at the top and bottom of landscape images.
- **The first image after switching files takes longer** if the weights are on a spinning hard disk: they have to be read. After that they stay in the system cache. The encoder-from-disk setup relies on that cache: with RAM full of other programs, the encoder would be read from disk for every image.
- **The same seed and the same settings give the same image,** byte for byte.
- **We did not use BFL's prompt upsampler** (`flux-3-image-klein-pup`, 18.8 GB, does not fit here), which BFL recommends. Prompts were used as written.

## Reproduce the measurements

```bash
scripts/descargar.sh      # download with a pinned commit and SHA-256 check
scripts/convertir.sh      # BF16 -> GGUF, with size, RAM and SHA-256 of each type
scripts/estilos.sh <type> <seed> [folder]       # the style prompts with one setting
scripts/3a.sh … scripts/3g.sh                   # the tuning rounds
scripts/4-cata.sh and scripts/4-cata-p8.sh      # the blind test
scripts/5-tecnico.sh and scripts/5-tecnico-p16.sh     # technical at 8 and 16 steps
scripts/5-infografia.sh and scripts/5-edicion.sh
scripts/lpips_vs.py <reference.png> <image.png>...   # LPIPS (AlexNet, CPU)
```

`estilos.sh` takes environment variables to change the encoder (`LLM`), the steps (`STEPS`), the prompt list (`TSV`) and extra options (`EXTRA`). Prompts are in [`prompts/`](prompts/). Each run appends a row to a `resultados.csv` with total time, encoder time, sampling and VAE, and peak RAM and VRAM. Images and logs are not included in this repo. The scripts use the test machine's paths; change them at the top of each one.

## Test machine

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5.8 GiB usable), driver 595.91.07 |
| CPU / RAM | Intel Core i5-9400 (6 cores), 16 GB |
| Storage | Weights on a 7200 rpm hard disk |
| OS | Ubuntu 24.04.5, CUDA 13.0 to build |
| sd.cpp | `8cd731e` (2026-10-15) for every test on this page |

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own licenses: the transformer and the VAE, the [FLUX Kommunity License v1.0](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/LICENSE.md); the Qwen3-VL text encoder, Apache 2.0. GGUF files you convert from the transformer are derivative works under BFL's license: they may only be redistributed non-commercially, together with the license and its notice.
