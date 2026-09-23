#!/bin/bash
# Fase 2: calidad. 3 recetas × 6 prompts × 3 semillas = 54 imágenes (~5 h).
# Reanudable: si se corta, relanzar el mismo comando; salta lo que ya terminó bien
# y repite lo que falló o quedó a medias.
#
# uso: scripts/fase2.sh   (conviene lanzarlo dentro de tmux o screen: son ~5 h)
cd "$(dirname "$0")/.."
B=scripts/bench.sh
CSV=bench/fase2/resultados.csv
LOG=bench/fase2/progreso.log
mkdir -p bench/fase2

# Resoluciones por receta y proporción (múltiplos de 32)
declare -A RES=(
  [rapida:1:1]="1024 1024"      [rapida:9:16]="768 1344"      [rapida:16:9]="1344 768"
  [equilibrada:1:1]="1184 1184" [equilibrada:9:16]="896 1568" [equilibrada:16:9]="1568 896"
  [maxima:1:1]="1536 1536"      [maxima:9:16]="1152 2048"     [maxima:16:9]="2048 1152"
)
declare -A PASOS=([rapida]=15 [equilibrada]=25 [maxima]=25)

proporcion() {  # W H del tsv → 1:1 | 9:16 | 16:9
  if [ "$1" -eq "$2" ]; then echo 1:1; elif [ "$1" -lt "$2" ]; then echo 9:16; else echo 16:9; fi
}

# Una fila corrupta (p. ej. por un apagón a mitad de escritura) no tiene 17 campos: se descarta
if [ -f "$CSV" ]; then
  awk -F, 'NR==1 || NF==17' "$CSV" > "$CSV.tmp" && mv "$CSV.tmp" "$CSV"
fi

hecho() {  # receta prompt semilla → éxito si ya hay fila con exit 0
  [ -f "$CSV" ] && awk -F, -v n="$1" -v p="$2" -v s="$3" \
    '$1==n && $3==p && $8==s && $10==0 {f=1} END {exit !f}' "$CSV"
}

echo "=== INICIO $(date '+%F %T')" | tee -a "$LOG"
$B _calentamiento calentamiento Q4_0-normal 2 anuncio 512 512 > /dev/null

total=54; n=0
# Semilla por fuera: al acabar cada tercio ya hay una comparación completa de las 3 recetas
for seed in 42 7 123; do
  while IFS=$'\t' read -r id w h _; do
    [ "$id" = id ] && continue
    prop=$(proporcion "$w" "$h")
    for receta in rapida equilibrada maxima; do
      n=$((n + 1))
      if hecho "$receta" "$id" "$seed"; then
        echo "[$n/$total] $receta $id s$seed: ya estaba, salto" | tee -a "$LOG"
        continue
      fi
      # Si una ejecución anterior falló o se cortó, se quita su fila para no duplicar
      [ -f "$CSV" ] && awk -F, -v n="$receta" -v p="$id" -v s="$seed" \
        '!($1==n && $3==p && $8==s)' "$CSV" > "$CSV.tmp" && mv "$CSV.tmp" "$CSV"
      read -r W H <<<"${RES[$receta:$prop]}"
      echo -n "[$n/$total] $(date +%H:%M) " | tee -a "$LOG"
      SEED=$seed $B fase2 "$receta" Q4_0-normal "${PASOS[$receta]}" "$id" "$W" "$H" -- --diffusion-fa \
        < /dev/null | tee -a "$LOG"
    done
  done < prompts/estilos.tsv
done

fallos=$(awk -F, 'NR>1 && $10!=0' "$CSV" | wc -l)
echo "=== FIN $(date '+%F %T') · filas con error: $fallos (relanzar el script las reintenta)" | tee -a "$LOG"
