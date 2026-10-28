# quick-bench

Mide una receta de texto en tu propia máquina en pocos minutos y obtén números fáciles de compartir.

`quick-bench.py` arranca `llama-server` con las opciones exactas de una receta y mide tres cosas:

- **Lectura del prompt (prefill):** a qué velocidad lee el modelo el prompt.
- **Generación:** a qué velocidad escribe la respuesta.
- **Generación con el contexto lleno:** lo mismo, con un prompt largo ya en el contexto. La velocidad baja según se llena.

Pasa por `llama-server`, no por `llama-bench`, así que las recetas con modelo borrador (decodificación especulativa) se miden como las usarías de verdad. Cada medida es una petición de chat real: algo de contexto y después una tarea corta de programación en Python, respondida con el muestreo de la receta.

Solo necesita Python 3.8 o posterior y una compilación de llama.cpp. No hay que instalar paquetes.

El script y su salida están en inglés, para que los resultados se puedan compartir con cualquiera.

## Ejecutarlo

Descarga los ficheros GGUF que indica la receta y después:

```bash
# Recetas de GPU (hechas para una RTX 3050 de 6 GB)
python3 quick-bench.py minicpm5-2b gpu --models-dir ~/models
python3 quick-bench.py lfm2.5-2.6b gpu --models-dir ~/models
python3 quick-bench.py lfm2.5-24b-a2b gpu --models-dir ~/models

# Recetas solo con CPU
python3 quick-bench.py lfm2.5-24b-a2b cpu --models-dir ~/models --threads 6
```

| Opción | Qué hace |
|---|---|
| `--models-dir` | Carpeta con los ficheros GGUF, con sus nombres originales. También puedes indicar cada fichero con `--model` y `--draft`. |
| `--server` | Ruta de `llama-server`, si no está en tu `PATH`. |
| `--threads` | Recetas de CPU: número de hilos. Usa uno por núcleo de rendimiento. Por defecto, la mitad de las CPU lógicas. |
| `--cpu-mask` | Recetas de CPU: fija los hilos a núcleos, por ejemplo `0x555` para las CPU 0, 2, 4, 6, 8 y 10 (un bit por núcleo de rendimiento, el primer hilo de cada uno; míralo con `lscpu --extended`). Por defecto, sin fijar. |
| `--sizes` | Longitudes del prompt en tokens. `0` envía la tarea sola. Por defecto: GPU `0,4096,32768`; CPU `0,2048,8192`. |
| `--decode` | Máximo de tokens por respuesta. Por defecto: GPU 1024; CPU 256. Con modelo borrador, las respuestas cortas dan una generación más baja de la real. |
| `--reps` | Corridas por longitud, cada una con una tarea distinta (3 por defecto). Se informa la mediana. |
| `-- <opciones>` | Lo que va después de `--` se pasa a `llama-server`; por ejemplo, `-- -ncmoe 28` para probar un `-ncmoe` menor en una GPU con más VRAM. |

En GPU tarda 2-5 minutos; en CPU, 5-10. La GPU tiene que estar libre: cierra lo que esté usando VRAM.

## Qué obtienes

Una tabla en Markdown, lista para pegar en un *issue* o en una publicación:

```
### minicpm5-2b · gpu recipe

Intel(R) Core(TM) i5-9400 CPU @ 2.90GHz · GPU: NVIDIA GeForce RTX 3050, 6144 MiB · 15.5 GB RAM · llama.cpp commit 4413a19 · 5670 MiB VRAM

| Prompt | Prefill | Decode with that context (median, range) | Draft acceptance | Reference prefill / decode |
|---|---|---|---|---|
| 77 tokens | 1816.1 tok/s | 89.4 tok/s (76.7–95.5) | 48% | 1812.3 / 78,6 tok/s |
...
```

