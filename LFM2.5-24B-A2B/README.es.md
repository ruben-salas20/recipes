# LFM2.5-24B-A2B en una GPU de 6 GB y en un portátil sin GPU

Receta medida para ejecutar [LFM2.5-24B-A2B](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B) en local con [llama.cpp](https://github.com/ggml-org/llama.cpp), con 128k de contexto, en dos máquinas:

| | **Sobremesa** (GPU) | **Portátil** (solo CPU) |
|---|---|---|
| GPU | NVIDIA RTX 3050, **6 GB de VRAM** | **Ninguna** (gráfica integrada, sin usar) |
| CPU | Intel i5-9400, 6 núcleos | Intel i7-13620H, 6 núcleos de rendimiento + 4 de eficiencia |
| RAM | **16 GB** | **24 GB** DDR5 |
| llama.cpp | b11580, CUDA | b11588, compilación oficial para CPU |

LFM2.5-24B-A2B es un modelo de mezcla de expertos (MoE) de Liquid AI: 24 000 millones de parámetros en total, unos 2000 millones activos por token, y un diseño híbrido (casi todo capas de convolución, pocas de atención). Está entrenado para agentes de programación como [Pi](https://github.com/badlogic/pi-mono) y OpenCode. No cabe en 6 GB de VRAM, pero como solo usa 2000 millones de parámetros por token, va a una velocidad útil con la mayoría de los expertos en la RAM, o del todo en la CPU.

Todos los números de esta página se midieron en esas dos máquinas. Los scripts que los generaron están en [`scripts/`](scripts/) y los resultados en bruto, en [`bench/`](bench/).

[English version](README.md)

> [!NOTE]
> **Licencia.** Los pesos están bajo la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/main/LICENSE): uso libre para investigación y para uso comercial en empresas con menos de 10 millones de dólares de ingresos anuales.

## Resumen

| | **Sobremesa** · RTX 3050 6 GB + 16 GB de RAM | **Portátil** · solo CPU + 24 GB de RAM |
|---|---|---|
| Generación, contexto vacío | **33,7 tok/s** | **26-30 tok/s** |
| Generación, con 110k tokens de contexto | 15,0 tok/s | sin medir |
| Lectura del prompt | **906 tok/s** (prompt de 4096 tokens) | **~72 tok/s** |
| Memoria | 5,5 GB de VRAM; el resto de los expertos, en la RAM | **15,6 GB** de RAM con 128k |
| Antes de la receta | 335 tok/s de lectura del prompt | 23,4 tok/s de generación, 16,7 GB de RAM |
| Mini-benchmark de código (11 tareas) | 7,0 / 11, el mejor de las tres recetas | mismo GGUF, misma nota |
| Agente de código (Pi, 9 corridas) | 6 / 9 | sin medir |

## Receta del sobremesa · RTX 3050 6 GB de VRAM + 16 GB de RAM

```bash
llama-server \
  -m LFM2.5-24B-A2B-QAD-Q4_0.gguf \
  -ngl 99 -ncmoe 32 \
  -b 2048 -ub 2048 \
  -np 1 -c 131072 \
  -ctk q8_0 -ctv q8_0 \
  --temp 0.1 --top-k 50 --repeat-penalty 1.05
```

| Opción | Por qué |
|---|---|
| `-ngl 99 -ncmoe 32` | Todas las capas van a la GPU salvo los expertos de 32 capas, que se quedan en la RAM. 32 es el valor que deja sitio para `-ub 2048` con 128k de contexto. |
| `-b 2048 -ub 2048` | Procesa el prompt en lotes de 2048 tokens. Los expertos de la RAM se envían a la GPU una vez por lote, así que lotes más grandes son menos envíos: **la lectura del prompt pasa de 335 a 906 tok/s**. La generación no cambia. |
| `-ctk q8_0 -ctv q8_0` | Caché KV cuantizada, necesaria para que quepan 128k en 6 GB. |
| `-np 1` | Una conversación cada vez. Funciona igual con subagentes: ver [más abajo](#subagentes). |
| `--temp 0.1 --top-k 50 --repeat-penalty 1.05` | El muestreo que recomienda Liquid AI. |

Ocupa 5553 MiB de los 6 GB. La atención rápida (*flash attention*) va activada por defecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-prefill-dark.es.webp">
  <img alt="Lectura del prompt en la RTX 3050 con distintos -ub y -ncmoe" src="assets/gpu-prefill.es.webp">
</picture>

**La generación se frena según se llena el contexto.** Pasa de 33,7 tok/s con el contexto vacío a 15,0 tok/s con 110 000 tokens. La prueba de 110k usó el servidor real, que reserva toda su memoria al arrancar, así que la receta aguanta 128k de verdad.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/gpu-context-dark.es.webp">
  <img alt="Velocidad de generación con 0, 32k, 64k y 110k tokens de contexto" src="assets/gpu-context.es.webp">
</picture>

## Receta del portátil · solo CPU, sin VRAM + 24 GB de RAM

```bash
llama-server \
  -m LFM2.5-24B-A2B-QAD-Q4_0.gguf \
  -t 6 -C 0x555 --cpu-strict 1 \
  -lm none \
  -np 1 -c 131072 -fa on \
  --temp 0.1 --top-k 50 --repeat-penalty 1.05
```

| Opción | Por qué |
|---|---|
| `-t 6` | Un hilo por núcleo de rendimiento. Con más hilos (12 o 16) este portátil no lee el prompt más rápido. |
| `-C 0x555 --cpu-strict 1` | Fija cada hilo a su propio núcleo de rendimiento (CPU 0, 2, 4, 6, 8 y 10), para que ninguno caiga en un núcleo de eficiencia ni dos en el mismo núcleo. +4 a +13 % de generación, menos que el efecto del calor. |
| `-lm none` | Carga el modelo en la RAM en vez de mapear el fichero. Sin esto, parte del modelo acaba dos veces en memoria: **16,7 GB por defecto, 15,6 GB con `none`**. |
| `-fa on` | Atención rápida (*flash attention*). |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/cpu-memory-dark.es.webp">
  <img alt="Memoria con 128k de contexto: -lm auto, -lm none y --no-repack" src="assets/cpu-memory.es.webp">
</picture>

**Lo que limita este portátil es el calor y la potencia, no las opciones.** La CPU llega a 90-95 °C en menos de un minuto y la generación pierde 2-3 tok/s en un par de minutos. Por eso la cifra de generación es un rango (26-30 tok/s). La lectura del prompt se queda en ~72 tok/s con cualquier número de hilos o tamaño de lote, porque la política de energía del fabricante (que aplica `thermald`) limita la CPU a 25 W sostenidos. Con `thermald` parado y un límite de 35 W, la lectura del prompt subió un 10 % y la CPU se calentó 9 °C más; eso no forma parte de la receta.

## Calidad

El mini-benchmark de código son 11 funciones de Python corregidas con tests de pytest ocultos, 3 pasadas por modelo. La prueba de agente es [Pi](https://github.com/badlogic/pi-mono) trabajando en un proyecto pequeño de Python (un registro de gastos de 200 líneas) con 3 tareas: añadir una función, arreglar un fallo descrito por un usuario y refactorizar sin cambiar el comportamiento. 3 pasadas por tarea, con las recetas del sobremesa a 128k. Pi corrió en un entorno aislado (bubblewrap) que solo le dejaba escribir en su copia del proyecto.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/coding-dark.es.webp">
  <img alt="Mini-benchmark de código: media de tareas aprobadas sobre 11" src="assets/coding.es.webp">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/agent-dark.es.webp">
  <img alt="Agente de código con Pi: tareas aprobadas sobre 9" src="assets/agent.es.webp">
</picture>

- **Mini-benchmark: 7,0 / 11** (8, 6 y 7) con el GGUF anterior y 6,7 (6, 7 y 7) con el actual, el mejor de los tres modelos, aunque solo por 0,4-0,7 tareas. Aprobó la tarea de fechas y la de la caché LRU en las 3 pasadas; los dos modelos pequeños no aprobaron nunca la primera y la segunda solo 3 veces de 12. En cambio, falló siempre la de aplanar listas, que los pequeños aprobaron 11 veces de 12.
- **Agente: 6 / 9.** Resolvió las 3 tareas de añadir una función y los 3 arreglos. Falló las 3 refactorizaciones de la misma forma: el informe semanal debe ir de lunes a domingo y lo ordenó alfabéticamente. Los tests visibles del proyecto no lo detectaron. Para escribir y arreglar código, fiable; para proteger un comportamiento que ningún test cubre, no.
- Una pasada varía ±1-2 tareas, así que la diferencia con MiniCPM5-2B (7 / 9) está dentro del ruido.

## Subagentes

Un plugin de subagentes funciona con esta receta y `-np 1`. La sesión principal y el subagente se turnan en el mismo servidor, y el `--cache-ram` de llama.cpp (activo por defecto, hasta 8 GB) guarda en la RAM la conversación que espera. Cuando la principal retoma, solo se procesan los tokens nuevos. **No pongas `--cache-ram 0`.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/subagents-dark.es.webp">
  <img alt="Tiempo para retomar la sesión principal tras un subagente, con y sin --cache-ram" src="assets/subagents.es.webp">
</picture>

`-np 2 --kv-unified` (dos sesiones que comparten una caché de 128k) deja que las dos avancen a la vez, pero cada una a la mitad de velocidad: la última no termina antes que con `-np 1` (8,8 frente a 9,7 s en el sobremesa; 14,5 frente a 14,2 s en el portátil). La prueba simuló el tráfico con un script ([`scripts/subagentes.py`](scripts/subagentes.py)), no con un plugin real.

## Adaptarla a tu máquina

Las cifras de arriba son de estas dos máquinas. Lo que se puede trasladar:

- **El GGUF y el muestreo** son los mismos en cualquier equipo.
- **Más VRAM (sobremesa):** baja `-ncmoe` de uno en uno hasta que el servidor no arranque y vuelve al anterior. Cada paso pasa a la GPU los expertos de una capa más y acelera la generación. Con 8 GB o más también puedes quitar `-ctk q8_0 -ctv q8_0`.
- **`-b 2048 -ub 2048`** ayuda siempre que haya expertos en la RAM (`-ncmoe` mayor que 0). Si te falta VRAM, baja `-ub` antes de subir `-ncmoe`.
- **Otra CPU (portátil):** usa un hilo por núcleo de rendimiento (`-t`). Para `-C`, pon un bit por núcleo de rendimiento, tomando solo el primer hilo de cada uno: míralo con `lscpu --extended`. En CPU sin núcleos de eficiencia puedes omitir `-C`.
- **`-lm none`** ahorra alrededor de 1 GB con cualquier CPU.
- **El calor y la potencia** dependen del portátil. Si la lectura del prompt no sube con más hilos, mira el límite de potencia, no llama.cpp.

## Ficheros

| Fichero | Tamaño | SHA-256 |
|---|---|---|
| [`LFM2.5-24B-A2B-QAD-Q4_0.gguf`](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/0912d33/LFM2.5-24B-A2B-QAD-Q4_0.gguf) (Liquid AI, commit `0912d33`) | 13,58 GB · 4,53 bits por peso | `d1c03f73…934fbabf8a5` |

Hash completo en [`SHA256SUMS`](SHA256SUMS). QAD significa destilación consciente de la cuantización: Liquid AI entrenó este Q4_0 para recuperar lo que se pierde al cuantizar.

> [!IMPORTANT]
> **Liquid AI sustituyó este fichero el 2026-10-13** por pesos nuevos (cambian 390 de 428 tensores; mismo tamaño, tipos y metadatos). La mayoría de las mediciones de esta página usaron el fichero anterior (commit `f97fc8a`, SHA-256 `89617cc4…`). Comprobamos el nuevo en el sobremesa: misma velocidad (903 tok/s de lectura del prompt, 33,5 tok/s de generación) y una perplejidad algo menor (16,55 frente a 16,87 en wikitext-2). Con él, el mini-benchmark dio **6,7 / 11** (6, 7 y 7 tareas), frente a 7,0 con el anterior: lo mismo dentro del ruido. La prueba de agente no se ha repetido. Datos: [`bench/2.1f-gguf-nuevo/`](bench/2.1f-gguf-nuevo/).

## Reproducir las medidas

**Comprobación rápida en tu máquina:** [`../tools/quick-bench.py`](../tools/README.es.md) ejecuta esta receta y mide la lectura del prompt, la generación y la generación con el contexto lleno en pocos minutos:

```bash
python3 ../tools/quick-bench.py lfm2.5-24b-a2b gpu --models-dir ~/models   # o: cpu --threads <núcleos de rendimiento>
```

Los scripts están en [`scripts/`](scripts/), con el nombre de la ronda a la que pertenecen, y los datos en bruto de cada ronda, en [`bench/`](bench/) con el mismo nombre. Las rondas del sobremesa empiezan por `2.1` y las del portátil, por `2.2`. Los scripts del sobremesa corren dentro de la imagen Docker de [llama-swap](https://github.com/mostlygeek/llama-swap) (`unified-cuda13`, llama.cpp b11580); los del portátil usan la compilación oficial para CPU b11588. Suponen las rutas de los modelos de las máquinas de prueba: edita las variables del principio.

Los resultados del mini-benchmark (un JSON por pasada, con el código generado) están en [`bench/3.2-minibench/`](bench/3.2-minibench/) y los de la prueba de agente, en [`bench/3.3-pi/`](bench/3.3-pi/).

## Licencia

Los scripts de esta carpeta se publican bajo la [licencia MIT](../LICENSE). Los pesos del modelo no se incluyen y mantienen su propia licencia, la [LFM Open License v1.0](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/blob/main/LICENSE).
