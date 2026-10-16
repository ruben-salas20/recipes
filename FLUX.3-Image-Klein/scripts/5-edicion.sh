#!/usr/bin/env bash
# Fase 5, edición: 3 casos con -r × semillas 42 y 7, con la receta (decisión 10). En ai-lab, en tmux; reanudable.
# Las referencias son imágenes de la cata (Q6_K, 8 pasos, semilla 42).
# SOLO=<caso> genera solo ese caso, sin calentamiento. T elige el transformer (q5_K por defecto: Q6_K no cabe con referencias). REFPX limita el área de cada referencia antes del VAE (por defecto 0,5 MP): a 1 MP no cabe en 6 GB.
set -uo pipefail
SD=~/.local/opt/sd.cpp/build/bin/sd-cli
M=/data/ai-lab/models/flux-3-image-klein
B=$(cd "$(dirname "$0")/.." && pwd)/bench
REF=$B/4-cata
REFPX=${REFPX:-524288}
T=${T:-q5_K}
OUT=$B/5-edicion/${T}_ref$REFPX
mkdir -p "$OUT"; cd "$OUT"
CSV=resultados.csv
[ -f "$CSV" ] || echo "caso,semilla,ancho,alto,exit,total_s,codificador_s,muestreo_s,vae_s,vram_pico_mib,ram_pico_kb" > "$CSV"

# caso|ancho|alto|referencias separadas por coma|prompt
CASOS=(
"texto|768|1344|anuncio_q6_K_receta_p8_s42.png|Change the headline text '¿DOLOR DE RODILLA?' to '¿DOLOR DE ESPALDA?'. Keep everything else exactly the same: the man, the park, the colors, the orange button and its text."
"hora|1344|768|ciudad_q6_K_receta_p8_s42.png|Change the time of day to bright midday with a clear blue sky and hard sunlight. Keep the same city, buildings, volcano, street and camera angle."
"combinar|768|1344|retrato_q6_K_receta_p8_s42.png,producto_q6_K_receta_p8_s42.png|The woman from image 1 holding the amber glass supplement bottle with the white 'MAGNESIO' label from image 2 in her hands, smiling at the camera. Keep her face, hair and huipil, and keep the bottle and its label exactly as in image 2."
)
for s in 1 42 7; do
  for c in "${CASOS[@]}"; do
    IFS='|' read -r id w h refs prompt <<< "$c"
    [ -n "${SOLO:-}" ] && [ "$id" != "$SOLO" ] && continue
    # La semilla 1 es solo calentamiento: un caso y fuera de la tabla.
    if [ "$s" = 1 ] && [ "$id" != texto ]; then continue; fi
    n="${id}_s${s}"; [ "$s" = 1 ] && n="calentamiento_${id}"
    if [ -f "$n.png" ]; then echo "$n ya hecho"; continue; fi
    rargs=(); IFS=',' read -r -a rl <<< "$refs"; for r in "${rl[@]}"; do rargs+=(-r "$REF/$r"); done
    ( while :; do nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits; sleep 1; done ) > "$n.vram" &
    mon=$!
    ini=$(date +%s.%N)
    /usr/bin/time -v "$SD" --diffusion-model "$M/gguf/flux-3-image-klein-$T.gguf" \
      --llm "$M/te/Qwen3VL-4B-Instruct-Q8_0.gguf" --vae "$M/ae.safetensors" "${rargs[@]}" \
      -p "$prompt" -W "$w" -H "$h" -s "$s" --cfg-scale 1.0 --steps 8 --sampling-method euler \
      --offload-to-cpu --vae-tiling --params-backend te=disk,diffusion=cpu,vae=cpu --cache-mode easycache \
      --ref-image-args "vae_input_max_pixels=$REFPX" \
      -v -o "$n.png" < /dev/null > "$n.log" 2>&1
    rc=$?
    fin=$(date +%s.%N)
    kill "$mon" 2>/dev/null
    [ "$s" = 1 ] && continue
    seg() { tr '\r' '\n' < "$n.log" | grep -oP "$1 completed, taking \K[0-9.]+" | tail -1 || true; }
    echo "$id,$s,$w,$h,$rc,$(python3 -c "print(round($fin-$ini,1))"),$(seg get_learned_condition),$(seg sampling),$(seg decode_first_stage),$(sort -n "$n.vram" | tail -1),$(awk -F': ' '/Maximum resident set size/{print $2}' "$n.log")" | tee -a "$CSV"
  done
done
echo "edicion ok $(date -Is)"
