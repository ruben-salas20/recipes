#!/usr/bin/env bash
# Ronda 3e: --cache-mode easycache (valores por defecto) con la base; 3 prompts × 2 semillas.
# Sin caché son las imágenes te8disco de 3b. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3e-easycache
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=easycache
IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for s in 42 7; do
  IDS="anuncio producto retrato" bash "$D/estilos.sh" q6_K "$s" "$OUT"
done
echo "3e ok $(date -Is)"
