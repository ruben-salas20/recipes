#!/usr/bin/env bash
# Fase 5, técnico a 16 pasos (Q6_K, codificador Q8_0 desde disco, EasyCache): mismos 12 temas × 42 y 7.
# Lánzalo cuando acabe 5-tecnico.sh: nunca dos tandas a la vez. En tmux.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/5-tecnico
export TSV=$D/../prompts/tecnico.tsv
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta_p16 STEPS=16
IDS=corazon bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7; do
  bash "$D/estilos.sh" q6_K "$s" "$OUT"
done
echo "tecnico p16 ok $(date -Is)"
