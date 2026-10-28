#!/usr/bin/env bash
# Paso 2.2e, portátil (b11940 precompilado, QAD-Q4_0, caché f16, sin FA, -t 6 -tb 16, -c 16384):
# generación especulativa con n-gramas en extraer a JSON. Modos none, ngram-mod, ngram-simple, none (valores por
# defecto de b11940). Por modo, los ítems 03, 14 y 16 (los que menos razonan en 3.4), una petición cada uno, muestreo
# de la tarjeta, max_tokens 8192. A 55 °C antes de cada petición.
#   bash LFM3-1.7B/scripts/2.2e-ngramas.sh
set -uo pipefail
cd "$(dirname "$0")/.."
R=$PWD/..
BIN=~/.local/opt/llama.cpp/cpu-b11940; MOD=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=$PWD/bench/2.2e-ngramas; LOG=$OUT/entorno.log; PUERTO=8091
[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
[ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{ date -Is; uptime -p; "$BIN/llama-server" --version 2>&1 | tail -2; } > $LOG 2>&1
i=0
for modo in none ngram-mod ngram-simple none; do
  i=$((i+1))
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m $MOD -t 6 -tb 16 -fa off -c 16384 -np 1 --spec-type $modo \
    > $OUT/server-$i-$modo.log 2>&1 &
  pid=$!
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
  if ! kill -0 $pid 2>/dev/null; then echo "$i-$modo: no arrancó" >> $LOG; continue; fi
  for it in 03 14 16; do
    enfria
    echo "$i-$modo-$it inicio: $(date +%T), $(temp) °C" >> $LOG
    (cd $R/pruebas-generales/extraer-json && python3 run_bench.py --base-url http://127.0.0.1:$PUERTO/v1 --model lfm3-qad \
      --tasks $it --temperature 0.1 --top-k 50 --repeat-penalty 1.1 --out $OUT/json-$i-$modo-$it.json > $OUT/json-$i-$modo-$it.log 2>&1)
    echo "$i-$modo-$it fin: $(date +%T), $(temp) °C" >> $LOG
  done
  kill $pid; wait $pid 2>/dev/null
  gzip -f $OUT/server-$i-$modo.log
done
echo "hecho: $(date -Is)" >> $LOG