Y un fichero JSON con cada corrida, tu CPU, GPU, RAM, la versión de llama.cpp, el comando exacto y el SHA-256 de los ficheros del modelo (sáltate el hash con `--no-hash`). El log del servidor se guarda al lado.

## Resultados de referencia

quick-bench en las dos máquinas de prueba de las recetas (2026-10-14). Son las cifras con las que el script compara las tuyas. Salen un 5-15 % por debajo de las de `llama-bench` de las recetas, porque cada petición pasa por `llama-server` con plantilla de chat y muestreo, y las corridas van seguidas. Los JSON completos están en [`results/`](results/).

**Sobremesa · RTX 3050 6 GB de VRAM + 16 GB de RAM** (llama.cpp commit `4413a19`, b11580)

| Receta | Tarea sola: prefill / generación | Prompt de 4k | Prompt de 32k | VRAM |
|---|---|---|---|---|
| LFM2.5-24B-A2B | 52 / 29,9 tok/s | 647 / 29,5 tok/s | 753 / 24,1 tok/s | 5588 MiB |
| MiniCPM5-2B | 1812 / 78,6 tok/s | 2303 / 84,9 tok/s | 1279 / 43,6 tok/s | 5670 MiB |
| LFM2.5-2.6B | 1283 / 121,0 tok/s | 2477 / 103,2 tok/s | 2109 / 74,6 tok/s | 4606 MiB |
| LFM3-1.7B ¹ | 1714 / 102,9 tok/s | 4439 / 99,4 tok/s | 3730 / 81,0 tok/s | 2884 MiB |

**Portátil · solo CPU, sin VRAM + 24 GB de RAM** (i7-13620H, `--threads 6 --cpu-mask 0x555`, llama.cpp b11588)

| Receta | Tarea sola: prefill / generación | Prompt de 2k | Prompt de 8k | RAM |
|---|---|---|---|---|
| LFM2.5-24B-A2B | 64 / 25,5 tok/s | 70 / 23,4 tok/s | 64 / 15,9 tok/s | 15,9 GB |
| MiniCPM5-2B | 110 / 25,0 tok/s | 99 / 19,4 tok/s | 66 / 10,8 tok/s | 8,0 GB |
| LFM2.5-2.6B | 130 / 24,9 tok/s | 96 / 21,6 tok/s | 88 / 16,0 tok/s | 4,2 GB |
| LFM3-1.7B ² | 141 / 33,2 tok/s | 153 / 32,8 tok/s | 135 / 27,0 tok/s | 3,5 GB |

El prefill del 24B con un prompt mínimo es bajo en la GPU (52 tok/s) porque los expertos que quedan en la RAM se envían a la GPU en cada lote, por pequeño que sea. El portátil usó la versión anterior del GGUF del 24B (commit `f97fc8a`); el sobremesa, la actual.

¹ LFM3-1.7B se midió el 2026-10-28 con llama.cpp b11946 (`8ca4060b7`). ² En el portátil, el 2026-10-28 con llama.cpp b11940 (`eb7818c0b`) y `--threads 6` sin `--cpu-mask`, como en su receta.

## Cómo leer los números

- **Con modelo borrador, la generación varía entre corridas**, porque la velocidad depende de lo predecible que sea la respuesta. Por eso cada longitud prueba tres tareas distintas e informa la mediana y el rango.
- **Compara con la columna de referencia, no con las cifras principales de la receta.** Las recetas dan `llama-bench`, que mide la generación sin nada alrededor y, en el portátil, con pausas para enfriar.
- **Las opciones de las recetas están ajustadas a sus máquinas de prueba.** Si tienes más VRAM u otra CPU, mira «Adaptarla a tu máquina» en cada receta y prueba tus propias opciones después de `--`.

## Comparte tus resultados

Abre un *issue* en este repositorio con el formulario **Share results** y pega la tabla en Markdown (y el JSON, si quieres). Los resultados de otras GPU y CPU ayudan a ver hasta dónde sirven las recetas.
