#!/usr/bin/env bash
# Fase 5, texto: una infografía con 7 textos en español, con la receta (decisión 10), semillas 42, 7 y 123.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/5-infografia
export TSV=$D/../prompts/infografia.tsv
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta STEPS=8
bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7 123; do bash "$D/estilos.sh" q6_K "$s" "$OUT"; done
echo "infografia ok $(date -Is)"
