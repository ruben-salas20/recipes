#!/bin/bash
# Recetas de octubre de 2026 a 1 MP: Turbo y normal, 6 prompts × 3 semillas, con sd.cpp 8cd731e.
# uso: final-1016.sh turbo|normal
# Escribe bench/final-1016/ (Turbo) o ../Qwen-Image-2.1/bench/final-1016/ (normal): una imagen, un log y una fila de
# resultados.csv por ejecución. Antes de las 18 imágenes genera una de calentamiento (semilla 1) en calentamiento/,
# para que los ficheros entren en la caché del sistema. Reanudable: salta las imágenes que ya existen.
# Columnas: tiempos en segundos (total de reloj y cada fase según el log), VRAM máxima en MiB, RAM máxima del proceso
# en kB, lecturas_fs = bloques de 512 B leídos del disco, cache/disponible = free -m antes de cada imagen.
set -euo pipefail
cd "$(dirname "$0")/.."
D=/data/ai-lab/models/qwen-image-2.1
T=/data/ai-lab/models/qwen-image-2.1-turbo
SD=~/.local/opt/sd.cpp/build/bin/sd-cli
TSV=../Qwen-Image-2.1/prompts/estilos.tsv
SIG="1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0"
CAB="id,receta,semilla,ancho,alto,exit,total_s,codificador_s,muestreo_s,vae_s,vram_pico_mib,ram_pico_kb,lecturas_fs,cache_antes_mb,disponible_antes_mb"

case ${1:-} in
  turbo)  O=bench/final-1016
          args=(--diffusion-model "$T/Qwen-Image-2.1-Turbo-AD-Q4_K.gguf" --steps 8 --sigmas "$SIG"
                --params-backend "te=disk,diffusion=disk,vae=cpu") ;;
  normal) O=../Qwen-Image-2.1/bench/final-1016
          args=(--diffusion-model "$D/qwen-image-2.1-Q4_0-normal.gguf" --steps 25
                --params-backend "te=disk,diffusion=cpu,vae=cpu") ;;
  *) echo "uso: $0 turbo|normal"; exit 1 ;;
esac
R=$1

gen() {  # gen <carpeta> <prompt> <semilla>
  local dir=$1 id=$2 s=$3 w h prompt n
  IFS=$'\t' read -r _ w h prompt < <(awk -F'\t' -v id="$id" '$1==id' "$TSV")
  mkdir -p "$dir"; n="$dir/${R}_${id}_s${s}"
  [ -f "$n.png" ] && { echo "$n ya hecho"; return; }
  ( while :; do nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits; sleep 1; done ) > "$n.vram" &
  local mon=$! cache disp ini fin rc
  read -r cache disp < <(free -m | awk '/^Mem:/{print $6, $7}')
  ini=$(date +%s.%N)
  set +e
  /usr/bin/time -v "$SD" "${args[@]}" --llm "$D/Qwen3VL-8B-Instruct-Q4_K_M.gguf" \
    --vae "$D/qwen_image_2.1_vae_bf16.safetensors" \
    -p "$prompt" -W "$w" -H "$h" -s "$s" --cfg-scale 1 --sampling-method euler \
    --offload-to-cpu --vae-tiling --vae-tile-size 512 -v -o "$n.png" < /dev/null > "$n.log" 2>&1
  rc=$?
  set -e
  fin=$(date +%s.%N)
  kill "$mon" 2>/dev/null || true
  [ -f "$dir/resultados.csv" ] || echo "$CAB" > "$dir/resultados.csv"
  seg() { tr '\r' '\n' < "$n.log" | grep -oP "$1 completed, taking \K[0-9.]+" | tail -1 || true; }
  echo "$id,$R,$s,$w,$h,$rc,$(python3 -c "print(round($fin-$ini,1))"),$(seg get_learned_condition),$(seg sampling),$(seg decode_first_stage),$(sort -n "$n.vram" | tail -1),$(awk -F': ' '/Maximum resident set size/{print $2}' "$n.log"),$(awk -F': ' '/File system inputs/{print $2}' "$n.log"),$cache,$disp" \
    | tee -a "$dir/resultados.csv"
}

gen "$O/calentamiento" producto 1
for s in 42 7 123; do for id in producto retrato medico anuncio ciudad anime; do gen "$O" "$id" "$s"; done; done
