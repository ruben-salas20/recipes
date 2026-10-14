# LFM2.5-2.6B en una GPU de 6 GB y en un portátil sin GPU

Receta medida para ejecutar [LFM2.5-2.6B](https://huggingface.co/LiquidAI/LFM2.5-2.6B) en local con [llama.cpp](https://github.com/ggml-org/llama.cpp), con 128k de contexto, en dos máquinas:

| | **Sobremesa** (GPU) | **Portátil** (solo CPU) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB de VRAM** | **Ninguna** (gráfica integrada, sin usar) |
| CPU | Intel i5-9400, 6 núcleos | Intel i7-13620H, 6 núcleos de rendimiento + 4 de eficiencia |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, compilación oficial para CPU |

LFM2.5-2.6B es un modelo pequeño e híbrido de Liquid AI (casi todo capas de convolución, 8 capas de atención). Es **el más rápido y ligero de las tres recetas**: 128 tok/s en el sobremesa y 3,7 GB de RAM con 128k en el portátil. Pero en nuestra prueba de agente **no sirvió como agente de código** (ver [Calidad](#calidad)).

Todos los números de esta página se midieron en esas dos máquinas. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, en [`bench/`](bench/).

[English version](README.md)

> [!NOTE]
> **Licencia.** Los pesos están bajo la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/main/LICENSE): uso libre para investigación y para uso comercial en empresas con menos de 10 millones de dólares de ingresos anuales.

## Resumen

| | **Sobremesa** · RTX 3050 6 GB + 16 GB de RAM | **Portátil** · solo CPU + 24 GB de RAM |
|---|---|---|
| Cuantización | Q4_K_M + borrador DSpark | QAD-Q4_0 |
| Generación | **128 tok/s** | **29,2 tok/s** |
| Lectura del prompt | **2477 tok/s** (prompt de 4k) · 1795 (prompt de 64k) | **98 tok/s** (prompt de 2048 tokens) |
| Memoria con 128k | 4,5 GB de VRAM | **3,7 GB** de RAM |
| Antes de la receta | 96k de contexto en 5,0 GB de VRAM | 26,8 tok/s con Q4_K_M |
| Mini-benchmark de código (11 tareas) | 5,7 / 11 (Q4_K_M) | 6,3 / 11 (QAD-Q4_0) |
| Agente de código (Pi, 9 corridas) | **1 / 9** | sin medir |

## Receta del sobremesa · RTX 3050 6 GB de VRAM + 16 GB de RAM

```bash
llama-server \
  -m LFM2.5-2.6B-Q4_K_M.gguf \
  -md LFM2.5-2.6B-DSpark-Q4_K_M.gguf \
  --spec-type draft-dspark --spec-draft-n-max 9 --spec-draft-n-min 0 \
  -ngl 99 -ngld 99 -fa on \
  -np 1 -c 131072 \
  -ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Opción | Por qué |
|---|---|
| `-md … --spec-type draft-dspark` | Decodificación especulativa con el borrador DSpark de Liquid AI: propone tokens y LFM2.5-2.6B los comprueba de una pasada. **73 → 128 tok/s (+75 %).** La salida mantiene la calidad del modelo principal. |
| `--spec-draft-n-max 9` | Hasta 9 tokens propuestos por paso. 9 ganó a 5 y a 7 en dos rondas distintas (con temperatura 0,1 y 0). Encender la cabeza de confianza (`--spec-draft-p-min` 0,3 o 0,5) lo hizo más lento, así que se queda en el valor por defecto (0). |
| `-c 131072` con `-ctk q8_0 -ctv q8_0 -ctkd q8_0 -ctvd q8_0` | 128k con la caché KV en q8_0, para el modelo y el borrador. Ocupa **menos** VRAM que los 96k anteriores sin cuantizar (4561 frente a 4999 MiB) a la misma velocidad. 128k sin cuantizar no caben. |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.1` | El muestreo que recomienda Liquid AI. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-speed-dark.es.webp">
  <img alt="Velocidad de generación en la RTX 3050 con y sin el borrador DSpark" src="assets/gpu-speed.es.webp">
</picture>

**Lleva bien los prompts largos.** La lectura del prompt pasa de 2477 tok/s con un prompt de 4k a 1795 con uno de 64k (−28 %). Con solo 8 capas de atención, el contexto largo le cuesta mucho menos que a MiniCPM5-2B (−64 %).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/prefill-context-dark.es.webp">
  <img alt="Lectura del prompt según su longitud para LFM2.5-2.6B y MiniCPM5-2B" src="assets/prefill-context.es.webp">
</picture>

**Siempre razona primero.** Su plantilla de chat abre siempre un bloque de razonamiento y `--reasoning off` no le afecta, porque la plantilla no tiene ese interruptor. Para respuestas directas hace falta una plantilla modificada que cierre el bloque en el acto.

## Receta del portátil · solo CPU, sin VRAM + 24 GB de RAM

```bash
llama-server \
  -m LFM2.5-2.6B-QAD-Q4_0.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 0.1 --top-k 50 --repeat-penalty 1.1
```

| Opción | Por qué |
|---|---|
| QAD-Q4_0 | El Q4_0 entrenado para la cuantización de Liquid AI: **+9 % de generación frente a Q4_K_M** (29,2 frente a 26,8 tok/s) y algo más fiel a Q8_0 (ver abajo). |
| reempaquetado (activo por defecto) | llama.cpp reordena los pesos Q4_0 al cargarlos para las instrucciones vectoriales de la CPU. **No uses `--repack 0`** (ni `--no-repack`): la lectura del prompt cae un 43 % (98 → 56 tok/s). |
| `-t 6 -C 0x555 --cpu-strict 1` | Un hilo por núcleo de rendimiento, cada uno fijo en su núcleo. Medido con Q4_K_M, la velocidad se estanca entre 4 y 6 hilos (25,1 y 26,7 tok/s) y baja con 8, cuando entran núcleos de eficiencia (24,5). |
| `-lm none` | Carga el modelo en la RAM en vez de mapear el fichero: **3,7 GB en lugar de 4,9 GB** con 128k. |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-quants-dark.es.webp">
  <img alt="Velocidad de generación y fidelidad de Q4_K_M y QAD-Q4_0 en el portátil" src="assets/cpu-quants.es.webp">
</picture>

La fidelidad se mide con la divergencia KL frente al fichero Q8_0 en wikitext-2: cuánto se alejan las predicciones de cada cuantización de la versión casi sin pérdida. Menos es más fiel.

| Cuantización | Bits por peso | Tamaño | KL frente a Q8_0 | Mismo token principal que Q8_0 |
|---|---|---|---|---|
| Q4_K_M | 4,97 | 1,67 GB | 0,157 | 81,4 % |
| **QAD-Q4_0** | 4,73 | 1,59 GB | **0,141** | 82,2 % |

Una rareza: en wikitext-2, el fichero Q8_0 tiene una perplejidad alta (50-54) y los de 4 bits, una más baja (45-47). Lo comprobamos con dos compilaciones y dos máquinas (CPU y CUDA): es real, no un error de la prueba. Los dos ficheros de 4 bits se alejan de Q8_0 de forma parecida, que es lo que muestra la KL.

En el portátil no se usa modelo borrador: en una prueba temprana en esta CPU, un borrador DSpark hizo más lento un modelo LFM2.5 (12,9 frente a 31,9 tok/s). La velocidad del portátil también depende del calor: con la CPU caliente pierde unos 2 tok/s en un par de minutos.

## Calidad

El mini-benchmark de código son 11 funciones de Python corregidas con tests de pytest ocultos, 3 pasadas por configuración. La prueba de agente es [Pi](https://github.com/badlogic/pi-mono) trabajando en un proyecto pequeño de Python (un registro de gastos de 200 líneas) con 3 tareas: añadir una función, arreglar un fallo descrito por un usuario y refactorizar sin cambiar el comportamiento. 3 pasadas por tarea, con las recetas del sobremesa a 128k. Pi corrió en un entorno aislado (bubblewrap) que solo le dejaba escribir en su copia del proyecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.es.webp">
  <img alt="Mini-benchmark de código: media de tareas aprobadas sobre 11" src="assets/coding.es.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.es.webp">
  <img alt="Agente de código con Pi: tareas aprobadas sobre 9" src="assets/agent.es.webp">
</picture>

- **Mini-benchmark: 6,3 / 11 con QAD-Q4_0 y 5,7 con Q4_K_M**, un empate dentro del ruido: la cuantización del portátil no pierde calidad. Las dos se sirvieron en la GPU del sobremesa; la nota depende del fichero, no de la máquina.
- **Agente: 1 / 9. No sirve como agente de código.** Daba tareas por hechas sin estarlo: en dos pasadas del arreglo no cambió nada, y en otras dos rompió tests que antes pasaban y aun así terminó. En una prueba anterior sin aislar también escribió ficheros fuera de la carpeta del proyecto. Si lo pruebas como agente, aíslalo.
- Para agentes de código en el mismo equipo, [MiniCPM5-2B](../MiniCPM5-2B/README.es.md) sacó 7 / 9 con un tamaño parecido.

## Subagentes

Un plugin de subagentes funciona con `-np 1`. La sesión principal y el subagente se turnan en el mismo servidor, y el `--cache-ram` de llama.cpp (activo por defecto) guarda en la RAM la conversación que espera, así que al retomarla no se vuelve a procesar. **No pongas `--cache-ram 0`.** Medido con LFM2.5-24B-A2B en las dos máquinas: unos 2-3 s por cambio, frente a 40 s (sobremesa) y 2 minutos (portátil) sin la caché. Detalles en la [receta de LFM2.5-24B-A2B](../LFM2.5-24B-A2B/README.es.md#subagentes).

## Adaptarla a tu máquina

Las cifras de arriba son de estas dos máquinas. Lo que se puede trasladar:

- **La elección de cuantización, los ajustes del borrador (`n-max 9`) y el muestreo** no dependen del equipo.
- **Más VRAM (sobremesa):** con 8 GB o más, 128k deberían caber sin cuantizar la caché KV (sin medir). El borrador es pequeño (0,20 GB): mantenlo.
- **Otra CPU (portátil):** QAD-Q4_0 con reempaquetado necesita una CPU con AVX2 (cualquier x86 reciente). Usa un hilo por núcleo de rendimiento; para `-C`, pon un bit por núcleo de rendimiento, tomando solo el primer hilo de cada uno (míralo con `lscpu --extended`).
- **`-lm none`** ahorra alrededor de 1 GB con cualquier CPU.

## Ficheros

| Fichero | Lo usa | Tamaño | SHA-256 |
|---|---|---|---|
| [`LFM2.5-2.6B-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/e7caca5/LFM2.5-2.6B-Q4_K_M.gguf) (Liquid AI, commit `e7caca5`) | Sobremesa | 1,67 GB · 4,97 bits por peso | `02a8b7e1…c697f52ed` |
| [`LFM2.5-2.6B-DSpark-Q4_K_M.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-DSpark-GGUF/blob/7bc2896/LFM2.5-2.6B-DSpark-Q4_K_M.gguf) (Liquid AI, commit `7bc2896`) | Sobremesa | 0,20 GB | `63786b76…e34b79a3cd` |
| [`LFM2.5-2.6B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/e7caca5/LFM2.5-2.6B-QAD-Q4_0.gguf) (Liquid AI, commit `e7caca5`) | Portátil | 1,59 GB · 4,73 bits por peso | `a247afd6…d8d40b03` |

Hashes completos en [`SHA256SUMS`](SHA256SUMS).

## Reproducir las medidas

**Comprobación rápida en tu máquina:** [`../tools/quick-bench.py`](../tools/README.es.md) ejecuta esta receta y mide la lectura del prompt, la generación y la generación con el contexto lleno en pocos minutos:

```bash
python3 ../tools/quick-bench.py lfm2.5-2.6b gpu --models-dir ~/models   # o: cpu --threads <núcleos de rendimiento>
```

Los scripts están en [`scripts/`](scripts/), con el nombre de la ronda a la que pertenecen, y los datos en bruto de cada ronda, en [`bench/`](bench/) con el mismo nombre. Las rondas del sobremesa empiezan por `2.5` y las del portátil, por `2.6` (y `2.0`, una prueba de RAM). Los scripts del sobremesa corren dentro de la imagen Docker de [llama-swap](https://github.com/mostlygeek/llama-swap) (`unified-cuda13`, llama.cpp b11580); los del portátil usan la compilación oficial para CPU b11588. La prueba de fidelidad (2.6b) usó llama.cpp b11028 con CUDA en el sobremesa, y la 2.6c repitió parte en el portátil. Los scripts suponen las rutas de los modelos de las máquinas de prueba: edita las variables del principio.

Los resultados del mini-benchmark (un JSON por pasada, con el código generado) están en [`bench/3.2-minibench/`](bench/3.2-minibench/) y los de la prueba de agente, en [`bench/3.3-pi/`](bench/3.3-pi/).

## Licencia

Los scripts de esta carpeta se publican bajo la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen su propia licencia, la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/main/LICENSE).
