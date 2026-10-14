#!/usr/bin/env bash
# Paso 2.2g: subagentes con la receta del 24B en el portátil. Portátil en reposo y enchufado; espera a 55 °C
# antes de cada variante.  bash LFM2.5-24B-A2B/scripts/2.2g-subagentes.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
OUT=bench/2.2g-subagentes; mkdir -p "$OUT"; LOG=$OUT/entorno.log
RECETA="-m $HOME/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf -t 6 -C 0x555 --cpu-strict 1 -lm none --ctx-size 131072 -fa on"
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{ echo "fecha: $(date -Is)"; echo "ac: $(cat /sys/class/power_supply/ADP0/online)"; free -m; } > "$LOG"
for v in "np1-cram8192|-np 1" "np1-cram0|-np 1 --cache-ram 0" "np2-kvu|-np 2 --kv-unified"; do
  IFS='|' read -r nombre flags <<< "$v"
  enfria
  "$BIN/llama-server" --host 127.0.0.1 --port 8092 $RECETA $flags > "$OUT/server-$nombre.log" 2>&1 & PID=$!
  until curl -sf localhost:8092/health >/dev/null 2>&1; do sleep 2; done
  echo "$nombre: inicio $(date +%T), $(temp) °C" >> "$LOG"
  ( while sleep 10; do echo "$nombre $(date +%T) $(free -m | awk '/Mem:/{printf "ram_usada %d ", $3} /Swap:/{printf "swap %d", $3}') rss $(( $(awk '/VmRSS/{print $2}' /proc/$PID/status) / 1024 ))"; done ) >> "$OUT/memoria.log" & VIG=$!
  python3 scripts/subagentes.py http://127.0.0.1:8092 "$nombre" "$OUT/resultados.csv" 8000 2000 >> "$LOG" 2>&1
  kill $VIG $PID; wait $PID 2>/dev/null; sleep 3
done
echo "hecho: $(date -Is)" >> "$LOG"
