#!/bin/bash
# Comparativa final: la receta normal medida de nuevo con sd.cpp actual frente al turbo oficial
# (con el codificador Q4_K_M y con el Q8_0 en disco),
# 6 prompts × 3 semillas, y después el frente técnico con el turbo (12 temas × 2 semillas).
# Reanudable: si se corta, relanzar el mismo comando; salta lo que ya terminó bien.
#
# Ajustes del turbo: los ganadores de scripts/turbo1.sh (variables TURBO_*, más abajo).
cd "$(dirname "$0")/.."
B=scripts/bench.sh
LOG=bench/final/progreso.log
mkdir -p bench/final bench/tecnico-turbo

T=/data/ai-lab/models/qwen-image-2.1-turbo
TURBO_MODEL=${TURBO_MODEL:-$T/Qwen-Image-2.1-Turbo-AD-Q4_K.gguf}
TURBO_TIER=${TURBO_TIER:-14mp}
TURBO_EXTRA=${TURBO_EXTRA:-}
TE8=/data/ai-lab/models/qwen-image-2.1/Qwen3VL-8B-Instruct-Q8_0.gguf
SIG="1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0"

declare -A RES=(
  [1mp:1:1]="1024 1024"   [1mp:9:16]="768 1344"   [1mp:16:9]="1344 768"
  [14mp:1:1]="1184 1184"  [14mp:9:16]="896 1568"  [14mp:16:9]="1568 896"
  [24mp:1:1]="1536 1536"  [24mp:9:16]="1152 2048" [24mp:16:9]="2048 1152"
)
proporcion() { if [ "$1" -eq "$2" ]; then echo 1:1; elif [ "$1" -lt "$2" ]; then echo 9:16; else echo 16:9; fi; }

# Una fila corrupta (corte a mitad de escritura) no tiene 17 campos: se descarta
limpiar() { [ -f "$1" ] && awk -F, 'NR==1 || NF==17' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
hecho() {  # csv receta prompt semilla → éxito si ya hay fila con exit 0
  [ -f "$1" ] && awk -F, -v n="$2" -v p="$3" -v s="$4" '$1==n && $3==p && $8==s && $10==0 {f=1} END {exit !f}' "$1"
}
quitar() { [ -f "$1" ] && awk -F, -v n="$2" -v p="$3" -v s="$4" '!($1==n && $3==p && $8==s)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

limpiar bench/final/resultados.csv
limpiar bench/tecnico-turbo/resultados.csv
echo "=== INICIO $(date '+%F %T') · turbo: $(basename "$TURBO_MODEL") $TURBO_TIER $TURBO_EXTRA" | tee -a "$LOG"
$B _calentamiento calentamiento "$TURBO_MODEL" 2 anuncio 512 512 -- --diffusion-fa > /dev/null

# 1) Estilos: normal frente a turbo y turbo8
CSV=bench/final/resultados.csv; n=0; total=54
for seed in 42 7 123; do
  while IFS=$'\t' read -r id w h _; do
    [ "$id" = id ] && continue
    prop=$(proporcion "$w" "$h")
    for receta in normal turbo turbo8; do
      n=$((n + 1))
      if hecho $CSV $receta "$id" $seed; then echo "[$n/$total] $receta $id s$seed: ya estaba" | tee -a "$LOG"; continue; fi
      quitar $CSV $receta "$id" $seed
      echo -n "[$n/$total] $(date +%H:%M) " | tee -a "$LOG"
      if [ $receta = normal ]; then
        read -r W H <<<"${RES[14mp:$prop]}"
        SEED=$seed $B final normal Q4_0-normal 25 "$id" "$W" "$H" -- --diffusion-fa < /dev/null | tee -a "$LOG"
      elif [ $receta = turbo ]; then
        read -r W H <<<"${RES[$TURBO_TIER:$prop]}"
        SEED=$seed $B final turbo "$TURBO_MODEL" 8 "$id" "$W" "$H" -- --diffusion-fa --sigmas "$SIG" $TURBO_EXTRA < /dev/null | tee -a "$LOG"
      else
        read -r W H <<<"${RES[$TURBO_TIER:$prop]}"
        LLM=$TE8 SEED=$seed $B final turbo8 "$TURBO_MODEL" 8 "$id" "$W" "$H" -- --diffusion-fa --sigmas "$SIG" \
          --params-backend "te=disk,diffusion=cpu,vae=cpu" $TURBO_EXTRA < /dev/null | tee -a "$LOG"
      fi
    done
  done < prompts/estilos.tsv
done

# 2) Frente técnico con el turbo
CSV=bench/tecnico-turbo/resultados.csv; n=0; total=24
for id in $(tail -n +2 prompts/tecnico.tsv | cut -f1); do
  for seed in 42 7; do
    n=$((n + 1))
    if hecho $CSV turbo "$id" $seed; then echo "[tec $n/$total] $id s$seed: ya estaba" | tee -a "$LOG"; continue; fi
    quitar $CSV turbo "$id" $seed
    linea=$(awk -F'\t' -v i="$id" '$1==i' prompts/tecnico.tsv)
    prop=$(proporcion "$(cut -f2 <<<"$linea")" "$(cut -f3 <<<"$linea")")
    read -r W H <<<"${RES[$TURBO_TIER:$prop]}"
    echo -n "[tec $n/$total] $(date +%H:%M) " | tee -a "$LOG"
    PROMPTS=prompts/tecnico.tsv SEED=$seed $B tecnico-turbo turbo "$TURBO_MODEL" 8 "$id" "$W" "$H" -- --diffusion-fa --sigmas "$SIG" $TURBO_EXTRA < /dev/null | tee -a "$LOG"
  done
done

echo "=== FIN $(date '+%F %T')" | tee -a "$LOG"
