#!/usr/bin/env bash
# Ronda 3f: --flash-attn on y off con la base (decisión 9); 3 prompts × 2 semillas.
# auto son las imágenes de 3e. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3f-flash-attn
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
B="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache"
for fa in on off; do
  export EXTRA="$B --flash-attn $fa" TAG="fa$fa"
  IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
  for s in 42 7; do
    IDS="anuncio producto retrato" bash "$D/estilos.sh" q6_K "$s" "$OUT"
  done
done
echo "3f ok $(date -Is)"
