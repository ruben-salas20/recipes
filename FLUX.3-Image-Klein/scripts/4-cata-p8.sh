#!/usr/bin/env bash
# Fase 4, tercera variante: Q6_K con la receta pero 8 pasos (EasyCache incluido); 6 prompts × 42, 7 y 123.
# Lánzalo cuando acabe 4-cata.sh: nunca dos tandas a la vez. En tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/4-cata
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta_p8 STEPS=8
IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7 123; do
  bash "$D/estilos.sh" q6_K "$s" "$OUT"
done
echo "cata p8 ok $(date -Is)"
