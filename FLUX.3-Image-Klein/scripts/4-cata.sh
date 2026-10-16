#!/usr/bin/env bash
# Fase 4: los 6 prompts de estilos × semillas 42, 7 y 123 con la receta, en Q6_K y Q5_K.
# Reutiliza las imágenes de 3e (Q6_K) y 3g (Q5_K), hechas con la misma configuración. En ai-lab, en tmux; reanudable.
set -euo pipefail
D=$(dirname "$0")
B=$(cd "$(dirname "$0")/.." && pwd)/bench
OUT=$B/4-cata
mkdir -p "$OUT"
for p in anuncio producto retrato; do
  for s in 42 7; do
    [ -f "$OUT/${p}_q6_K_receta_s$s.png" ] || cp "$B/3e-easycache/${p}_q6_K_easycache_s$s.png" "$OUT/${p}_q6_K_receta_s$s.png"
    [ -f "$OUT/${p}_q5_K_receta_s$s.png" ] || cp "$B/3g-cuantizacion-receta/${p}_q5_K_receta_s$s.png" "$OUT/"
  done
done
export LLM=Qwen3VL-4B-Instruct-Q8_0.gguf
export EXTRA="--params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache" TAG=receta
for t in q6_K q5_K; do
  IDS=anuncio bash "$D/estilos.sh" "$t" 1 "$OUT/calentamiento"
  for s in 42 7 123; do
    bash "$D/estilos.sh" "$t" "$s" "$OUT"
  done
done
echo "cata ok $(date -Is)"
