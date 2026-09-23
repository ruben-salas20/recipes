#!/bin/bash
# Genera una imagen con una configuración y añade una fila al CSV de la ronda.
# uso: bench.sh <ronda> <nombre> <modelo> <pasos> <prompt_id> [W H] [-- args extra de sd-cli]
#   modelo: sufijo del fichero, p. ej. Q4_0-normal → qwen-image-2.1-Q4_0-normal.gguf
#   W H: si se omiten, se usan los del prompt en prompts/estilos.tsv
#   env: SEED (42), CFG (1), PROMPTS (prompts/estilos.tsv), OFFLOAD (--offload-to-cpu; vacío = sin offload)
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
D=/data/ai-lab/models/qwen-image-2.1
SD=~/.local/opt/sd.cpp/build/bin/sd-cli

ronda=$1 nombre=$2 modelo=$3 pasos=$4 pid=$5; shift 5
linea=$(awk -F'\t' -v id="$pid" '$1==id' "${PROMPTS:-$R/prompts/estilos.tsv}")
[ -z "$linea" ] && { echo "prompt '$pid' no existe"; exit 1; }
W=$(cut -f2 <<<"$linea") H=$(cut -f3 <<<"$linea") prompt=$(cut -f4 <<<"$linea")
if [ $# -ge 2 ] && [ "$1" != "--" ]; then W=$1 H=$2; shift 2; fi
[ "${1:-}" = "--" ] && shift
extra=("$@")
seed=${SEED:-42} cfg=${CFG:-1}

out="$R/bench/$ronda"; mkdir -p "$out"
base="$out/${nombre}_${pid}_s${seed}"
csv="$out/resultados.csv"
[ -f "$csv" ] || echo "nombre,modelo,prompt,W,H,pasos,cfg,seed,extra,exit,total_s,muestreo_s,s_por_paso,vae_s,ram_pico_gb,vram_reposo_mib,vram_pico_mib" > "$csv"

vram_reposo=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
# nvidia-smi -lms escribe una lectura cada 500 ms mientras dure la generación
nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms 500 > "$base.vram" &
vpid=$!

/usr/bin/time -f "TIME %e %M" "$SD" \
  --diffusion-model "$D/qwen-image-2.1-$modelo.gguf" \
  --vae "$D/qwen_image_2.1_vae_bf16.safetensors" \
  --llm "$D/Qwen3VL-8B-Instruct-Q4_K_M.gguf" \
  ${OFFLOAD---offload-to-cpu} --vae-tiling --vae-tile-size 24x24 \
  --cfg-scale "$cfg" --sampling-method euler --steps "$pasos" \
  -W "$W" -H "$H" --seed "$seed" "${extra[@]}" \
  -p "$prompt" -o "$base.png" > "$base.log" 2>&1
rc=$?
kill $vpid 2>/dev/null; wait $vpid 2>/dev/null

read -r total rss < <(grep '^TIME' "$base.log" | awk '{print $2, $3}')
muestreo=$(grep -o 'sampling completed, taking [0-9.]*' "$base.log" | awk '{print $4}')
vae=$(grep -o 'decode_first_stage completed, taking [0-9.]*' "$base.log" | awk '{print $4}')
vram_pico=$(sort -n "$base.vram" | tail -1)
s_paso=$( [ -n "$muestreo" ] && awk -v m="$muestreo" -v p="$pasos" 'BEGIN{printf "%.2f", m/p}')
ram=$(awk -v k="${rss:-0}" 'BEGIN{printf "%.2f", k/1048576}')

echo "$nombre,$modelo,$pid,$W,$H,$pasos,$cfg,$seed,\"${extra[*]}\",$rc,$total,$muestreo,$s_paso,$vae,$ram,$vram_reposo,$vram_pico" >> "$csv"
echo "$nombre: exit=$rc total=${total}s muestreo=${muestreo}s (${s_paso}s/paso) vae=${vae}s ram=${ram}GB vram=${vram_pico}MiB"
