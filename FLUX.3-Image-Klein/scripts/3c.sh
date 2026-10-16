#!/usr/bin/env bash
# Ronda 3c: 12 y 8 pasos con la base (Q6_K, codificador Q8_0 desde disco); 3 prompts × 2 semillas.
# Los 16 pasos son los de 3b (te8disco). Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3c-pasos
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu"
export TAG=calentamiento STEPS=16
IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for p in 12 8; do
  export TAG="p$p" STEPS=$p
  for s in 42 7; do
    IDS="anuncio producto retrato" bash "$D/estilos.sh" q6_K "$s" "$OUT"
  done
done
echo "3c ok $(date -Is)"
