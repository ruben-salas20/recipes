#!/usr/bin/env bash
# Paso 2.1b: umbral GGML_OP_OFFLOAD_MIN_BATCH del 24B. Corre dentro del contenedor llama-swap:
#   docker exec llama-swap bash /hf/hub/pruebas/2.1b-offload-min-batch.sh
# Antes: GPU libre (curl -s localhost:8080/unload) y nadie usando el chat.
set -uo pipefail
MODELO=/models/pruebas/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=/hf/hub/pruebas/2.1b-offload-min-batch
mkdir -p "$OUT"
{
  echo "fecha: $(date -Is)"
  llama-bench --version 2>&1 | tail -2
  nvidia-smi --query-gpu=memory.used --format=csv
  nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv
} > "$OUT/entorno.log" 2>&1

for umbral in 32 64 128 256 4096; do
  GGML_OP_OFFLOAD_MIN_BATCH=$umbral llama-bench -m "$MODELO" -ngl 99 -ncmoe 32 -b 2048 -ub 2048 \
    -ctk q8_0 -ctv q8_0 -fa on -t 6 -p 32,64,128,256,512,1024 -n 0 -r 3 -o csv \
    > "$OUT/umbral-$umbral.csv" 2> "$OUT/umbral-$umbral.log"
done
echo "hecho: $OUT" | tee -a "$OUT/entorno.log"
