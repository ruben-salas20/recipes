#!/usr/bin/env bash
# Fase 5, técnico: los 12 temas de tecnico.tsv × semillas 42 y 7 con la receta (decisión 10). En ai-lab, en tmux.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/5-tecnico
export TSV=$D/../prompts/tecnico.tsv
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta STEPS=8
IDS=corazon bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7; do
  bash "$D/estilos.sh" q6_K "$s" "$OUT"
done
echo "tecnico ok $(date -Is)"
