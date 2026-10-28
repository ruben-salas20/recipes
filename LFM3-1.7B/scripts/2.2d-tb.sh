#!/usr/bin/env bash
# Paso 2.2d, portátil (b11940 precompilado, QAD-Q4_0, caché f16, sin FA): hilos del prompt (-tb) en llama-server.
# -t 6 siempre (generación); -tb 6, 16, 6, 16 (ABAB). Servidor -c 16384, una petición /completion por arranque:
# ~8k tokens de wikitext-2 (test) y 256 generados con ignore_eos. A 55 °C antes de cada corrida.
#   bash LFM3-1.7B/scripts/2.2d-tb.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu-b11940; MOD=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=bench/2.2d-tb; LOG=$OUT/entorno.log; PUERTO=8091
[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
[ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
TEXTO=$(mktemp); head -c 35000 ~/models/datos/wikitext-2-raw/wiki.test.raw | sed '$d' > $TEXTO
{ date -Is; uptime -p; "$BIN/llama-server" --version 2>&1 | tail -2; echo "texto: $(wc -c < $TEXTO) bytes, sha256 $(sha256sum < $TEXTO | cut -c1-16)"; } > $LOG 2>&1
CUERPO=$(mktemp); jq -Rs '{prompt: ., n_predict: 256, ignore_eos: true, cache_prompt: false}' $TEXTO > $CUERPO; rm -f $TEXTO
trap 'rm -f $CUERPO' EXIT
echo "corrida,tb,prompt_n,prompt_ms,prompt_tps,predicted_n,predicted_tps" > $OUT/peticion.csv
i=0
for tb in 6 16 6 16; do
  i=$((i+1)); enfria
  echo "$i-tb$tb inicio: $(date +%T), $(temp) °C" >> $LOG
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m $MOD -t 6 -tb $tb -fa off -c 16384 -np 1 > $OUT/server-$i-tb$tb.log 2>&1 &
  pid=$!
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
  curl -s localhost:$PUERTO/completion -H 'Content-Type: application/json' -d @$CUERPO | jq 'del(.content)' > $OUT/respuesta-$i-tb$tb.json
  jq -r --arg i $i --arg tb $tb '[$i,$tb,.timings.prompt_n,.timings.prompt_ms,.timings.prompt_per_second,.timings.predicted_n,.timings.predicted_per_second]|@csv' \
    $OUT/respuesta-$i-tb$tb.json >> $OUT/peticion.csv
  kill $pid; wait $pid 2>/dev/null
  gzip -f $OUT/server-$i-tb$tb.log
  echo "$i-tb$tb fin: $(date +%T), $(temp) °C" >> $LOG
done
echo "hecho: $(date -Is)" >> $LOG
