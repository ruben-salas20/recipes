#!/usr/bin/env bash
# Fase 2: los 6 prompts de estilos con una configuración. Corre en ai-lab, en tmux; reanudable.
# Uso: estilos.sh <tipo> <semilla> [carpeta]   p. ej. estilos.sh q6_K 42
# IDS="anuncio producto" limita los prompts; por defecto, los 6.
# LLM elige el codificador (fichero en te/), EXTRA añade opciones y TAG se suma al nombre de la variante.
# TSV cambia la lista de prompts. STEPS cambia los pasos (16 por defecto). RES=1.4 pasa a 1,4 MP con los tamaños de Qwen.
set -euo pipefail

T=${1:?tipo}; S=${2:?semilla}
SD=~/.local/opt/sd.cpp/build/bin/sd-cli
M=/data/ai-lab/models/flux-3-image-klein
TSV=${TSV:-$(dirname "$0")/../prompts/estilos.tsv}
LLM=${LLM:-Qwen3VL-4B-Instruct-Q4_K_M.gguf}
read -r -a EXTRA_ARGS <<< "${EXTRA:-}"
V="${T}${TAG:+_$TAG}"
OUT=${3:-$(cd "$(dirname "$0")/.." && pwd)/bench/2-estilos}
mkdir -p "$OUT"; cd "$OUT"

CSV=resultados.csv
[ -f "$CSV" ] || echo "id,tipo,semilla,ancho,alto,exit,total_s,codificador_s,muestreo_s,vae_s,vram_pico_mib,ram_pico_kb" > "$CSV"

tail -n +2 "$TSV" | while IFS=$'\t' read -r id w h prompt; do
  [ -n "${IDS:-}" ] && [[ " $IDS " != *" $id "* ]] && continue
  if [ "${RES:-}" = 1.4 ]; then
    case "${w}x${h}" in 1024x1024) w=1184 h=1184 ;; 768x1344) w=896 h=1568 ;; 1344x768) w=1568 h=896 ;; esac
  fi
  n="${id}_${V}_s${S}"
  if [ -f "$n.png" ]; then echo "$n ya hecho"; continue; fi
  ( while :; do nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits; sleep 1; done ) > "$n.vram" &
  mon=$!
  ini=$(date +%s.%N)
  set +e
  /usr/bin/time -v "$SD" --diffusion-model "$M/gguf/flux-3-image-klein-$T.gguf" \
    --llm "$M/te/$LLM" --vae "$M/ae.safetensors" \
    -p "$prompt" -W "$w" -H "$h" -s "$S" --cfg-scale 1.0 --steps "${STEPS:-16}" --sampling-method euler \
    --offload-to-cpu --vae-tiling "${EXTRA_ARGS[@]}" -v -o "$n.png" < /dev/null > "$n.log" 2>&1
  rc=$?
  set -e
  fin=$(date +%s.%N)
  kill "$mon" 2>/dev/null || true
  seg() { tr '\r' '\n' < "$n.log" | grep -oP "$1 completed, taking \K[0-9.]+" | tail -1 || true; }
  te=$(seg get_learned_condition); mu=$(seg sampling); va=$(seg decode_first_stage)
  vram=$(sort -n "$n.vram" | tail -1)
  rss=$(awk -F': ' '/Maximum resident set size/{print $2}' "$n.log")
  tot=$(python3 -c "print(round($fin-$ini,1))")
  echo "$id,$V,$S,$w,$h,$rc,$tot,$te,$mu,$va,$vram,$rss" | tee -a "$CSV"
done
echo "estilos ok $(date -Is)"
