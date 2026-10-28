#!/usr/bin/env bash
# Paso 2.2b, portátil (b11940 precompilado, -t 6, QAD-Q4_0, caché f16): FlashAttention on/off con ~32k de contexto.
# A) Servidor -c 36864, una petición /completion: ~32k tokens de wikitext-2 (test) y 256 generados con ignore_eos.
#    Prefill y TTFT (prompt_ms), decode a ~32k y RSS. Orden on, off, on; a 55 °C antes de cada corrida.
# B) Búfer de cálculo al arrancar a 32k, 128k y 256k, con y sin FA (solo se lee el log; sin peticiones).
#   bash LFM3-1.7B/scripts/2.2b-fa-32k.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu-b11940; MOD=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=bench/2.2b-fa-32k; LOG=$OUT/entorno.log; PUERTO=8091
[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
[ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
TEXTO=$(mktemp); head -c 140000 ~/models/datos/wikitext-2-raw/wiki.test.raw | sed '$d' > $TEXTO
{ date -Is; uptime -p; "$BIN/llama-server" --version 2>&1 | tail -2; echo "texto: $(wc -c < $TEXTO) bytes, sha256 $(sha256sum < $TEXTO | cut -c1-16)"; free -m; } > $LOG 2>&1
CUERPO=$(mktemp); jq -Rs '{prompt: ., n_predict: 256, ignore_eos: true, cache_prompt: false}' $TEXTO > $CUERPO; rm -f $TEXTO
trap 'rm -f $CUERPO' EXIT
arranca() { # $1 fa, $2 ctx, $3 log
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m $MOD -t 6 -fa $1 -c $2 -np 1 -v > $3 2>&1 &
  pid=$!
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do kill -0 $pid 2>/dev/null || { pid=; return 1; }; sleep 0.5; done
}

# A
echo "corrida,fa,prompt_n,prompt_ms,prompt_tps,predicted_n,predicted_tps,rss_kb" > $OUT/peticion.csv
i=0
for fa in on off on; do
  i=$((i+1)); enfria
  echo "$i-fa$fa inicio: $(date +%T), $(temp) °C" >> $LOG
  arranca $fa 36864 $OUT/server-$i-fa$fa.log || { echo "$i-fa$fa: no arrancó" >> $LOG; continue; }
  curl -s localhost:$PUERTO/completion -H 'Content-Type: application/json'  -d @$CUERPO | jq 'del(.content)' > $OUT/respuesta-$i-fa$fa.json
  rss=$(grep -oP '^VmRSS:\s+\K[0-9]+' /proc/$pid/status)
  jq -r --arg i $i --arg fa $fa --arg rss $rss '[$i,$fa,.timings.prompt_n,.timings.prompt_ms,.timings.prompt_per_second,.timings.predicted_n,.timings.predicted_per_second,$rss]|@csv' \
    $OUT/respuesta-$i-fa$fa.json >> $OUT/peticion.csv
  kill $pid; wait $pid 2>/dev/null
  echo "$i-fa$fa fin: $(date +%T), $(temp) °C" >> $LOG
done

# B
for fa in on off; do
  for c in 32768 131072 262144; do
    if arranca $fa $c $OUT/arranque-fa$fa-c$c.log; then
      echo "arranque fa$fa c$c: $(grep -h 'compute buffer size' $OUT/arranque-fa$fa-c$c.log | tr -s ' ' | cut -d' ' -f3-) rss_kb $(grep -oP '^VmRSS:\s+\K[0-9]+' /proc/$pid/status)" >> $LOG
      kill $pid; wait $pid 2>/dev/null
    else
      echo "arranque fa$fa c$c: no arrancó" >> $LOG
    fi
  done
done
gzip -f $OUT/*.log 2>/dev/null; gunzip -f $LOG.gz
echo "hecho: $(date -Is)" >> $LOG
