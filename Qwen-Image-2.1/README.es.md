# Qwen-Image 2.1 en una GPU de 6 GB

Receta medida para ejecutar [Qwen-Image 2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) en local en una **RTX 3050 con 6 GB de VRAM y 16 GB de RAM**, con [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). Sin ComfyUI y sin entorno de Python: un binario compilado y tres ficheros de modelo.

Todos los números de esta página se midieron en esa máquina. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, un CSV por ronda, en [`bench/`](bench/).

[English version](README.md)

![Cinco imágenes generadas con la receta por defecto](assets/showcase.webp)
*Receta por defecto, semilla 42, sin elegir las mejores. De izquierda a derecha: foto de producto, retrato, anuncio con texto en español, concept art e ilustración anime.*

> [!IMPORTANT]
> **Los pesos del modelo solo se pueden usar con fines no comerciales.** La [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (sección 2) permite investigación y evaluación. El uso comercial, incluidos anuncios o fotos de producto para un negocio, requiere una licencia aparte de Qwen (`model-business@notice.qwencloud.com`). Esta guía explica cómo ejecutar el modelo, no qué puedes hacer con lo que genera.

## La receta

```bash
sd-cli \
  --diffusion-model qwen_image_2.1-Q4_0.gguf \
  --vae qwen_image_2.1_vae_bf16.safetensors \
  --llm Qwen3VL-8B-Instruct-Q4_K_M.gguf \
  --offload-to-cpu --diffusion-fa \
  --vae-tiling \
  --cfg-scale 1 --sampling-method euler --steps 25 \
  -W 1184 -H 1184 \
  -p "tu prompt" -o salida.png
```

| | Por defecto | Borrador |
|---|---|---|
| Para qué | Imágenes finales y cualquier cosa con texto | Explorar composiciones sin texto |
| Pasos | 25 | 15 |
| Cuadrada | 1184 × 1184 | 1024 × 1024 |
| Vertical 9:16 | 896 × 1568 | 768 × 1344 |
| Horizontal 16:9 | 1568 × 896 | 1344 × 768 |
| Tiempo por imagen | **~4 min 50 s** | **~2 min 45 s** |
| RAM máxima del sistema | 9,4 GB | 9,4 GB |

Las dos recetas usan Q4_0, flash attention y CFG 1. El tiempo es de reloj e incluye toda la ejecución: carga, codificación del texto, muestreo y decodificación del VAE. Las medidas tienen que ser múltiplos de 32.

## Instalación

### 1. Compilar stable-diffusion.cpp con CUDA

Usa el commit [`0a9340c`](https://github.com/leejet/stable-diffusion.cpp/commit/0a9340c5) (2026-09-25) o posterior: arregla las manchas blancas que se describen en Problemas conocidos. Esta guía se verificó con `3f8527a`.

> **Nota de versión.** Las medidas de esta página se tomaron con `c92d73c` (2026-09-22). Desde entonces, sd.cpp corrigió el calendario de ruido de Qwen-Image 2.1 ([#2048](https://github.com/leejet/stable-diffusion.cpp/pull/2048)), así que la misma semilla da ahora una imagen ligeramente distinta. En nuestras comprobaciones, la velocidad y la memoria no cambian; los números de calidad (precisión del texto y prueba a ciegas) aún no se han vuelto a medir.

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
cmake -B build -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
# binarios: build/bin/sd-cli y build/bin/sd-server
```

`86` es la arquitectura de la serie RTX 30. Usa `89` para las RTX 40, o quita la opción para que CMake la detecte.

### 2. Descargar los tres ficheros del modelo (~9,9 GB)

| Pieza | Fichero | Tamaño | SHA-256 |
|---|---|---|---|
| Modelo de difusión | [`qwen_image_2.1-Q4_0.gguf`](https://huggingface.co/leejet/Qwen-Image-2.1-GGUF/blob/main/qwen_image_2.1-Q4_0.gguf) (leejet) | 4,2 GB | `8d992dc9…cf29e9147` |
| Codificador de texto | [`Qwen3VL-8B-Instruct-Q4_K_M.gguf`](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/blob/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf) (Qwen) | 5,0 GB | `67d1659b…0e9e2` |
| VAE | [`qwen_image_2.1_vae_bf16.safetensors`](https://huggingface.co/Comfy-Org/Qwen-Image-2.1/blob/main/vae/qwen_image_2.1_vae_bf16.safetensors) (Comfy-Org) | 0,68 GB | `bb21f747…e4876b7c9` |

Los hashes completos están en [`SHA256SUMS`](SHA256SUMS). El VAE es exclusivo de la 2.1: los de Qwen-Image 1 y Wan 2.2 no sirven.

### 3. Liberar la GPU

La receta usa la tarjeta entera. Cierra cualquier otro programa que ocupe VRAM (un servidor de LLM, Whisper) antes de generar, o la ejecución fallará por falta de memoria.

## Por qué estos ajustes

Todas las medidas de esta sección usan el mismo prompt de anuncio a 768 × 1344, semilla 42, cambiando una sola opción cada vez. Datos en bruto: [`bench/fase1/`](bench/fase1/) y [`bench/fase1b/`](bench/fase1b/).

![El mismo anuncio con cuatro configuraciones y sus tiempos](assets/speed.webp)

| Cambio | Tiempo | s/paso | Resultado |
|---|---|---|---|
| Base (Q4_0, 25 pasos, CFG 1) | 316 s | 10,5 | — |
| **+ `--diffusion-fa`** | **221 s** | **6,8** | **−30 % en total, −35 % de muestreo**, visualmente idéntica |
| + FA, 20 pasos | 193 s | 7,0 | Casi igual que con 25 pasos en este prompt |
| + FA, 15 pasos | 166 s | 7,5 | Sigue muy parecida; vale para borradores |
| Q4_K en vez de Q4_0 | 327 s | 11,0 | Una imagen distinta, no mejor |
| Q5_0 en vez de Q4_0 | 333 s | 11,2 | Igual, y 0,8 GB más de RAM |
| + FA, 1,4 MP (896 × 1568) | 293 s | 9,5 | La única que escribió bien "Envío" |
| 2,4 MP (1152 × 2048) sin FA | — | — | **Sin memoria** (pedía 11,6 GB de VRAM) |
| + FA, 2,4 MP | 502 s | 17,1 | Cabe, pero ver más abajo |

**Flash attention es la mayor mejora.** No viene activada por defecto. Además, es lo que permite que 2,4 MP quepa en 6 GB.

**CFG 1, no 6.** El ejemplo de sd.cpp usa `--cfg-scale 6.0`; la plantilla oficial de ComfyUI usa 1. Con un CFG mayor que 1, cada paso se calcula dos veces, así que CFG 1 va más o menos el doble de rápido. En nuestras pruebas también respetó mejor el estilo pedido (con CFG 6 ignoró "soft pastel colors").

**La resolución importa más que los pasos.** A 1024 × 576 las imágenes salían lavadas; a ~1 MP, no. A ~1 MP, 15, 20 y 25 pasos se veían casi iguales.

## Elegir entre tres candidatas

Generamos 6 prompts × 3 semillas con tres recetas candidatas: 54 imágenes. Datos en bruto en [`bench/fase2/`](bench/fase2/).

| | Borrador | **Por defecto** | Máxima |
|---|---|---|---|
| Ajustes | 15 pasos, ~1 MP | 25 pasos, ~1,4 MP | 25 pasos, ~2,4 MP |
| Preferencia a ciegas (18 comparaciones) | 5 | **8** | 3 (+2 empates) |
| Imágenes con el texto perfecto (9 con texto) | 4 | **9** | 6 |
| Imágenes con la mancha blanca (ya arreglada, ver Problemas conocidos) | 4 / 18 | 1 / 18 | 7 / 18 |
| Tiempo por imagen | 2 min 45 s | 4 min 50 s | 8 min 25 s |

![Texto del botón del anuncio en las tres recetas](assets/text-accuracy.webp)
*El texto pequeño es donde más se diferencian las recetas: solo la receta por defecto escribió "Envío" con tilde en las tres semillas.*

**La receta máxima no compensa.** Tarda casi el doble que la receta por defecto y salió peor en todas las medidas. En este modelo, más píxeles no significan mejor imagen, al menos con Q4_0.

Cuánto fiarse de esto:
- **La precisión del texto (9/9) es el resultado más sólido.** Es objetivo y la diferencia es clara. El texto se revisó letra por letra a ojo, no con OCR.
- **La preferencia a ciegas es una señal, no una prueba.** Las imágenes se mostraron al mismo tamaño y en orden aleatorio, y votó una sola persona. Con 18 comparaciones, 8 frente a 5 puede ser casualidad. Lo que sí muestra es que la receta máxima no gana.

## Para qué sirve

Prompts probados: fotos de producto, retratos, anuncios con texto en español, concept art e ilustración anime. Los cinco salieron utilizables. El texto es el punto fuerte del modelo: titulares y etiquetas salieron bien escritos, tildes incluidas, con la receta por defecto.

**Imágenes técnicas y académicas.** También probamos 12 temas de distintas disciplinas, sin texto en la imagen y con la receta borrador:

![12 temas técnicos con su veredicto](assets/technical.es.webp)

- **Sirven (7):** corazón, célula, flor, puente colgante, prisma, capas de la Tierra y sistema solar. Las estructuras grandes y conocidas salen bien.
- **Ilustrativas (4):** rodilla (la rótula está mal colocada), motor, dodecaedro y circuito. Se reconocen y valen para público general, pero un especialista vería errores.
- **No sirve (1):** cafeína. La molécula no era cafeína en ninguna de las dos semillas.

En resumen: sirve para figuras de libro de texto de estructuras grandes y conocidas. No es fiable cuando los detalles tienen que ser exactos: moléculas concretas, piezas mecánicas precisas o la relación espacial entre partes. **Genera sin etiquetas y ponlas tú:** cuando se le piden, el modelo las escribe bien pero las coloca apuntando a la parte equivocada.

## Problemas conocidos

**Manchas blancas: arregladas en sd.cpp [`0a9340c`](https://github.com/leejet/stable-diffusion.cpp/commit/0a9340c5) ([#2054](https://github.com/leejet/stable-diffusion.cpp/pull/2054)).** Con versiones anteriores, algunas imágenes salían con un rectángulo de blanco puro, de bordes duros y 12-16 px de ancho:

![Una mancha blanca en una ilustración de rodilla](assets/white-patch.webp)

- **Causa:** desbordamiento en FP16 en las convoluciones del VAE de Qwen-Image 2.1. El arreglo reduce la escala de sus entradas y la restaura después.
- **Verificado:** regeneramos 3 imágenes que tenían mancha, con las mismas semillas y ajustes, en `3f8527a`. Las 3 salieron limpias y a la misma velocidad. Basta con actualizar; no hace falta ninguna opción.
- Afectó a 12 de nuestras 54 imágenes de comparación, siempre alineadas a la cuadrícula de 16 px del modelo.
- **Una corrección:** una versión anterior de esta página decía que se había descartado la precisión del VAE en GPU, porque decodificar en CPU daba la misma mancha. Esa conclusión era errónea: el desbordamiento ocurre también en las convoluciones FP16 de ese camino, así que la prueba no aislaba lo que creíamos.

Gracias a leejet por el arreglo y por contestar nuestro aviso en Hugging Face.

**Otras cosas que conviene saber:**
- **Mantén `--vae-tiling`.** Decodificar una imagen de 1 MP de una vez necesita más de 6 GB, y sd.cpp acaba recurriendo a los trozos igualmente. Los trozos de 256 px por defecto funcionan bien. Desde [`19bbbca`](https://github.com/leejet/stable-diffusion.cpp/commit/19bbbca1), `--vae-tile-size` se mide en píxeles de la imagen, no en celdas del latente: si copiaste `--vae-tile-size 24x24` de una versión anterior de esta página, quítalo. **Nunca decodifiques en CPU sin trozos:** a 1024² agotó los 16 GB de RAM y el kernel mató el proceso.
- **La primera imagen tras reiniciar tarda ~1 minuto más** si los pesos están en un disco duro mecánico, porque hay que leer ~10 GB. Después quedan en la caché del sistema y cargan en ~3 s.
- **No midas mientras descargas.** Las descargas al mismo disco expulsan los pesos de la caché; en nuestras pruebas la carga pasó de 3 s a 36 s.
- **La columna de VRAM siempre marca ~5,1-5,2 GB.** sd.cpp ocupa toda la memoria libre y trae el resto desde la RAM. Es lo que usa, no lo que necesita; la VRAM mínima no se ha medido.
- **Los PNG de salida son RGBA** aunque la imagen sea opaca, porque Qwen-Image 2.1 admite transparencia.

## Reproducir las medidas

```bash
scripts/bench.sh <ronda> <nombre> <modelo> <pasos> <prompt_id> [W H] [-- opciones extra de sd-cli]
scripts/fase1.sh      # velocidad y memoria, una variable cada vez
scripts/fase1b.sh     # combinaciones con flash attention
scripts/fase2.sh      # 3 recetas × 6 prompts × 3 semillas (~5 h, reanudable)
scripts/tecnico.sh    # 12 temas técnicos × 2 semillas
```

Los prompts están en [`prompts/`](prompts/). Cada ejecución añade una fila a un `resultados.csv` con el tiempo, la RAM y la VRAM máximas y las opciones exactas; las imágenes y los logs se guardan al lado, pero no se incluyen en este repo. Los votos de la prueba a ciegas y su clave están en [`bench/fase2/ciego/`](bench/fase2/ciego/). Los scripts usan las rutas de la máquina de pruebas; cambia `D` y `SD` al principio de `bench.sh`.

## Máquina de pruebas

| | |
|---|---|
| GPU | NVIDIA RTX 3050 6 GB (5,8 GiB utilizables), driver 595.71.05, CUDA 13.0 |
| CPU / RAM | 6 núcleos, 16 GB |
| Almacenamiento | Pesos en un disco duro de 7200 rpm |
| Sistema | Ubuntu 24.04 |
| sd.cpp | Medidas: `c92d73c` (fase 2) y `c678dfe` (fase 1 y prueba técnica; una imagen comparada entre las dos salió idéntica bit a bit). Arreglo de las manchas verificado en `3f8527a` |

## Licencia

Los scripts de esta carpeta se publican con la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen sus propias licencias: Qwen-Image 2.1 y su VAE, la [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) (no comercial); el codificador de texto Qwen3-VL, Apache 2.0.
