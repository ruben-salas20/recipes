#!/usr/bin/env bash
# Ronda 3a: Q6_K, Q5_K y Q4_K a 1 MP; 3 prompts × 2 semillas. Corre en ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
OUT=$(cd "$(dirname "$0")/.." && pwd)/bench/3a-cuantizacion
# Calentamiento: una imagen que no cuenta, para que la primera medida no salga lenta.
IDS=anuncio bash "$D/estilos.sh" q6_K 1 "$OUT/calentamiento"
for t in q6_K q5_K q4_K; do
  for s in 42 7; do
    IDS="anuncio producto retrato" bash "$D/estilos.sh" "$t" "$s" "$OUT"
  done
done
echo "3a ok $(date -Is)"
