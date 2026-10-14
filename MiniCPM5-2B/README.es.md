# MiniCPM5-2B en una GPU de 6 GB y en un portátil sin GPU

Receta medida para ejecutar [MiniCPM5-2B](https://huggingface.co/openbmb/MiniCPM5-2B) en local con [llama.cpp](https://github.com/ggml-org/llama.cpp), con 128k de contexto, en dos máquinas:

| | **Sobremesa** (GPU) | **Portátil** (solo CPU) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB de VRAM** | **Ninguna** (gráfica integrada, sin usar) |
| CPU | Intel i5-9400, 6 núcleos | Intel i7-13620H, 6 núcleos de rendimiento + 4 de eficiencia |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, compilación oficial para CPU |

MiniCPM5-2B es un modelo pequeño para agentes de OpenBMB, con razonamiento opcional. En nuestras pruebas fue **el mejor agente de código de las tres recetas** (LFM2.5-24B-A2B, LFM2.5-2.6B y esta) y el más rápido haciéndolo. En el sobremesa usa el modelo borrador DSpark de OpenBMB para generar más rápido.

Todos los números de esta página se midieron en esas dos máquinas. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, en [`bench/`](bench/).

[English version](README.md)

> [!NOTE]
> **Licencia.** El modelo, los GGUF y el borrador DSpark están bajo Apache 2.0.

## Resumen

| | **Sobremesa** · RTX 3050 6 GB + 16 GB de RAM | **Portátil** · solo CPU + 24 GB de RAM |
|---|---|---|
| Cuantización | Q4_K_M + borrador DSpark | IQ4_NL |
| Generación | **93,8 tok/s** | **28-30 tok/s** |
| Lectura del prompt | **2356 tok/s** (prompt de 4k) · 851 (prompt de 64k) | **~98 tok/s** (prompt de 2048 tokens) |
| Memoria con 128k | 5,6 GB de VRAM | **7,0 GB** de RAM |
| Antes de la receta | ~84 tok/s con 64k de contexto | 26,0 tok/s con Q4_K_M |
| Mini-benchmark de código (11 tareas) | 5,3 / 11 (Q4_K_M) | 6,3 / 11 (IQ4_NL) |
| Agente de código (Pi, 9 corridas) | **7 / 9**, el mejor de las tres recetas | sin medir |

## Receta del sobremesa · RTX 3050 6 GB de VRAM + 16 GB de RAM

```bash
llama-server \
  -m MiniCPM5-2B-Q4_K_M.gguf \
  -md MiniCPM5-2.6B-DSpark.gguf \
  --spec-type draft-dspark --spec-draft-n-max 9 --spec-draft-n-min 0 \
  --spec-draft-p-min 0.5 \
  -ngl 99 -ngld 99 -fa on \
  -np 1 -c 131072 \
  -ub 256 -b 1024 \
  -ctk q8_0 -ctv q8_0 -ctkd q4_0 -ctvd q4_0 \
  --temp 1.0 --top-p 0.95 --min-p 0.0 \
  --reasoning on
```

Usa `--reasoning off` para respuestas directas, sin bloque de razonamiento.

| Opción | Por qué |
|---|---|
| `-md … --spec-type draft-dspark` | Decodificación especulativa: el modelo pequeño DSpark propone tokens y MiniCPM5-2B los comprueba de una pasada. La salida mantiene la calidad del modelo principal. |
| `--spec-draft-p-min 0.5` | La cabeza de confianza de DSpark: el borrador deja de proponer cuando duda. El valor por defecto de llama.cpp (0) la deja apagada. **84,0 → 96,9 tok/s.** Con 0,3 dio 88,0 y con 0,7, 83,8. |
| `-c 131072` con `-ctk q8_0 -ctv q8_0` | 128k de contexto. MiniCPM5-2B tiene 42 capas de atención (LFM2.5 tiene 8), así que su caché KV es grande: sin cuantizarla, 128k no caben en 6 GB. |
| `-ctkd q4_0 -ctvd q4_0` | La caché KV del borrador, en q4_0. OpenBMB solo publica el borrador en F16 (0,65 GB), así que ocupa más de lo normal. Con q8_0 aquí, el servidor no arranca. |
| `-ub 256 -b 1024` | Lotes más pequeños reducen el búfer de cálculo, la última pieza para que quepan 128k. La lectura del prompt sigue por encima de 2000 tok/s con prompts cortos. |
| `--temp 1.0 --top-p 0.95 --min-p 0.0` | El muestreo que recomienda OpenBMB. El `min-p` importa: el valor por defecto de llama.cpp (0,05) provoca bucles de repetición. |

Ocupa 5625 MiB de los 6 GB, así que nada más puede compartir la GPU.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-speed-dark.es.webp">
  <img alt="Velocidad de generación en la RTX 3050 con y sin el borrador DSpark" src="assets/gpu-speed.es.webp">
</picture>

**Su punto débil son los prompts largos.** La lectura del prompt cae de 2356 tok/s con un prompt de 4k a 851 con uno de 64k (−64 %), porque cada una de sus 42 capas de atención tiene que leer todo el contexto. LFM2.5-2.6B, con solo 8 capas de atención, pierde un 28 %.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/prefill-context-dark.es.webp">
  <img alt="Lectura del prompt según su longitud para MiniCPM5-2B y LFM2.5-2.6B" src="assets/prefill-context.es.webp">
</picture>

`--spec-type ngram-mod` (reutilizar texto repetido como borrador) solo ayudó cuando la respuesta repetía el prompt, así que no está en la receta.

## Receta del portátil · solo CPU, sin VRAM + 24 GB de RAM

```bash
llama-server \
  -m MiniCPM5-2B-IQ4_NL.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 1.0 --top-p 0.95 --min-p 0.0 \
  --reasoning on
```

| Opción | Por qué |
|---|---|
| IQ4_NL | +7 % de generación frente a Q4_K_M con casi la misma fidelidad (ver la gráfica). Q4_0 es aún más rápida (+12 %), pero pierde más del doble: descartada. |
| `-t 6` | Un hilo por núcleo de rendimiento. |
| `-C 0x555 --cpu-strict 1` | Fija cada hilo a su propio núcleo de rendimiento. Con IQ4_NL no dio una diferencia medible (28,2 frente a 28,2 y 29,7 frente a 29,2 tok/s); se mantiene por coherencia con las otras recetas y es opcional. |
| `-lm none` | Carga el modelo en la RAM en vez de mapear el fichero: **7,0 GB en lugar de 7,8 GB** con 128k. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-quants-dark.es.webp">
  <img alt="Velocidad de generación y fidelidad de Q4_K_M, IQ4_NL y Q4_0 en el portátil" src="assets/cpu-quants.es.webp">
</picture>

La fidelidad se mide con la divergencia KL frente al fichero Q8_0 en wikitext-2: cuánto se alejan las predicciones de cada cuantización de la versión casi sin pérdida. Menos es más fiel.

| Cuantización | Bits por peso | Tamaño | KL frente a Q8_0 | Mismo token principal que Q8_0 |
|---|---|---|---|---|
| Q4_K_M | 5,14 | 1,62 GB | 0,043 | 89,4 % |
| **IQ4_NL** | 5,10 | 1,61 GB | **0,047** | 88,7 % |
| Q4_0 | 4,82 | 1,52 GB | 0,110 | 83,5 % |

La lectura del prompt es igual en las tres (~96-98 tok/s con un prompt de 2048 tokens). La velocidad del portátil también depende del calor: con la CPU caliente pierde 2-3 tok/s en un par de minutos.

## Calidad

El mini-benchmark de código son 11 funciones de Python corregidas con tests de pytest ocultos, 3 pasadas por configuración. La prueba de agente es [Pi](https://github.com/badlogic/pi-mono) trabajando en un proyecto pequeño de Python (un registro de gastos de 200 líneas) con 3 tareas: añadir una función, arreglar un fallo descrito por un usuario y refactorizar sin cambiar el comportamiento. 3 pasadas por tarea, con las recetas del sobremesa a 128k. Pi corrió en un entorno aislado (bubblewrap) que solo le dejaba escribir en su copia del proyecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.es.webp">
  <img alt="Agente de código con Pi: tareas aprobadas sobre 9" src="assets/agent.es.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.es.webp">
  <img alt="Mini-benchmark de código: media de tareas aprobadas sobre 11" src="assets/coding.es.webp">
</picture>

- **Agente: 7 / 9, el mejor de los tres, con 138 s por tarea de media** (LFM2.5-24B-A2B: 6 / 9 en 293 s). Arregló el fallo en las 3 pasadas e hizo bien las 3 refactorizaciones, la tarea que LFM2.5-24B-A2B falló siempre. Sus dos fallos fueron el mismo detalle: una fecha inválida no terminaba el programa con código 2, como pedía la tarea.
- **Mini-benchmark: 6,3 / 11 con IQ4_NL y 5,3 con Q4_K_M**, un empate dentro del ruido: la cuantización del portátil no pierde calidad. Las dos se sirvieron en la GPU del sobremesa; la nota depende del fichero, no de la máquina. Con la temperatura recomendada (1,0), la nota oscila mucho entre pasadas, de 3 a 8.

## Subagentes

Un plugin de subagentes funciona con `-np 1`. La sesión principal y el subagente se turnan en el mismo servidor, y el `--cache-ram` de llama.cpp (activo por defecto) guarda en la RAM la conversación que espera, así que al retomarla no se vuelve a procesar. **No pongas `--cache-ram 0`.** Con `-np 2`, los 128k se repartirían entre dos sesiones. Medido con LFM2.5-24B-A2B en las dos máquinas: unos 2-3 s por cambio, frente a 40 s (sobremesa) y 2 minutos (portátil) sin la caché. Detalles en la [receta de LFM2.5-24B-A2B](../LFM2.5-24B-A2B/README.es.md#subagentes).

## Adaptarla a tu máquina

Las cifras de arriba son de estas dos máquinas. Lo que se puede trasladar:

- **La elección de cuantización, los ajustes del borrador (`p-min 0.5`) y el muestreo** no dependen del equipo.
- **Más VRAM (sobremesa):** con 8 GB deberías poder quitar `-ub 256 -b 1024` y usar `q8_0` también en la caché del borrador, y con 12 GB o más dejar la caché KV sin cuantizar (sin medir). Con menos de 6 GB, baja `-c`.
- **Otra CPU (portátil):** usa un hilo por núcleo de rendimiento. `-C` no cambió nada aquí; omítelo si tu CPU no tiene núcleos de eficiencia.
- **`-lm none`** ahorra casi 1 GB con cualquier CPU.
- **Un modelo borrador en CPU** no se probó con este modelo; la receta del portátil no lo usa.

## Ficheros

| Fichero | Lo usa | Tamaño | SHA-256 |
|---|---|---|---|
| [`MiniCPM5-2B-Q4_K_M.gguf`](https://huggingface.co/bartowski/MiniCPM5-2B-GGUF/blob/31fee03/MiniCPM5-2B-Q4_K_M.gguf) (bartowski, commit `31fee03`) | Sobremesa | 1,62 GB · 5,14 bits por peso | `967d467b…db755f0de` |
| [`MiniCPM5-2.6B-DSpark.gguf`](https://huggingface.co/openbmb/MiniCPM5-2B-DSpark-GGUF/blob/a261d2b/MiniCPM5-2.6B-DSpark.gguf) (OpenBMB, commit `a261d2b`) | Sobremesa | 0,65 GB · F16 | `57df0864…a3f0c26` |
| [`MiniCPM5-2B-IQ4_NL.gguf`](https://huggingface.co/bartowski/MiniCPM5-2B-GGUF/blob/31fee03/MiniCPM5-2B-IQ4_NL.gguf) (bartowski, commit `31fee03`) | Portátil | 1,61 GB · 5,10 bits por peso | `a2bd3ddc…9b9fce41` |

Hashes completos en [`SHA256SUMS`](SHA256SUMS). El borrador se llama `2.6B` en el repositorio de OpenBMB, pero es el borrador de MiniCPM5-2B.

## Reproducir las medidas

**Comprobación rápida en tu máquina:** [`../tools/quick-bench.py`](../tools/README.es.md) ejecuta esta receta y mide la lectura del prompt, la generación y la generación con el contexto lleno en pocos minutos:

```bash
python3 ../tools/quick-bench.py minicpm5-2b gpu --models-dir ~/models   # o: cpu --threads <núcleos de rendimiento>
```

Los scripts están en [`scripts/`](scripts/), con el nombre de la ronda a la que pertenecen, y los datos en bruto de cada ronda, en [`bench/`](bench/) con el mismo nombre. Las rondas del sobremesa empiezan por `2.3` y las del portátil, por `2.4`. Los scripts del sobremesa corren dentro de la imagen Docker de [llama-swap](https://github.com/mostlygeek/llama-swap) (`unified-cuda13`, llama.cpp b11580); los del portátil usan la compilación oficial para CPU b11588. La prueba de fidelidad (2.4c) usó llama.cpp b11028 con CUDA en el sobremesa. Los scripts suponen las rutas de los modelos de las máquinas de prueba: edita las variables del principio.

Los resultados del mini-benchmark (un JSON por pasada, con el código generado) están en [`bench/3.2-minibench/`](bench/3.2-minibench/) y los de la prueba de agente, en [`bench/3.3-pi/`](bench/3.3-pi/).

## Licencia

Los scripts de esta carpeta se publican bajo la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen su propia licencia, Apache 2.0.
