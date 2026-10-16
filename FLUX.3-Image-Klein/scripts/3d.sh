#!/usr/bin/env bash
# Ronda 3d: 1,4 MP con la base (Q6_K, codificador Q8_0 desde disco, 16 pasos); 3 prompts × 2 semillas.
# 1 MP son las imágenes te8disco de 3b. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3d-resolucion
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu"
export TAG=mp14 RES=1.4
IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7; do
  IDS="anuncio producto retrato" bash "$D/estilos.sh" q6_K "$s" "$OUT"
done
echo "3d ok $(date -Is)"
