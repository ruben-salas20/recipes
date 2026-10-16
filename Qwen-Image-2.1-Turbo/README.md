# Qwen-Image 2.1 Turbo on a 6 GB GPU

A measured recipe for running [Qwen-Image 2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo) locally on an **RTX 3050 with 6 GB of VRAM and 16 GB of RAM**, using [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). No ComfyUI, no Python stack: one compiled binary and three model files.

Turbo is the official checkpoint `Qwen/Qwen-Image-2.1-Turbo`: the same 7B architecture as Qwen-Image 2.1, distilled to 8 steps with CFG 1 and its own noise schedule. It uses the same VAE and the same text encoder as Qwen-Image 2.1.

**About 60 s per 1 MP image, with 1.4 GB of RAM.** This is the Qwen-Image recipe we recommend: in a blind test it won 10 of 12 comparisons against the [regular recipe](../Qwen-Image-2.1/README.md), which takes about 2 min 30 s. It renders short Spanish text well (ads, product labels). With long text, such as an infographic, it is much more accurate in English than in Spanish.

Every number on this page was measured on that machine. The scripts that produced them are in [`scripts/`](scripts/) and the raw results, one CSV per round, are in [`bench/`](bench/).

[Versión en español](README.es.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/showcase-dark.webp">
  <img alt="Six styles with the Turbo recipe: product, portrait, medical illustration, ad, city and anime" src="assets/showcase.webp">
</picture>

*The 6 test prompts with the recipe and seed 42, not cherry-picked: it is the first and only image of each.*

> [!IMPORTANT]
> **The model weights are licensed for non-commercial use only.** The Turbo checkpoint is under the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (section 2), the same terms as Qwen-Image 2.1: research and evaluation are allowed. Commercial use, including ads or product photos for a business, needs a separate license from Qwen (`model-business@notice.qwencloud.com`). This guide covers running the model, not what you are allowed to do with its output.

## The recipe

```bash
sd-cli \
  --diffusion-model Qwen-Image-2.1-Turbo-AD-Q4_K.gguf \
  --vae qwen_image_2.1_vae_bf16.safetensors \
  --llm Qwen3VL-8B-Instruct-Q4_K_M.gguf \
  --params-backend "te=disk,diffusion=disk,vae=cpu" \
  --offload-to-cpu --vae-tiling --vae-tile-size 512 \
  --cfg-scale 1 --sampling-method euler --steps 8 \
  --sigmas "1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0" \
  -W 1024 -H 1024 \
  -p "your prompt" -o out.png
```

- **`--sigmas` is mandatory.** Without it the Turbo model produces broken text (see [Tuning the Turbo model](#tuning-the-turbo-model)). The nine values are the checkpoint's own 8-step schedule plus the final 0.
- **`--params-backend "te=disk,diffusion=disk,…"`** streams the text encoder and the transformer from the file to the GPU without copying them into the program's RAM. This is the biggest time saver: see [From 145 to 60 s](#from-145-to-60-s).
- **`--vae-tile-size 512`** decodes the image in 512 px tiles instead of 256: the VAE goes from ~22 to ~13 s, with no visible seams.
- **Don't add `--diffusion-fa`**: it is deprecated. Flash attention is on by default (`--flash-attn auto`).

| | |
|---|---|
| Use it for | Everyday images: ads, product shots, portraits, illustration |
| Diffusion model | Turbo AD-Q4_K |
| Text encoder | Q4_K_M, read from disk |
| Steps | 8 |
| Square | 1024 × 1024 |
| Portrait 9:16 | 768 × 1344 |
| Landscape 16:9 | 1344 × 768 |
| Time per image | **~60 s** (mean 60.3 s, range 58.2–63.5 s) |
| Peak program RAM | 1.4 GB |
| Free RAM it needs | ~10 GB for the OS cache (see below) |

Use CFG 1. The time is wall clock for the whole run: loading, text encoding, sampling and VAE decoding. Means over 6 prompts × 3 seeds, after one warm-up image. Sizes must be multiples of 32.

> [!WARNING]
> **The speed depends on the files fitting in the OS cache.** The program uses little RAM, but it reads the text encoder (5 GB) and the transformer (4.2 GB) from their files for every image. If the system holds them in its disk cache in RAM, that read is almost free; for that it needs about 10 GB of free RAM. On the test machine (16 GB, no other large programs) they fit, and the first 1–3 images after switching models took 70–90 s while the cache filled. With less free RAM the transformer would be read from disk at every step and the image would take much longer; we have not measured that.

**There used to be two variants, Fast and Low RAM.** Now there is one: the recipe above is as fast as the old Fast and uses less RAM than the old Low RAM (1.4 GB against 5.3 GB). The old Low RAM used the Q8_0 text encoder (8.7 GB); we dropped it because with it the files no longer fit in the cache and the encoder is re-read from disk for every image. In the previous round's blind test, Q8_0 and Q4_K_M tied (3 votes each) and wrote the same text.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/before-after-dark.webp">
  <img alt="Seconds per image before and now: Turbo from 145 to 60 s, regular from 273 to 148 s" src="assets/before-after.webp">
</picture>

## Setup

### 1. Build stable-diffusion.cpp with CUDA

Use [`8cd731e`](https://github.com/leejet/stable-diffusion.cpp/commit/8cd731e) (2026-10-15). The current recipe was measured on it; later versions have not been tested. You need at least [`c150a6b`](https://github.com/leejet/stable-diffusion.cpp/commit/c150a6b) (2026-10-06), which fixed custom noise schedules (`--sigmas`), which the Turbo model needs.

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
| Diffusion model | [`Qwen-Image-2.1-Turbo-AD-Q4_K.gguf`](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF) (AtomicChat) | 4.20 GB | `4bb73c53…8130bc59` |
| Text encoder | [`Qwen3VL-8B-Instruct-Q4_K_M.gguf`](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/blob/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf) (Qwen) | 5.0 GB | `67d1659b…0e9e2` |
| VAE | [`qwen_image_2.1_vae_bf16.safetensors`](https://huggingface.co/Comfy-Org/Qwen-Image-2.1/blob/main/vae/qwen_image_2.1_vae_bf16.safetensors) (Comfy-Org) | 0.68 GB | `bb21f747…e4876b7c9` |

Full hashes are in [`SHA256SUMS`](SHA256SUMS). The VAE is specific to 2.1: the Qwen-Image 1 and Wan 2.2 VAEs do not work.

**Why AtomicChat's Turbo files.** The Turbo model is a quantization of the official [Qwen/Qwen-Image-2.1-Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo) checkpoint. We chose [AtomicChat's GGUF files](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF) because they measured how faithful each quantization is to the BF16 original (LPIPS; AD-Q4_K scores 0.147) and published their renders. They also found that a Q8_0 text encoder deviates less than a Q4_K_M one; in our blind tests it made no difference (see [The recipe](#the-recipe)). We checked their SHA-256 and the file structure: modulation layers in Q8_0; timestep, final norm and output projection in BF16.

### 3. Free the GPU

The recipe uses the whole card. Close anything else holding VRAM (an LLM server, Whisper) before generating, or the run fails with an out-of-memory error.

## Tuning the Turbo model

First round, with the previous recipe (1.4 MP) and sd.cpp `f89d9b1`. Measured with the ad and product prompts, seed 42. Raw data: [`bench/turbo1/`](bench/turbo1/). Script: [`scripts/turbo1.sh`](scripts/turbo1.sh).

| Change | Result |
|---|---|
| **AD-Q4_K at 1.4 MP (the recipe at the time)** | **140 s** |
| AD-Q5_K | 152–154 s and 10.5 GB of RAM, no visible improvement |
| 1 MP | 122 s, but it deformed "MAGNESIO". With the current recipe this did not happen again: 10 of 10 texts right in the ad and product shot (see below) |
| 2.4 MP | 215 s |
| **No `--sigmas`** | Same cost, but the ad headline comes out broken (duplicated letters, brackets). **The custom schedule is mandatory.** |
| Q8_0 text encoder held in RAM | 152–172 s and 12.6 GB of RAM; only fits with the machine nearly empty |
| Q8_0 text encoder read from disk (the old Low RAM) | Image bit-for-bit identical to the one from RAM |

## From 145 to 60 s

The previous recipe took ~145 s, almost four times as long as FLUX.3 Image Klein on the same machine, with a model of similar size. **The cause was the disk.** The recipe copied the weights (~9 GB) into the program's RAM; with that, the files no longer fit in the OS cache as well, and every image re-read ~9 GB from the hard disk: ~29 s for the text encoder and ~25 s more during sampling. This also explains why the old Low RAM sampled faster per step than Fast: it left more free RAM for the cache.

Each change was measured on its own with sd.cpp `8cd731e`, starting from the previous recipe at 1.4 MP:

| Change | Time per image | Image |
|---|---|---|
| Previous recipe on sd.cpp `8cd731e`, without `--diffusion-fa` | 145 s | The same scene |
| **Text encoder from disk** (`te=disk`) | **97 s** | Pixel-for-pixel identical |
| Transformer from disk too (`diffusion=disk`) | 101 s, with 1.5 GB of RAM instead of 5.5 | Pixel-for-pixel identical |
| **512 px VAE tiles** | −9 s (VAE from ~22 to ~13 s) | Almost identical (LPIPS 0.001), no seams |
| **1 MP instead of 1.4 MP** | **60.3 s** (the current recipe) | Text the same or better; blind test, a tie (6 to 5) |

What we tried and left out of the recipe:

- **EasyCache** (`--cache-mode easycache`): with 8 steps it skips 2 and saves 16 s, but the image comes out with visible grain (LPIPS 0.118 against the recipe).
- **768 px VAE tiles:** slower than 512 px tiles (17.7 s). **0.25 overlap between tiles:** leaves visible seams.
- **Q8_0 text encoder:** see [The recipe](#the-recipe).

LPIPS measures how different two images look to a person: 0 is identical, and the higher, the more different. Values of 0.02–0.05 were already noticed in a blind test with the images side by side. Raw data: [`bench/final-1016/`](bench/final-1016/) (the current recipe, 18 images).

## Comparison with the regular recipe

The two current recipes, at 1 MP and on sd.cpp `8cd731e`: Turbo and the [regular one](../Qwen-Image-2.1/README.md) (25 steps, no EasyCache). 6 prompts × 3 seeds each. Votes and answer keys of the blind tests in [`bench/cata-1016/`](bench/cata-1016/).

| | **Turbo** | Regular |
|---|---|---|
| Blind preference (12 comparisons) | **10** | 1 (+1 tie) |
| Images with perfect text (9 with text) | 6 / 9 | 3 / 9 |
| Infographic with 7 Spanish texts (3 seeds) | 16 / 21 | 16 / 21 |
| Time per image | **~60 s** | ~148 s |
| Peak program RAM | 1.4 GB | 5.2 GB |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/recipes-dark.webp">
  <img alt="Turbo and the regular recipe with the same ad and product shot" src="assets/recipes.webp">
</picture>

How much to trust each result:

- **Blind preference.** 12 pairs (6 prompts × seeds 42 and 7), in random order, one voter. Turbo won with both seeds on 4 of the 6 prompts (product, medical illustration, ad and anime). We ran four more blind tests to understand the result:

  | Blind test (12 pairs) | Result |
  |---|---|
  | Turbo against the regular recipe with EasyCache | 11 to 0 (1 tie) |
  | Regular without EasyCache against regular with EasyCache | 10 to 0 (2 ties) |
  | Turbo at 1 MP against the regular recipe at 1.4 MP | 10 to 0 (2 ties) |
  | Turbo at 1 MP against Turbo at 1.4 MP | 6 to 5 (1 tie) |

  The regular recipe does not win in any configuration. EasyCache makes the regular recipe visibly worse, which is why it goes without it.
- **A contradiction.** In the previous round, at 1.4 MP, the regular recipe won 9 of 18 comparisons against the two Turbo variants of the time. With the same regular images, it now loses 10 to 0. Since Turbo at 1 MP and at 1.4 MP tie, resolution does not explain it: the voter's judgement changed between rounds (the format changed too, from three images at once to pairs). This round's blind tests agree with each other. With a single voter, all of this is a signal, not proof.
- **Text.** The 9 text images per recipe are the ad, the product shot and the medical illustration (3 seeds each). Turbo got all 6 ads and product shots right and failed the 3 medical illustrations, always on the accent of "Rótula" ("Rötula", "Rôtula", "Rőtula"). The regular recipe got the 3 product shots right, 1 of 3 ads ("Envio" without the accent in the other 2) and 1 of 3 medical illustrations (a repeated "Tibia" in one; a repeated "Menisco", "Cartíllago" and an illegible label in another). Text was checked letter by letter, at full size, not with OCR.

## What it is good for

Tested prompts: product shots, portraits, ads with Spanish text, concept art, anime illustration and city scenes. Short text is the model's strong point: ads and product labels, accents included. Lists of small labels (the medical illustration) fail.

**Infographics: we don't recommend them.** The text comes out well in English and so-so in Spanish, but the figures don't explain what the text says. We tested two infographics with 7 texts each, in Spanish and in English, with both recipes and 3 seeds: one on sleep habits and a technical one (how a heat pump works). We counted the texts letter by letter at full size. Prompts in [`prompts/textos-largos.tsv`](prompts/textos-largos.tsv); timings in [`bench/idioma-1016/`](bench/idioma-1016/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/text-language-dark.webp">
  <img alt="Infographic and technical sheet in Spanish and English, with the correct texts of each and generic figures" src="assets/text-language.webp">
</picture>

| Infographic (7 texts × 3 seeds) | Turbo | Regular |
|---|---|---|
| Sleep habits, Spanish | 16 / 21 | 16 / 21 |
| **Sleep habits, English** | **21 / 21** | **21 / 21** |
| Heat pump, Spanish | 15 / 21 | 15 / 21 |
| **Heat pump, English** | **18 / 21** | **17 / 21** |

- **In Spanish it fails on long words with accents or ñ:** "Acuréstate", "ejlercicio" and "mañaña" in the infographic (seed 42, above); "El válvula", "pressión" and "expansió" in the technical sheets.
- **In English, the only repeated error** is that it drops the brackets of "(COP)" in the technical sheets.
- **The figures are unrelated to the text or explain nothing.** In the sleep infographic some fit (a clock, a screen, a dark room), but "exercise" comes out as a table with a lamp or a cloud, and "light dinner" as a glass of wine. In the technical sheet, the four stages of the heat pump (evaporator, compressor, condenser and valve) are almost the same generic machine in another colour, or (in Spanish, seed 42) two lab beakers, a flame and a tray: there is no outdoor and indoor unit and no circuit, so the image does not show how it works. It happens in English and in Spanish alike, and with both recipes.
- If you need an infographic, generate only the illustrations (one per image, no text) and lay out the text in another program. For long Spanish text inside the image, [FLUX.3 Image Klein](../FLUX.3-Image-Klein/README.md) got 21 of 21 in the same infographic, although its figures don't show the habit either.

**Technical and academic images.** We tested 12 subjects across disciplines, without text in the image, 2 seeds each, with the previous recipe (1.4 MP, same model). Raw data: [`bench/tecnico-turbo/`](bench/tecnico-turbo/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/technical-dark.webp">
  <img alt="12 technical subjects with a verdict for each" src="assets/technical.webp">
</picture>

- **Usable (8):** heart, cell, flower, engine, suspension bridge, prism, Earth's layers, solar system. The engine now draws a single cylinder, as the prompt asks.
- **Illustrative (3):** knee (the kneecap is still in the wrong place), dodecahedron (some faces look like hexagons), circuit. Recognizable, fine for a general audience; a specialist would spot errors.
- **Not usable (1):** caffeine. It is not the molecule requested.

With the regular model at 15 steps (earlier round) the split was 7 / 4 / 1, and the engine was only illustrative.

In short: good for textbook-style figures of big, familiar structures. Not reliable where details must be exact: specific molecules, precise mechanical parts or the spatial relation between parts. **Generate without labels and add them yourself:** when asked for labels, the model spells them well but points them at the wrong part.

## Other things to know

- **Keep `--vae-tiling`.** Decoding a 1 MP image in one piece needs more than 6 GB and sd.cpp falls back to tiling anyway. Since [`19bbbca`](https://github.com/leejet/stable-diffusion.cpp/commit/19bbbca1), `--vae-tile-size` is measured in image pixels, not latent cells. **Never decode on the CPU without tiling:** at 1024² it used all 16 GB of RAM and the kernel killed the process.
- **The first images after a reboot or a model switch are slower** if the weights live on a hard disk: ~10 GB have to be read to fill the OS cache. In our tests the first 1–3 took 70–90 s; after that, ~60 s.
- **Don't benchmark while downloading.** Downloads to the same disk evict the weights from the cache, and the recipe reads them from disk again.
- **The VRAM column always shows ~5.1–5.2 GB.** sd.cpp fills whatever is free and streams the rest from RAM. It is what it uses, not what it needs; the minimum VRAM has not been measured.
- **Output PNGs are RGBA** even for opaque images, because Qwen-Image 2.1 supports transparency.

## Reproduce the measurements

```bash
scripts/final-1016.sh turbo|normal   # the current recipes: 6 prompts × 3 seeds (resumable)
scripts/bench.sh <round> <name> <model> <steps> <prompt_id> [W H] [-- extra sd-cli args]
scripts/turbo1.sh     # Turbo configuration: quantization, resolution, schedule, encoder (previous round)
scripts/final.sh      # comparison and technical test of the previous round (resumable)
```

`final-1016.sh` writes one log and one `resultados.csv` row per image; the columns are explained at the top of the script. The blind tests were built from the images of those runs; [`bench/cata-1016/`](bench/cata-1016/) has the votes and answer key of each.

`bench.sh` takes either the suffix of a model file or the full path to a `.gguf` (as for the Turbo model). The `LLM` environment variable selects the text encoder; by default it is the Q4_K_M.

Prompts are in [`prompts/`](prompts/). Every run appends one row to a `resultados.csv` with the time, the peak RAM and VRAM and the exact flags; the images and logs are written next to it but are not included in this repo. Data by round: [`bench/final-1016/`](bench/final-1016/) (the current recipe), [`bench/cata-1016/`](bench/cata-1016/) (this round's blind tests), [`bench/idioma-1016/`](bench/idioma-1016/) (long text in Spanish and English), [`bench/turbo1/`](bench/turbo1/) (Turbo configuration), [`bench/final/`](bench/final/) (previous round's comparison, with its blind test in [`bench/final/ciego/`](bench/final/ciego/)) and [`bench/tecnico-turbo/`](bench/tecnico-turbo/) (technical test). The scripts assume the model paths of the test machine; edit `D` and `SD` at the top of `bench.sh`.

## Test machine

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5.8 GiB usable), driver 595.71.05, CUDA 13.0 |
| CPU / RAM | 6 cores, 16 GB |
| Storage | Weights on a 7200 rpm hard disk |
| OS | Ubuntu 24.04 |
| sd.cpp | Current recipe: `8cd731e` (2026-10-15). Previous round (Turbo tuning, technical test, 1.4 MP blind test): `f89d9b1` (2026-10-09) |

## License

The scripts in this folder are released under the [MIT license](../LICENSE). The model weights are not included and keep their own licenses: the Turbo checkpoint and the VAE under the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (non-commercial); the Qwen3-VL text encoder under Apache 2.0.
