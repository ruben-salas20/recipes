# LFM3-1.7B en una GPU de 6 GB y en un portátil sin GPU

Receta medida para ejecutar [LFM3-1.7B](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF) en local con [llama.cpp](https://github.com/ggml-org/llama.cpp), con 128k de contexto, en dos máquinas:

| | **Sobremesa** (GPU) | **Portátil** (solo CPU) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB de VRAM** | **Ninguna** (gráfica integrada, sin usar) |
| CPU | Intel i5-9400, 6 núcleos | Intel i7-13620H, 6 núcleos de rendimiento + 4 de eficiencia |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11940, CUDA | b11940, compilación oficial para CPU |

LFM3-1.7B es un modelo pequeño e híbrido de Liquid AI: 13 capas de convolución y 11 de atención, 6 de ellas con atención completa. Su caché KV (la memoria donde guarda el contexto) ocupa solo 12 KiB por token, así que **su contexto completo de 262 144 tokens cabe en una GPU de 6 GB**. Siempre razona antes de responder, y **necesita espacio para hacerlo**: con un límite de 8192 tokens por respuesta sacó un 70 % en nuestra prueba de extraer a JSON, y con 32 768, un 95 % (ver [Déjale espacio para razonar](#déjale-espacio-para-razonar)).

Todos los números de esta página se midieron en esas dos máquinas. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, en [`bench/`](bench/).

[English version](README.md)

> [!NOTE]
> **Licencia.** Los pesos están bajo la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/main/LICENSE): uso libre para investigación y para uso comercial en empresas con menos de 10 millones de dólares de ingresos anuales.

## Resumen

| | **Sobremesa** · RTX 3050 6 GB + 16 GB de RAM | **Portátil** · solo CPU + 24 GB de RAM |
|---|---|---|
| Cuantización | Q4_K_M | QAD-Q4_0 |
| Generación | **120 tok/s** · 92 con 32k | **37 tok/s** · 29 con 8k · 15 con 32k |
| Lectura del prompt | **~4450 tok/s** (prompt de 4k) | **153 tok/s** (prompt de 2048 tokens) · 138 (prompt de 8k) |
| Memoria con 128k | **2884 MiB** de VRAM (262k caben en 4547 MiB) | **2,6 GB** de RAM (3,5 GB tras un prompt de 8k) |
| Extraer a JSON (24 ítems) | **95 %** de campos acertados, JSON válido en 71 de 72 respuestas | el mismo modelo, ver [Calidad](#calidad) |
| Mini-benchmark de código (11 tareas) | 6,0 / 11 (5,0 con 8192 tokens) | 4,7 / 11 con 8192 tokens (Q4_K_M: 5,0) |
| Agente de código (Pi, 9 corridas) | 5 / 9 | sin medir |

## Déjale espacio para razonar

LFM3-1.7B escribe un bloque de razonamiento antes de cada respuesta, y en algunas tareas el bloque es largo: hasta 30 000 tokens para sacar un JSON de una factura larga. **Si el cliente limita la respuesta a 8192 tokens, el modelo se queda a menudo sin espacio mientras razona y no devuelve nada.** Muchos clientes y benchmarks usan 8192 o menos por defecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/token-limit-dark.es.webp">
  <img alt="Nota al extraer a JSON con un límite de 8192 y de 32768 tokens por respuesta" src="assets/token-limit.es.webp">
</picture>

| | `max_tokens` 8192 | `max_tokens` 32768 |
|---|---|---|
| Extraer a JSON (3 pasadas) | 67-72 % | **91,5-96,7 %** |
| Ítems cortados sin respuesta | 6-7 de 24 por pasada | 1 de 72 |
| Ítems en español / en inglés | 56 / 85 % | 93 / 96 % |
| Mini-benchmark de código (3 pasadas) | 5,0 / 11 | **6,0 / 11** |
| Tests de código aprobados | 46 de 106 de media | 88 de 106 |

Los ítems en español no eran más difíciles de acertar: solo hacían razonar más al modelo. Cuando terminaba de razonar, acertaba cerca del 96 % de los campos en los dos idiomas. **Pon `max_tokens` a 32768 en tu cliente.** El precio es tiempo: las respuestas de JSON más largas tardaron unos 5 minutos en el sobremesa, y en el portátil tardarían unos 17.

## Receta del sobremesa · RTX 3050 6 GB de VRAM + 16 GB de RAM

```bash
llama-server \
  -m LFM3-1.7B-Q4_K_M.gguf \
  -ngl 99 -np 1 -c 131072 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Opción | Por qué |
|---|---|
| Q4_K_M | Más fiel al original que QAD-Q4_0 (divergencia KL frente a BF16 de 0,117 frente a 0,186) a cambio de un 6 % menos de generación (120,5 frente a 128,3 tok/s). Las dos empataron en el mini-benchmark (5,0 y 4,7 / 11 con 8192 tokens). Q8_0 casi no pierde nada (KL 0,003), pero va un 35 % más lenta. |
| Caché KV en f16 (por defecto) | **No la cuantices.** Con `q8_0`, la generación cae un 36-45 % con contexto largo (35,1 frente a 54,6 tok/s con 128k), y la memoria que ahorra no hace falta. |
| `-c 131072` | 128k es lo que usamos en la prueba de agente. Los 262 144 completos **también caben: 4547 MiB de VRAM**. |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.1` | El muestreo que recomienda Liquid AI. Con `--repeat-penalty 1.0` sacó lo mismo en el mini-benchmark (6,0 / 11). |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-context-dark.es.webp">
  <img alt="Velocidad de generación en la RTX 3050 con el contexto vacío, con 32k, 128k y 240k" src="assets/gpu-context.es.webp">
</picture>

Todavía no hay borrador DSpark para LFM3 (a 2026-10-28), así que esta receta no usa generación especulativa.

## Receta del portátil · solo CPU, sin VRAM + 24 GB de RAM

```bash
llama-server \
  -m LFM3-1.7B-QAD-Q4_0.gguf \
  -lm none \
  -t 6 -tb 16 -fa off \
  -np 1 -c 131072 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Opción | Por qué |
|---|---|
| QAD-Q4_0 | La Q4_0 de Liquid AI entrenada para cuantizarse: la más rápida en esta CPU (35,4 frente a 33,9 tok/s de Q4_K_M), y empató con Q4_K_M en el mini-benchmark. Se aparta más del original (KL 0,186 frente a 0,117). |
| `-lm none` | Carga el modelo en la RAM en vez de mapear el fichero: **2,6 GB en lugar de 3,4 GB** con 128k, a la misma velocidad (37,5 frente a 37,7 tok/s). |
| `-t 6` | La generación va más rápida con un hilo por núcleo de rendimiento: 38-41 tok/s con 6 hilos y 35,5 con 16. |
| `-tb 16` | La lectura del prompt, en cambio, sí aprovecha los 16 hilos: **+17 %** (de 118 a 138 tok/s con un prompt de 7850 tokens; el primer token llega en 56,9 s en vez de 66,5). La generación no cambia. |
| `-fa off` | Sin FlashAttention, la generación con contexto va mucho más rápida en esta CPU: **+19 % con 8k y +77 % con 32k** (15,2 frente a 8,5 tok/s). El precio es memoria: el búfer de cálculo sube a 4,3 GiB con 128k (0,2 GiB con FlashAttention). La lectura del prompt va un 6-15 % más lenta. |
| `-c 131072` | Con `-fa off`, los 262 144 completos necesitan un búfer de cálculo de 8,5 GiB más 3 GiB de caché KV. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-flash-attn-dark.es.webp">
  <img alt="Velocidad de generación en el portátil con FlashAttention y sin ella, con el contexto vacío, con 8k y con 32k" src="assets/cpu-flash-attn.es.webp">
</picture>

Otras cosas que medimos en el portátil y no ayudaron: un microlote mayor (`-ub` 1024 o 2048 da lo mismo o un 6-7 % menos que el 512 por defecto) y la generación especulativa con n-gramas (`--spec-type ngram-mod` o `ngram-simple`, +3-4 % al extraer a JSON, porque casi toda la respuesta es razonamiento nuevo).

## Calidad

Todas las pruebas de calidad corrieron en la GPU del sobremesa con Q4_K_M, 3 pasadas cada una; la nota depende del fichero, no de la máquina. La divergencia KL se midió en los tres ficheros candidatos:

| Cuantización | Bits por peso | Tamaño | KL frente a BF16 | Mismo token más probable que BF16 | Perplejidad frente a BF16 |
|---|---|---|---|---|---|
| Q8_0 | 8,51 | 1,85 GB | 0,003 | 97,1 % | +0,0 % |
| **Q4_K_M** (sobremesa) | ~5,05 | 1,10 GB | **0,117** | 83,2 % | +2,5 % |
| **QAD-Q4_0** (portátil) | 4,82 | 1,05 GB | 0,186 | 79,4 % | +18 % |

**Código.** El mini-benchmark son 11 funciones de Python que corrigen tests de pytest ocultos. La prueba de agente es [Pi](https://github.com/badlogic/pi-mono) trabajando en un proyecto pequeño de Python (un gestor de gastos de 200 líneas) con 3 tareas: añadir una función, arreglar un fallo que cuenta un usuario y refactorizar sin cambiar el comportamiento. Pi corrió aislado (bubblewrap): solo podía escribir en su copia del proyecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.es.webp">
  <img alt="Mini-benchmark de código: media de tareas aprobadas de 11, con el límite de tokens de cada corrida" src="assets/coding.es.webp">
</picture>

- **Mini-benchmark: 6,0 / 11 con 32 768 tokens.** Con el mismo límite de 8192 tokens, queda por debajo de las otras recetas pequeñas: 5,0 frente a 6,3 de MiniCPM5-2B y LFM2.5-2.6B.
- **Escribe mal algunos nombres.** En una tarea llama a menudo `compressir_repeticiones` a la función `comprimir_repeticiones`, y fallan todos los tests. Pasa también con el fichero BF16 sin cuantizar (1 de 10 corridas; 3 de 10 con Q4_K_M) y sin penalización por repetición: viene del modelo.
- **Agente: 5 / 9** (función 0/3, fallo 3/3, refactorizar 2/3), con Pi 1.4.0 y 16 384 tokens por turno. En dos corridas de la función gastó el turno razonando y no cambió nada. Con 32 768 por turno sacó 4 / 9: la función siguió fallando, y una vez borró dos funciones y rompió el proyecto. Las otras recetas se probaron con Pi 1.0.3, así que las cifras no se comparan directamente (MiniCPM5-2B 7 / 9, LFM2.5-2.6B 1 / 9). La propia Liquid AI no lo recomienda para programar con agentes.

**Tareas que no son de código.** Tres pruebas que montamos para esta receta, con textos en español y en inglés. Resumir y traducir corrieron con un límite de 8192 tokens (se cortaron de 0 a 3 respuestas de 18 o de 120).

| Prueba | Resultado |
|---|---|
| **Extraer a JSON** · 24 textos sintéticos (facturas, correos, contratos, chats) y un esquema JSON | **95 %** de campos acertados con 32k tokens (91,5-96,7 %), JSON válido en 71 de 72 respuestas |
| **Resumir** · 18 textos sintéticos de 320 a 960 palabras, corregidos con comprobaciones automáticas y con un modelo juez (Claude Sonnet) | Recoge unas 3/4 partes de los hechos (juez: 0,75-0,78). Pero en 10-13 de los 18 resúmenes **cambia una relación entre hechos verdaderos**: algo anunciado pasa a estar hecho, o una causa se atribuye a otra cosa. A veces resume en inglés un texto en español. Revisa sus resúmenes antes de fiarte de ellos. |
| **Traducir** · 120 frases de [WMT24++](https://huggingface.co/datasets/google/wmt24pp), chrF (de 0 a 100, parecido con una traducción humana) | Español ↔ inglés **~59**, estable entre pasadas. Francés, alemán y portugués, 53-63. Chino ~30 y japonés 23-27. |

## Adaptarla a tu máquina

Los números de arriba son de estas dos máquinas. Lo que se puede llevar a otra:

- **`max_tokens` 32768 y el muestreo** no dependen del hardware.
- **Menos VRAM (sobremesa):** con 128k, la receta ocupa 2884 MiB de VRAM, así que debería caber en una GPU de 4 GB (sin medir). En cualquier GPU de NVIDIA, deja la caché KV en f16.
- **Otra CPU (portátil):** usa un hilo por núcleo de rendimiento en `-t` y todos los hilos en `-tb`. Si `-fa off` gana depende de la CPU: compara las dos opciones con la longitud de contexto que uses. **`-lm none`** ahorra unos 0,8 GB con cualquier CPU.
- **Versión.** Medimos con llama.cpp b11940. La tarjeta de Liquid AI dice ahora b11960 o posterior; el único cambio de LFM3 entre las dos es la entrada de vídeo para los modelos multimodales, que esta receta de texto no usa.

## Ficheros

| Fichero | Para | Tamaño | SHA-256 |
|---|---|---|---|
| [`LFM3-1.7B-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/b3f2ae5/LFM3-1.7B-Q4_K_M.gguf) (Liquid AI, commit `b3f2ae5`) | Sobremesa | 1,10 GB · ~5,05 bits por peso | `3793e1e6…b05c93c4` |
| [`LFM3-1.7B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/b3f2ae5/LFM3-1.7B-QAD-Q4_0.gguf) (Liquid AI, commit `b3f2ae5`) | Portátil | 1,05 GB · 4,82 bits por peso | `43a7d09a…e572a7452` |

Los hashes completos están en [`SHA256SUMS`](SHA256SUMS). Los mismos ficheros, con los mismos hashes, siguen en el commit actual del repositorio.

## Reproducir las medidas

**Prueba rápida en tu máquina:** [`../tools/quick-bench.py`](../tools/README.es.md) ejecuta esta receta y mide la lectura del prompt, la generación y la generación con el contexto lleno en pocos minutos:

```bash
python3 ../tools/quick-bench.py lfm3-1.7b gpu --models-dir ~/models   # o: cpu --threads <núcleos de rendimiento>
```

Los scripts están en [`scripts/`](scripts/), con el nombre de la ronda a la que pertenecen, y los datos en bruto de cada ronda, en [`bench/`](bench/) con el mismo nombre. Las rondas del sobremesa son `2.0`, `2.1` y `3.x`; las del portátil, `2.0` y de `2.2a` a `2.2f`. El sobremesa usó llama.cpp b11940 compilado con CUDA 13; el portátil, la compilación oficial para CPU b11940. Los scripts suponen las rutas de los modelos de las máquinas de prueba: cambia las variables del principio.

Los resultados del mini-benchmark (un JSON por pasada, con el código generado) están en [`bench/3.2-minibench/`](bench/3.2-minibench/) y [`bench/3.2b-minibench-32k/`](bench/3.2b-minibench-32k/); la prueba de agente, en [`bench/3.3-pi/`](bench/3.3-pi/) (16 384 tokens por turno) y [`bench/3.3-pi-32k/`](bench/3.3-pi-32k/); y las de JSON, resumir y traducir, en [`bench/3.4-pruebas-generales/`](bench/3.4-pruebas-generales/) y [`bench/3.4b-json-32k/`](bench/3.4b-json-32k/).

## Licencia

Los scripts de esta carpeta se publican con la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen su propia licencia, la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/blob/main/LICENSE).
