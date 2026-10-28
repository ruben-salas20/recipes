# Recetas

Recetas medidas para ejecutar modelos abiertos en hardware local modesto. Cada carpeta es un modelo: el comando exacto, los ajustes ganadores, los números que los respaldan y los scripts para reproducirlos.

[English version](README.md)

## Modelos de imagen

| Modelo | Equipo | Receta |
|---|---|---|
| Qwen-Image 2.1 (texto a imagen) | RTX 3050 6 GB · 16 GB de RAM | [Español](Qwen-Image-2.1/README.es.md) · [English](Qwen-Image-2.1/README.md) |
| Qwen-Image 2.1 Turbo (texto a imagen, 8 pasos) | RTX 3050 6 GB · 16 GB de RAM | [Español](Qwen-Image-2.1-Turbo/README.es.md) · [English](Qwen-Image-2.1-Turbo/README.md) |
| FLUX.3 Image Klein (texto a imagen, 8 pasos) | RTX 3050 6 GB · 16 GB de RAM | [Español](FLUX.3-Image-Klein/README.es.md) · [English](FLUX.3-Image-Klein/README.md) |

## Modelos de texto

Cuatro modelos con [llama.cpp](https://github.com/ggml-org/llama.cpp) y 128k de contexto, medidos en dos máquinas. Cada receta cubre las dos.

### Medidos con GPU

Sobremesa: **RTX 3050 6 GB de VRAM** · i5-9400 · **16 GB de RAM** · llama.cpp b11580 (CUDA)

| Modelo | Configuración | Generación | Lectura del prompt | Agente de código (Pi) | Receta |
|---|---|---|---|---|---|
| LFM2.5-24B-A2B | QAD-Q4_0, expertos en parte en la RAM | 33,7 tok/s | 906 tok/s | 6 / 9 | [Español](LFM2.5-24B-A2B/README.es.md) · [English](LFM2.5-24B-A2B/README.md) |
| MiniCPM5-2B | Q4_K_M + borrador DSpark | 93,8 tok/s | 2356 tok/s | **7 / 9** | [Español](MiniCPM5-2B/README.es.md) · [English](MiniCPM5-2B/README.md) |
| LFM2.5-2.6B | Q4_K_M + borrador DSpark | **128 tok/s** | 2477 tok/s | 1 / 9 | [Español](LFM2.5-2.6B/README.es.md) · [English](LFM2.5-2.6B/README.md) |
| LFM3-1.7B ¹ | Q4_K_M | 120 tok/s | **~4450 tok/s** | 5 / 9 ² | [Español](LFM3-1.7B/README.es.md) · [English](LFM3-1.7B/README.md) |

### Medidos solo con CPU

Portátil: **sin GPU** · i7-13620H · **24 GB de RAM** · llama.cpp b11588 (CPU)

| Modelo | Configuración | Generación | Lectura del prompt | RAM con 128k | Mini-benchmark de código | Receta |
|---|---|---|---|---|---|---|
| LFM2.5-24B-A2B | QAD-Q4_0 | 26-30 tok/s | ~72 tok/s | 15,6 GB | **7,0 / 11** | [Español](LFM2.5-24B-A2B/README.es.md) · [English](LFM2.5-24B-A2B/README.md) |
| MiniCPM5-2B | IQ4_NL | 28-30 tok/s | ~98 tok/s | 7,0 GB | 6,3 / 11 | [Español](MiniCPM5-2B/README.es.md) · [English](MiniCPM5-2B/README.md) |
| LFM2.5-2.6B | QAD-Q4_0 | 29,2 tok/s | ~98 tok/s | 3,7 GB | 6,3 / 11 | [Español](LFM2.5-2.6B/README.es.md) · [English](LFM2.5-2.6B/README.md) |
| LFM3-1.7B ¹ | QAD-Q4_0 | **37 tok/s** | **~153 tok/s** | **2,6 GB** | 4,7 / 11 | [Español](LFM3-1.7B/README.es.md) · [English](LFM3-1.7B/README.md) |

**Pruébalo en tu máquina:** [`tools/quick-bench.py`](tools/README.es.md) ejecuta una receta y mide en pocos minutos la lectura del prompt, la generación y la generación con el contexto lleno. Da una tabla para compartir.

La lectura del prompt en la GPU es con un prompt de 4k; en la CPU, con 512-2048 tokens. El mini-benchmark son 11 tareas de Python con tests ocultos (media de 3 pasadas); la prueba de agente es Pi en un proyecto pequeño, 3 tareas × 3 pasadas.

¹ LFM3-1.7B: llama.cpp b11940 en las dos máquinas, y mini-benchmark con 8192 tokens por respuesta, como los demás (6,0 / 11 con 32 768). Necesita `max_tokens` 32768 para rendir: ver su receta. ² Con Pi 1.4.0; los demás, con Pi 1.0.3.

Las contribuciones, sobre todo resultados en otros equipos, son bienvenidas: ver [CONTRIBUTING](CONTRIBUTING.md#en-español).

Los scripts de este repositorio tienen licencia MIT. Los pesos de los modelos no se incluyen y conservan sus propias licencias; cada receta dice cuáles.
