# FLUX.3 Image Klein en una GPU de 6 GB

Receta medida para ejecutar [FLUX.3 Image Klein](https://huggingface.co/black-forest-labs/flux-3-image-klein) (Black Forest Labs, octubre de 2026) en local en una **RTX 3050 con 6 GB de VRAM y 16 GB de RAM**, con [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Sin ComfyUI y sin entorno de Python: un binario compilado y tres ficheros de modelo.

Klein es la versión destilada de FLUX.3 Image: un transformer de 5,5 B parámetros pensado para 16 pasos con CFG 1. Usa el VAE de FLUX.2 y Qwen3-VL 4B como codificador de texto.

**Unos 39 s por imagen de 1 MP, con 4,9 GB de RAM y 4,9 GB de VRAM.** Su punto fuerte es el texto en español dentro de la imagen: anuncios, etiquetas de producto, carteles. La edición con imágenes de referencia no sirve en 6 GB.

Todos los números de esta página se midieron en esa máquina. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, un CSV por ronda, en [`bench/`](bench/).

[English version](README.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/showcase-dark.es.webp">
  <img alt="Seis estilos con la receta: producto, retrato, ilustración médica, anuncio, ciudad y anime" src="assets/showcase.es.webp">
</picture>

*Los 6 prompts de prueba con la receta y la semilla 42, sin elegir: es la primera y única imagen de cada uno.*

> [!IMPORTANT]
> **Licencia de los pesos: [FLUX Kommunity License v1.0](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/LICENSE.md).** El uso no comercial es libre. Las imágenes generadas se pueden usar con fines comerciales si quien las genera cumple las condiciones de la licencia (entre otras, ingresos por debajo del límite que fija, revisar las imágenes antes de difundirlas y marcarlas como generadas por IA donde la ley lo pida). Léela entera antes de usarlas para un negocio. El repositorio de Hugging Face es restringido: hay que aceptar la licencia para descargar los pesos. Esta guía explica cómo ejecutar el modelo, no qué puedes hacer con lo que genera.

## La receta

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
  -p "tu prompt" -o salida.png
```

- **`--cache-mode easycache`** se salta el cálculo de los pasos en los que la imagen apenas cambia. A 16 pasos ahorró un tercio del tiempo y la imagen casi no cambió.
- **`--params-backend "te=disk,…"`** pasa el codificador de texto del fichero a la VRAM, lo usa y lo libera, sin guardarlo en RAM. Igual de rápido que tenerlo en RAM y 2,2 GB menos de RAM.
- **8 pasos** en lugar de los 16 de la documentación: ganó una cata a ciegas frente a 16 pasos (ver [Por qué estos ajustes](#por-qué-estos-ajustes)).
- **No añadas `--diffusion-fa`**: está obsoleto. Flash attention viene activada por defecto (`--flash-attn auto`) y es imprescindible: sin ella el modelo no cabe.

| | Receta | Más detalle | Menos memoria |
|---|---|---|---|
| Para qué | El día a día | Retratos e ilustración con detalle fino | Máquinas con poca RAM o VRAM libre |
| Modelo de difusión | Q6_K | Q6_K | Q5_K |
| Pasos | 8 | 16 | 16 (a 8 pasos, sin medir) |
| Tiempo por imagen | **~39 s** (media 38,6; rango 34-54) | ~52 s | ~49 s |
| RAM máxima del proceso | 4,9 GB | 4,9 GB | 4,3 GB |
| VRAM máxima | 4,9 GB | 4,9 GB | 4,3 GB |

Las tres usan EasyCache, el codificador desde disco y CFG 1. El tiempo es de reloj e incluye toda la ejecución: carga, codificación del texto, muestreo y VAE. Medias de 6 prompts × 3 semillas. Tamaños probados: 1024 × 1024, 768 × 1344 y 1344 × 768.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/recipes-dark.es.webp">
  <img alt="La receta y sus dos variantes con el mismo anuncio y la misma foto de producto" src="assets/recipes.es.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/speed-dark.es.webp">
  <img alt="Segundos por imagen de cada configuración" src="assets/speed.es.webp">
</picture>

## Instalación

### 1. Compilar stable-diffusion.cpp con CUDA

Usa [`8cd731e`](https://github.com/leejet/stable-diffusion.cpp/commit/8cd731e) (2026-10-15), el commit que añadió FLUX.3 Image Klein (PR #2143). Todo lo de esta página se midió con él; las versiones posteriores no se han probado.

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
git checkout 8cd731e && git submodule update --init --recursive
cmake -B build -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
# binario: build/bin/sd-cli
```

`86` es la arquitectura de la serie RTX 30. Usa `89` para las RTX 40, o quita la opción para que CMake la detecte.

### 2. Descargar los pesos

Del repo de BFL (hay que aceptar la licencia en la página del modelo) y del repo oficial de Qwen:

| Pieza | Fichero | Tamaño | SHA-256 |
|---|---|---|---|
| Transformer, original | [`model.safetensors`](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/model.safetensors) (BFL, BF16) | 11,1 GB | `c3e9813c…fee0bd7c` |
| VAE | [`ae.safetensors`](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/ae.safetensors) (BFL) | 0,34 GB | `868fe7b3…066ce8f3` |
| Codificador de texto | [`Qwen3VL-4B-Instruct-Q8_0.gguf`](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/blob/main/Qwen3VL-4B-Instruct-Q8_0.gguf) (Qwen) | 4,28 GB | `054721f4…27863eb1` |

Los hashes completos están en [`SHA256SUMS`](SHA256SUMS).

### 3. Convertir el transformer a GGUF

BFL publica el transformer en BF16 (11,1 GB), que no cabe en la GPU. sd.cpp lo convierte en unos minutos, sin pasar de 2,6 GB de RAM:

```bash
build/bin/sd-cli -M convert -m model.safetensors -o flux-3-image-klein-q6_K.gguf --type q6_K
build/bin/sd-cli -M convert -m model.safetensors -o flux-3-image-klein-q5_K.gguf --type q5_K   # variante «Menos memoria»
```

| Tipo | Tamaño | Bits por peso | Tiempo de conversión | SHA-256 del resultado |
|---|---|---|---|---|
| Q6_K | 4,67 GB | 6,74 | 2 min 9 s | `cae4ed97…af3d444d` |
| Q5_K | 3,95 GB | 5,70 | 5 min 17 s | `c3f1cb07…6d58b4d6` |

Con el mismo commit de sd.cpp deberías obtener el mismo SHA-256. Hay GGUF ya convertidos en [`Abiray/flux-3-image-klein-sd-GGUF`](https://huggingface.co/Abiray/flux-3-image-klein-sd-GGUF), pensados para ComfyUI. Cada fichero pesa 22 112 bytes más que el nuestro del mismo tipo, lo que apunta a los mismos tensores con más metadatos. Sus parejas `_S` y `_M` pesan lo mismo byte a byte, y su tabla de calidad por tipo no está medida. No hemos comprobado si sd.cpp los carga.

### 4. Liberar la GPU

La receta usa casi toda la tarjeta. Cierra cualquier otro programa que ocupe VRAM (un servidor de LLM, Whisper) antes de generar: sd.cpp no reparte el modelo en trozos y, si no cabe, falla.

## Por qué estos ajustes

Cada ronda cambió una sola cosa, con los prompts de anuncio, producto y retrato y las semillas 42 y 7. Para medir cuánto se aparta una imagen de otra usamos [LPIPS](https://github.com/richzhang/PerceptualSimilarity): 0 es idéntica, y por debajo de ~0,02 cuesta ver diferencias a simple vista. LPIPS dice cuánto cambia la imagen, no si mejora o empeora. Datos en [`bench/`](bench/).

| Ronda | Qué se probó | Resultado |
|---|---|---|
| Cuantización | Q6_K, Q5_K y Q4_K (Q8_0 y la FP8 de BFL no caben) | Q5_K se aparta poco de Q6_K (LPIPS 0,040) y Q4_K más (0,097: otra cara, otra losa). Bajar de tipo apenas acelera (−6 % y −8 %); lo que se gana es memoria |
| Codificador | Q4_K_M en RAM, Q8_0 en RAM y Q8_0 desde disco | Q8_0 en RAM es más lento (93-107 s): no cabe todo en la caché del sistema y relee el disco. Desde disco, igual de rápido que Q4_K_M y con 2,2 GB menos de RAM |
| Pasos | 16, 12 y 8 | 12 pasos −22 %; 8 pasos −42 %, con el texto bien |
| Resolución | 1 MP y 1,4 MP | 1,4 MP mejora algo el detalle de la piel, pero tarda un 37 % más. Se queda en 1 MP |
| EasyCache | Apagado y encendido | Se salta 6 de 16 pasos: −33 % de tiempo con LPIPS 0,019 |
| Flash attention | `auto`, `on` y `off` | `auto` ya la activa; sin ella no cabe |

**La cata a ciegas.** Tres variantes (Q6_K a 8 pasos, Q6_K a 16 y Q5_K a 16) con los 6 prompts × 3 semillas, al mismo tamaño y en orden aleatorio. Votó una sola persona.

| Prompt | Q6_K · 8 pasos | Q6_K · 16 pasos | Q5_K · 16 pasos | Empate |
|---|---|---|---|---|
| Anuncio | **3** | 0 | 0 | 0 |
| Ciudad | **3** | 0 | 0 | 0 |
| Médico | 1 | 0 | 1 | 1 |
| Anime | 0 | **2** | 0 | 1 |
| Retrato | 0 | **2** | 1 | 0 |
| Producto | 0 | 1 | 0 | 2 |
| **Total** | **7** | **5** | **2** | **4** |

Cuánto fiarse: 8 pasos ganó 7 de las 14 filas con ganadora, con un solo votante y 18 filas. Es una señal clara, no una prueba. Por eso la receta usa 8 pasos y deja 16 como variante para el detalle fino, donde ganó (retratos y anime). Votos y clave en [`bench/4-cata/ciego/`](bench/4-cata/ciego/).

## Para qué sirve

**Texto en español dentro de la imagen.** Es su punto fuerte. Con la receta, los 15 textos de los 3 anuncios y las 3 fotos de producto (semillas 42, 7 y 123) salieron bien letra por letra, con tildes y signos de apertura, revisados a tamaño completo. Las ilustraciones con muchas etiquetas pequeñas fallan: en la rodilla, las etiquetas están bien escritas, pero señalan partes equivocadas y falta una.

**Infografías: a medias.** Probamos un póster con 7 textos en español (título, 5 puntos y una fuente) con 3 semillas. Los 21 textos salieron bien, pero los iconos no ilustran el contenido: son siluetas o manchas genéricas.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/infographic-dark.es.webp">
  <img alt="Tres infografías con el texto correcto y figuras sin relación con el texto" src="assets/infographic.es.webp">
</picture>

**Imágenes técnicas y académicas: solo ilustrativas.** 12 temas de distintas disciplinas, sin texto en la imagen, con las semillas 42 y 7. Datos: [`bench/5-tecnico/`](bench/5-tecnico/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/technical-dark.es.webp">
  <img alt="12 temas técnicos con su veredicto" src="assets/technical.es.webp">
</picture>

- **Ilustrativas (10):** se reconoce el tema y valen para público general, pero un especialista vería errores. Por ejemplo, la rótula fuera de sitio, un motor con piezas sin lógica, más capas de las que tiene la Tierra o un noveno planeta.
- **No sirven (2):** la cafeína, con una molécula inventada, y el dodecaedro, sin caras pentagonales.
- Con 16 pasos, los mismos veredictos.

**Edición con imágenes de referencia: no sirve en 6 GB.** Con Q6_K no cabe ni con las referencias reducidas. Con Q5_K y las referencias reducidas (a 0,5 MP con una referencia y a 0,25 MP con dos) cabe y tarda ~47 s, pero todas las ediciones dejan ruido. Al combinar dos imágenes, además, las manos salen mal. Cambiar la hora del día solo funcionó a medias. Sin investigar si el ruido viene de reducir las referencias, de los 8 pasos o de Q5_K.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/editing-noise-dark.es.webp">
  <img alt="Recortes ampliados: ruido en la camiseta tras editar y manos deformes al combinar" src="assets/editing-noise.es.webp">
</picture>

## Otras cosas que conviene saber

- **Q8_0 y la FP8 de BFL no corren en la GPU** con `8cd731e`. sd.cpp deja el transformer entero en un solo bloque aunque no quepa (pide 5761 MB para Q8_0 y hay unos 5700 libres), y `--max-vram` no lo cambia. Q8_0 funciona con el transformer en la CPU (`--backend diffusion=cpu`), pero tarda 19 min por imagen a 512 × 512.
- **El prompt se sigue a medias en acciones y detalles.** «Un hombre caminando» salió de pie con la semilla 42 y caminando con la 7; «vehículos voladores» salieron como coches. A veces añade franjas negras de cine arriba y abajo en los formatos horizontales.
- **La primera imagen tras cambiar de fichero tarda más** si los pesos están en un disco duro mecánico: hay que leerlos. Después quedan en la caché del sistema. El codificador desde disco depende de esa caché: con la RAM llena de otros programas, se leería del disco en cada imagen.
- **La misma semilla y la misma configuración dan la misma imagen,** byte a byte.
- **No hemos usado el reescritor de prompts de BFL** (`flux-3-image-klein-pup`, 18,8 GB, no cabe aquí), que BFL recomienda. Los prompts se usaron tal cual.

## Reproducir las medidas

```bash
scripts/descargar.sh      # descarga con commit fijado y comprobación de SHA-256
scripts/convertir.sh      # BF16 -> GGUF, con tamaño, RAM y SHA-256 de cada tipo
scripts/estilos.sh <tipo> <semilla> [carpeta]   # los prompts de estilos con una configuración
scripts/3a.sh … scripts/3g.sh                   # las rondas de ajuste
scripts/4-cata.sh y scripts/4-cata-p8.sh        # la cata a ciegas
scripts/5-tecnico.sh y scripts/5-tecnico-p16.sh       # técnico a 8 y a 16 pasos
scripts/5-infografia.sh y scripts/5-edicion.sh
scripts/lpips_vs.py <referencia.png> <imagen.png>...   # LPIPS (AlexNet, CPU)
```

`estilos.sh` acepta variables de entorno para cambiar el codificador (`LLM`), los pasos (`STEPS`), la lista de prompts (`TSV`) y opciones extra (`EXTRA`). Los prompts están en [`prompts/`](prompts/). Cada ejecución añade una fila a un `resultados.csv` con el tiempo total, el del codificador, el muestreo y el VAE, y la RAM y la VRAM máximas. Las imágenes y los logs no se incluyen en este repo. Los scripts usan las rutas de la máquina de pruebas; cámbialas al principio de cada uno.

## Máquina de pruebas

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5,8 GiB utilizables), driver 595.91.07 |
| CPU / RAM | Intel Core i5-9400 (6 núcleos), 16 GB |
| Almacenamiento | Pesos en un disco duro de 7200 rpm |
| Sistema | Ubuntu 24.04.5, CUDA 13.0 para compilar |
| sd.cpp | `8cd731e` (2026-10-15) en todas las pruebas de esta página |

## Licencia

Los scripts de esta carpeta se publican con la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen sus propias licencias: el transformer y el VAE, la [FLUX Kommunity License v1.0](https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/LICENSE.md); el codificador de texto Qwen3-VL, Apache 2.0. Los GGUF que conviertas a partir del transformer son obras derivadas y siguen la licencia de BFL: solo se pueden redistribuir sin fines comerciales, con la licencia y su aviso.
