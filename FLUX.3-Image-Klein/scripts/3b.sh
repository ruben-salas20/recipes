#!/usr/bin/env bash
# Ronda 3b: codificador Q8_0 en RAM y Q8_0 desde disco, con Q6_K; 3 prompts × 2 semillas.
# La base (codificador Q4_K_M) es la de 3a. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3b-codificador
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
for v in te8 te8disco; do
  export TAG=$v EXTRA=""
  [ "$v" = te8disco ] && export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu"
  # Calentamiento de cada variante (no cuenta): la primera imagen lee los ficheros del HDD.
  IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
  for s in 42 7; do
    IDS="anuncio producto retrato" bash "$D/estilos.sh" q6_K "$s" "$OUT"
  done
done
echo "3b ok $(date -Is)"
