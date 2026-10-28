#!/usr/bin/env bash
# Paso 2.2a, portátil (b11940 precompilado, -t 6): FlashAttention activada frente a desactivada, caché f16.
# QAD-Q4_0, llama-bench -p 512 -n 128 -d 0,8192 -r 3, en orden ABAB (on, off, on, off). Espera a 55 °C antes de cada corrida.
#   bash LFM3-1.7B/scripts/2.2a-flashattention.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu-b11940; MOD=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=bench/2.2a-flashattention; LOG=$OUT/entorno.log
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
[ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{ date -Is; uptime -p; echo "ac: $(cat /sys/class/power_supply/ADP0/online)"; echo "perfil: $(powerprofilesctl get)"; "$BIN/llama-bench" --version 2>&1 | tail -2; } > $LOG 2>&1
i=0
for fa in on off on off; do
  i=$((i+1)); enfria
  echo "$i-fa$fa inicio: $(date +%T), $(temp) °C" >> $LOG
  "$BIN/llama-bench" -m $MOD -t 6 -fa $fa -p 512 -n 128 -d 0,8192 -r 3 -o csv > $OUT/bench-$i-fa$fa.csv 2> $OUT/bench-$i-fa$fa.log
  echo "$i-fa$fa fin: $(date +%T), $(temp) °C" >> $LOG
done
echo "hecho: $(date -Is)" >> $LOG
