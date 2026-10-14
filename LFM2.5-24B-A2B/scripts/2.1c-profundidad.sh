#!/usr/bin/env bash
# Paso 2.1c: decode y prefill del 24B en ai-lab con el contexto ya lleno (-d), con la receta de llama-swap.
# Corre dentro del contenedor llama-swap (GPU libre: curl -s localhost:8080/unload):
#   docker exec llama-swap bash /hf/hub/pruebas/2.1c-profundidad.sh
set -uo pipefail
MODELO=/models/pruebas/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=/hf/hub/pruebas/2.1c-profundidad
mkdir -p "$OUT"
{
  echo "fecha: $(date -Is)"
  llama-server --version 2>&1 | tail -2
  nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
} > "$OUT/entorno.log" 2>&1
llama-bench -m "$MODELO" -ngl 99 -ncmoe 32 -b 2048 -ub 2048 -ctk q8_0 -ctv q8_0 -fa 1 \
  -p 512 -n 128 -d 0,32768,65536,114688 -r 2 -o csv > "$OUT/profundidad.csv" 2> "$OUT/profundidad.log"
echo "hecho: $(date -Is)" >> "$OUT/entorno.log"
