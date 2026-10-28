#!/usr/bin/env bash
# Paso 2.2c, portátil (b11940 precompilado): hilos y tamaño de microlote (-ub) para el prefill. QAD-Q4_0, caché f16,
# sin FlashAttention (la candidata de 2.2b). Espera a 55 °C antes de cada corrida.
#   A) -t 4, 6, 8, 12, 16 y otra vez 6 (control): -p 512 -n 128, -d 0, -r 3.
#   B) -t 6, -b 2048, -ub 128, 256, 512, 1024, 2048 y otra vez 512 (control): -p 2048 -n 0, -d 0, -r 3.
#   C) -t 6, -ub 512, 2048, 512 con 8192 de contexto previo: -p 2048 -n 0, -d 8192, -r 2.
#   bash LFM3-1.7B/scripts/2.2c-hilos-ub.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu-b11940; MOD=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=bench/2.2c-hilos-ub; LOG=$OUT/entorno.log
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
[ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{ date -Is; uptime -p; echo "ac: $(cat /sys/class/power_supply/ADP0/online)"; echo "perfil: $(powerprofilesctl get)"; "$BIN/llama-bench" --version 2>&1 | tail -2; } > $LOG 2>&1
corre() {  # nombre, flags de llama-bench
  local n=$1; shift; enfria
  echo "$n inicio: $(date +%T), $(temp) °C" >> $LOG
  "$BIN/llama-bench" -m $MOD -fa off "$@" -o csv > $OUT/$n.csv 2> $OUT/$n.log
  echo "$n fin: $(date +%T), $(temp) °C" >> $LOG
}
i=0
for t in 4 6 8 12 16 6; do i=$((i+1)); corre A$i-t$t -t $t -p 512 -n 128 -r 3; done
i=0
for ub in 128 256 512 1024 2048 512; do i=$((i+1)); corre B$i-ub$ub -t 6 -b 2048 -ub $ub -p 2048 -n 0 -r 3; done
i=0
for ub in 512 2048 512; do i=$((i+1)); corre C$i-ub$ub -t 6 -b 2048 -ub $ub -p 2048 -n 0 -d 8192 -r 2; done
echo "hecho: $(date -Is)" >> $LOG
