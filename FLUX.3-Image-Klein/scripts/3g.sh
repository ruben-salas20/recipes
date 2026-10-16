#!/usr/bin/env bash
# Ronda 3g: Q5_K y Q4_K con la receta definida (codificador Q8_0 desde disco, EasyCache, 16 pasos, 1 MP);
# 3 prompts × 2 semillas. Q6_K son las imágenes de 3e. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3g-cuantizacion-receta
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta
for t in q5_K q4_K; do
  # Calentamiento por versión: la primera imagen de un fichero nuevo lo lee del HDD.
  IDS=anuncio bash "$D/estilos.sh" "$t" 1 "$OUT/calentamiento"
  for s in 42 7; do
    IDS="anuncio producto retrato" bash "$D/estilos.sh" "$t" "$s" "$OUT"
  done
done
echo "3g ok $(date -Is)"
