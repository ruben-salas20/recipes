# Qwen-Image 2.1 Turbo en una GPU de 6 GB

Receta medida para ejecutar [Qwen-Image 2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo) en local en una **RTX 3050 con 6 GB de VRAM y 16 GB de RAM**, con [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Sin ComfyUI y sin entorno de Python: un binario compilado y tres ficheros de modelo.

Turbo es el checkpoint oficial `Qwen/Qwen-Image-2.1-Turbo`: la misma arquitectura de 7B que Qwen-Image 2.1, destilada a 8 pasos con CFG 1 y con su propio calendario de ruido. Usa el mismo VAE y el mismo codificador de texto que Qwen-Image 2.1.

**Unos 60 s por imagen de 1 MP, con 1,4 GB de RAM.** Es la receta de Qwen-Image que recomendamos: en una cata a ciegas ganó 10 de 12 comparaciones a la [receta normal](../Qwen-Image-2.1/README.es.md), que tarda unos 2 min 30 s. Escribe bien el texto corto en español (anuncios, etiquetas de producto). Con textos largos, como una infografía, acierta mucho más en inglés que en español.

Todos los números de esta página se midieron en esa máquina. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, un CSV por ronda, en [`bench/`](bench/).

[English version](README.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/showcase-dark.es.webp">
  <img alt="Seis estilos con la receta Turbo: producto, retrato, ilustración médica, anuncio, ciudad y anime" src="assets/showcase.es.webp">
</picture>

*Los 6 prompts de prueba con la receta y la semilla 42, sin elegir: es la primera y única imagen de cada uno.*

> [!IMPORTANT]
> **Los pesos del modelo solo se pueden usar con fines no comerciales.** El checkpoint Turbo está bajo la [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (sección 2), las mismas condiciones que Qwen-Image 2.1: se permiten la investigación y la evaluación. El uso comercial, incluidos anuncios o fotos de producto para un negocio, requiere una licencia aparte de Qwen (`model-business@notice.qwencloud.com`). Esta guía explica cómo ejecutar el modelo, no qué puedes hacer con lo que genera.

## La receta

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
  -p "tu prompt" -o salida.png
```

- **`--sigmas` es obligatorio.** Sin él, el modelo Turbo produce texto roto (ver [Ajustar el modelo Turbo](#ajustar-el-modelo-turbo)). Los nueve valores son el calendario de 8 pasos del propio checkpoint más el 0 final.
- **`--params-backend "te=disk,diffusion=disk,…"`** lleva el codificador de texto y el transformer del fichero a la GPU sin copiarlos a la RAM del programa. Es lo que más tiempo ahorra: ver [De 145 a 60 s](#de-145-a-60-s).
- **`--vae-tile-size 512`** decodifica la imagen en trozos de 512 px en lugar de 256: el VAE pasa de ~22 a ~13 s, sin costuras visibles.
- **No añadas `--diffusion-fa`**: está obsoleto. Flash attention viene activada por defecto (`--flash-attn auto`).

| | |
|---|---|
| Para qué | El día a día: anuncios, fotos de producto, retratos, ilustración |
| Modelo de difusión | Turbo AD-Q4_K |
| Codificador de texto | Q4_K_M, leído del disco |
| Pasos | 8 |
| Cuadrada | 1024 × 1024 |
| Vertical 9:16 | 768 × 1344 |
| Horizontal 16:9 | 1344 × 768 |
| Tiempo por imagen | **~60 s** (media 60,3 s, rango 58,2-63,5 s) |
| RAM máxima del programa | 1,4 GB |
| RAM libre que necesita | ~10 GB para la caché del sistema (ver abajo) |

Usa CFG 1. El tiempo es de reloj e incluye toda la ejecución: carga, codificación del texto, muestreo y VAE. Medias de 6 prompts × 3 semillas, después de una imagen de calentamiento. Las medidas tienen que ser múltiplos de 32.

> [!WARNING]
> **La velocidad depende de que los ficheros quepan en la caché del sistema.** El programa usa poca RAM, pero lee el codificador (5 GB) y el transformer (4,2 GB) de los ficheros en cada imagen. Si el sistema los tiene en su caché de disco en RAM, esa lectura es casi gratis; para eso necesita unos 10 GB de RAM libre. En la máquina de pruebas (16 GB, sin otros programas grandes) cabían, y las primeras 1-3 imágenes después de cambiar de modelo tardaron 70-90 s mientras se llenaba la caché. Con menos RAM libre, el transformer se leería del disco en cada paso y la imagen tardaría mucho más; eso no lo hemos medido.

**Antes había dos variantes, Rápida y Poca RAM.** Ahora son una: la receta de arriba es tan rápida como la antigua Rápida y usa menos RAM que la antigua Poca RAM (1,4 GB frente a 5,3 GB). La antigua Poca RAM usaba el codificador Q8_0 (8,7 GB); lo quitamos porque con él los ficheros ya no caben en la caché y el codificador se relee del disco en cada imagen. En la cata a ciegas de la ronda anterior, Q8_0 y Q4_K_M empataron (3 votos cada uno) y escribieron el mismo texto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/before-after-dark.es.webp">
  <img alt="Segundos por imagen antes y ahora: Turbo de 145 a 60 s, normal de 273 a 148 s" src="assets/before-after.es.webp">
</picture>

## Instalación

### 1. Compilar stable-diffusion.cpp con CUDA

Usa [`8cd731e`](https://github.com/leejet/stable-diffusion.cpp/commit/8cd731e) (2026-10-15). La receta actual se midió con él; las versiones posteriores no se han probado. Hace falta como mínimo [`c150a6b`](https://github.com/leejet/stable-diffusion.cpp/commit/c150a6b) (2026-10-06), que arregló los calendarios de ruido a medida (`--sigmas`) que el modelo Turbo necesita.

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
git checkout 8cd731e && git submodule update --init --recursive
cmake -B build -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
# binarios: build/bin/sd-cli y build/bin/sd-server
```

`86` es la arquitectura de la serie RTX 30. Usa `89` para las RTX 40, o quita la opción para que CMake la detecte.

### 2. Descargar los ficheros del modelo

| Pieza | Fichero | Tamaño | SHA-256 |
|---|---|---|---|
| Modelo de difusión | [`Qwen-Image-2.1-Turbo-AD-Q4_K.gguf`](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF) (AtomicChat) | 4,20 GB | `4bb73c53…8130bc59` |
| Codificador de texto | [`Qwen3VL-8B-Instruct-Q4_K_M.gguf`](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/blob/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf) (Qwen) | 5,0 GB | `67d1659b…0e9e2` |
| VAE | [`qwen_image_2.1_vae_bf16.safetensors`](https://huggingface.co/Comfy-Org/Qwen-Image-2.1/blob/main/vae/qwen_image_2.1_vae_bf16.safetensors) (Comfy-Org) | 0,68 GB | `bb21f747…e4876b7c9` |

Los hashes completos están en [`SHA256SUMS`](SHA256SUMS). El VAE es exclusivo de la 2.1: los de Qwen-Image 1 y Wan 2.2 no sirven.

**Por qué los ficheros Turbo de AtomicChat.** El modelo Turbo es una cuantización del checkpoint oficial [Qwen/Qwen-Image-2.1-Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo). Elegimos los [ficheros GGUF de AtomicChat](https://huggingface.co/AtomicChat/Qwen-Image-2.1-Turbo-GGUF) porque midieron la fidelidad de cada cuantización frente al original en BF16 (LPIPS; AD-Q4_K obtiene 0,147) y publicaron sus renders. También comprobaron que un codificador de texto Q8_0 se desvía menos que un Q4_K_M; en nuestras catas no se notó (ver [La receta](#la-receta)). Verificamos su SHA-256 y la estructura de los ficheros: capas de modulación en Q8_0; timestep, norma final y proyección de salida en BF16.

### 3. Liberar la GPU

La receta usa la tarjeta entera. Cierra cualquier otro programa que ocupe VRAM (un servidor de LLM, Whisper) antes de generar, o la ejecución fallará por falta de memoria.

## Ajustar el modelo Turbo

Primera ronda, con la receta anterior (1,4 MP) y sd.cpp `f89d9b1`. Medido con los prompts de anuncio y producto, semilla 42. Datos en bruto: [`bench/turbo1/`](bench/turbo1/). Script: [`scripts/turbo1.sh`](scripts/turbo1.sh).

| Cambio | Resultado |
|---|---|
| **AD-Q4_K a 1,4 MP (la receta de entonces)** | **140 s** |
| AD-Q5_K | 152-154 s y 10,5 GB de RAM, sin mejora visible |
| 1 MP | 122 s, pero deformó "MAGNESIO". Con la receta actual no se repitió: 10 de 10 textos bien en anuncio y producto (ver abajo) |
| 2,4 MP | 215 s |
| **Sin `--sigmas`** | Cuesta lo mismo, pero el titular del anuncio sale roto (letras duplicadas, corchetes). **El calendario propio es obligatorio.** |
| Codificador Q8_0 en RAM | 152-172 s y 12,6 GB de RAM; solo cabe con la máquina casi vacía |
| Codificador Q8_0 en disco (la antigua Poca RAM) | Imagen idéntica bit a bit a la de RAM |

## De 145 a 60 s

La receta anterior tardaba ~145 s, casi cuatro veces lo que FLUX.3 Image Klein en la misma máquina, con un modelo de tamaño parecido. **La causa era el disco.** La receta copiaba los pesos (~9 GB) a la RAM del programa; con eso, los ficheros ya no cabían también en la caché del sistema, y en cada imagen se volvían a leer ~9 GB del disco duro: ~29 s el codificador de texto y ~25 s más durante el muestreo. Eso explica también por qué la antigua Poca RAM muestreaba más rápido por paso que la Rápida: dejaba más RAM libre para la caché.

Cada cambio se midió por separado con sd.cpp `8cd731e`, empezando por la receta anterior a 1,4 MP:

| Cambio | Tiempo por imagen | Imagen |
|---|---|---|
| Receta anterior con sd.cpp `8cd731e`, sin `--diffusion-fa` | 145 s | La misma escena |
| **Codificador desde disco** (`te=disk`) | **97 s** | Idéntica píxel a píxel |
| Transformer también desde disco (`diffusion=disk`) | 101 s, con 1,5 GB de RAM en vez de 5,5 | Idéntica píxel a píxel |
| **VAE en trozos de 512 px** | −9 s (VAE de ~22 a ~13 s) | Casi idéntica (LPIPS 0,001), sin costuras |
| **1 MP en vez de 1,4 MP** | **60,3 s** (la receta actual) | Texto igual o mejor; a ciegas, empate (6 a 5) |

Lo que probamos y no entró en la receta:

- **EasyCache** (`--cache-mode easycache`): con 8 pasos se salta 2 y ahorra 16 s, pero la imagen sale con grano visible (LPIPS 0,118 frente a la receta).
- **Trozos de VAE de 768 px:** más lentos que los de 512 px (17,7 s). **Solape de 0,25 entre trozos:** deja costuras visibles.
- **Codificador Q8_0:** ver [La receta](#la-receta).

LPIPS mide cuánto se diferencian dos imágenes tal como las percibe una persona: 0 es idéntica, y cuanto más alto, más diferentes. Valores de 0,02-0,05 ya se notaron en una cata a ciegas con las imágenes lado a lado. Datos en bruto: [`bench/final-1016/`](bench/final-1016/) (la receta actual, 18 imágenes).

## Comparativa con la receta normal

Las dos recetas actuales, a 1 MP y con sd.cpp `8cd731e`: Turbo y la [normal](../Qwen-Image-2.1/README.es.md) (25 pasos, sin EasyCache). 6 prompts × 3 semillas cada una. Votos y claves de las catas en [`bench/cata-1016/`](bench/cata-1016/).

| | **Turbo** | Normal |
|---|---|---|
| Preferencia a ciegas (12 comparaciones) | **10** | 1 (+1 empate) |
| Imágenes con el texto perfecto (9 con texto) | 6 / 9 | 3 / 9 |
| Infografía con 7 textos en español (3 semillas) | 16 / 21 | 16 / 21 |
| Tiempo por imagen | **~60 s** | ~148 s |
| RAM máxima del programa | 1,4 GB | 5,2 GB |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/recipes-dark.es.webp">
  <img alt="Turbo y la receta normal con el mismo anuncio y producto" src="assets/recipes.es.webp">
</picture>

Cuánto fiarse de cada resultado:

- **Preferencia a ciegas.** 12 parejas (6 prompts × semillas 42 y 7), en orden aleatorio, con un solo votante. Turbo ganó con las dos semillas en 4 de los 6 prompts (producto, ilustración médica, anuncio y anime). Hicimos cuatro catas más para entender el resultado:

  | Cata (12 parejas) | Resultado |
  |---|---|
  | Turbo frente a la normal con EasyCache | 11 a 0 (1 empate) |
  | Normal sin EasyCache frente a la normal con EasyCache | 10 a 0 (2 empates) |
  | Turbo a 1 MP frente a la normal a 1,4 MP | 10 a 0 (2 empates) |
  | Turbo a 1 MP frente a Turbo a 1,4 MP | 6 a 5 (1 empate) |

  La normal no gana en ninguna configuración. EasyCache empeora la normal de forma visible, por eso la receta normal va sin él.
- **Una contradicción.** En la ronda anterior, a 1,4 MP, la normal ganó 9 de 18 comparaciones frente a las dos variantes del Turbo de entonces. Con las mismas imágenes de la normal, ahora pierde 10 a 0. Como Turbo a 1 MP y a 1,4 MP empatan, la resolución no lo explica: cambió el criterio del votante entre una ronda y otra (también cambió el formato, de tres imágenes a la vez a parejas). Las catas de esta ronda son coherentes entre sí. Con un solo votante, todo esto es una señal, no una prueba.
- **Texto.** Las 9 imágenes con texto de cada receta son el anuncio, el producto y la ilustración médica (3 semillas cada uno). Turbo acertó los 6 anuncios y productos y falló las 3 ilustraciones médicas, siempre en la tilde de "Rótula" ("Rötula", "Rôtula", "Rőtula"). La normal acertó los 3 productos, 1 de 3 anuncios ("Envio" sin tilde en los otros 2) y 1 de 3 ilustraciones médicas ("Tibia" repetida en una; "Menisco" repetida, "Cartíllago" y una etiqueta ilegible en otra). El texto se revisó letra por letra, a tamaño completo, no con OCR.

## Para qué sirve

Prompts probados: fotos de producto, retratos, anuncios con texto en español, concept art, ilustración anime y escenas de ciudad. El texto corto es el punto fuerte del modelo: anuncios y etiquetas de producto, tildes incluidas. Las listas de etiquetas pequeñas (la ilustración médica) fallan.

**Infografías: no las recomendamos.** El texto sale bien en inglés y regular en español, pero las figuras no explican lo que dice el texto. Probamos dos infografías con 7 textos cada una, en español y en inglés, con las dos recetas y 3 semillas: una de hábitos de sueño y una técnica (cómo funciona una bomba de calor). Contamos los textos letra por letra a tamaño completo. Prompts en [`prompts/textos-largos.tsv`](prompts/textos-largos.tsv); tiempos en [`bench/idioma-1016/`](bench/idioma-1016/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/text-language-dark.es.webp">
  <img alt="Infografía y lámina técnica en español y en inglés, con los textos acertados de cada una y figuras genéricas" src="assets/text-language.es.webp">
</picture>

| Infografía (7 textos × 3 semillas) | Turbo | Normal |
|---|---|---|
| Hábitos de sueño, español | 16 / 21 | 16 / 21 |
| **Hábitos de sueño, inglés** | **21 / 21** | **21 / 21** |
| Bomba de calor, español | 15 / 21 | 15 / 21 |
| **Bomba de calor, inglés** | **18 / 21** | **17 / 21** |

- **En español falla en palabras largas con tilde o eñe:** "Acuréstate", "ejlercicio" y "mañaña" en la infografía (semilla 42, arriba); "El válvula", "pressión" y "expansió" en las láminas técnicas.
- **En inglés, el único fallo repetido** es que quita los paréntesis de "(COP)" en las láminas técnicas.
- **Las figuras no tienen relación con el texto o no explican nada.** En la infografía del sueño, algunas encajan (un reloj, una pantalla, un cuarto oscuro), pero "hacer ejercicio" sale como una mesa con lámpara o una nube, y "cena ligera" como una copa de vino. En la lámina técnica, las cuatro fases de la bomba de calor (evaporador, compresor, condensador y válvula) son casi la misma máquina genérica con otro color, o (en español, semilla 42) dos vasos de laboratorio, una llama y una bandeja: no hay unidad exterior e interior ni circuito, así que la imagen no enseña cómo funciona. Pasa igual en inglés y en español, y con las dos recetas.
- Si necesitas una infografía, genera solo las ilustraciones (una por imagen, sin texto) y compón el texto y la maqueta en otro programa. Para texto largo en español dentro de la imagen, [FLUX.3 Image Klein](../FLUX.3-Image-Klein/README.es.md) acertó 21 de 21 en la misma infografía, aunque sus figuras tampoco muestran el hábito.

**Imágenes técnicas y académicas.** Probamos 12 temas de distintas disciplinas, sin texto en la imagen, 2 semillas cada uno, con la receta anterior (1,4 MP, mismo modelo). Datos en bruto: [`bench/tecnico-turbo/`](bench/tecnico-turbo/).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/technical-dark.es.webp">
  <img alt="12 temas técnicos con su veredicto" src="assets/technical.es.webp">
</picture>

- **Sirven (8):** corazón, célula, flor, motor, puente colgante, prisma, capas de la Tierra y sistema solar. El motor ahora dibuja un solo cilindro, como pide el prompt.
- **Ilustrativas (3):** rodilla (la rótula sigue mal colocada), dodecaedro (algunas caras parecen hexágonos) y circuito. Se reconocen y valen para público general, pero un especialista vería errores.
- **No sirve (1):** cafeína. No es la molécula pedida.

Con el modelo normal a 15 pasos (ronda anterior), el reparto fue 7 / 4 / 1, y el motor solo era ilustrativo.

En resumen: sirve para figuras de libro de texto de estructuras grandes y conocidas. No es fiable cuando los detalles tienen que ser exactos: moléculas concretas, piezas mecánicas precisas o la relación espacial entre partes. **Genera sin etiquetas y ponlas tú:** cuando se le piden, el modelo las escribe bien pero las coloca apuntando a la parte equivocada.

## Otras cosas que conviene saber

- **Mantén `--vae-tiling`.** Decodificar una imagen de 1 MP de una vez necesita más de 6 GB, y sd.cpp acaba recurriendo a los trozos igualmente. Desde [`19bbbca`](https://github.com/leejet/stable-diffusion.cpp/commit/19bbbca1), `--vae-tile-size` se mide en píxeles de la imagen, no en celdas del latente. **Nunca decodifiques en CPU sin trozos:** a 1024² agotó los 16 GB de RAM y el kernel mató el proceso.
- **Las primeras imágenes tras reiniciar o cambiar de modelo tardan más** si los pesos están en un disco duro mecánico: hay que leer ~10 GB hasta llenar la caché del sistema. En nuestras pruebas, las 1-3 primeras tardaron 70-90 s; después, ~60 s.
- **No midas mientras descargas.** Las descargas al mismo disco expulsan los pesos de la caché, y la receta vuelve a leerlos del disco.
- **La columna de VRAM siempre marca ~5,1-5,2 GB.** sd.cpp ocupa toda la memoria libre y trae el resto desde la RAM. Es lo que usa, no lo que necesita; la VRAM mínima no se ha medido.
- **Los PNG de salida son RGBA** aunque la imagen sea opaca, porque Qwen-Image 2.1 admite transparencia.

## Reproducir las medidas

```bash
scripts/final-1016.sh turbo|normal   # las recetas actuales: 6 prompts × 3 semillas (reanudable)
scripts/bench.sh <ronda> <nombre> <modelo> <pasos> <prompt_id> [W H] [-- opciones extra de sd-cli]
scripts/turbo1.sh     # configuración del Turbo: cuantización, resolución, calendario, codificador (ronda anterior)
scripts/final.sh      # comparativa y prueba técnica de la ronda anterior (reanudable)
```

`final-1016.sh` escribe un log y una fila de `resultados.csv` por imagen; las columnas se explican al principio del script. Las catas a ciegas se montaron con las imágenes de esas tandas; en [`bench/cata-1016/`](bench/cata-1016/) están los votos y la clave de cada una.

`bench.sh` acepta el sufijo de un fichero de modelo o la ruta completa de un `.gguf` (como el del Turbo). La variable de entorno `LLM` elige el codificador de texto; por defecto es el Q4_K_M.

Los prompts están en [`prompts/`](prompts/). Cada ejecución añade una fila a un `resultados.csv` con el tiempo, la RAM y la VRAM máximas y las opciones exactas; las imágenes y los logs se guardan al lado, pero no se incluyen en este repo. Datos por ronda: [`bench/final-1016/`](bench/final-1016/) (la receta actual), [`bench/cata-1016/`](bench/cata-1016/) (catas de la ronda actual), [`bench/idioma-1016/`](bench/idioma-1016/) (textos largos en español e inglés), [`bench/turbo1/`](bench/turbo1/) (configuración del Turbo), [`bench/final/`](bench/final/) (comparativa de la ronda anterior, con su cata en [`bench/final/ciego/`](bench/final/ciego/)) y [`bench/tecnico-turbo/`](bench/tecnico-turbo/) (prueba técnica). Los scripts usan las rutas de la máquina de pruebas; cambia `D` y `SD` al principio de `bench.sh`.

## Máquina de pruebas

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5,8 GiB utilizables), driver 595.71.05, CUDA 13.0 |
| CPU / RAM | 6 núcleos, 16 GB |
| Almacenamiento | Pesos en un disco duro de 7200 rpm |
| Sistema | Ubuntu 24.04 |
| sd.cpp | Receta actual: `8cd731e` (2026-10-15). Ronda anterior (ajustes del Turbo, prueba técnica, cata de 1,4 MP): `f89d9b1` (2026-10-09) |

## Licencia

Los scripts de esta carpeta se publican con la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen sus propias licencias: el checkpoint Turbo y el VAE, la [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (no comercial); el codificador de texto Qwen3-VL, Apache 2.0.
