#!/usr/bin/env bash
# Paso 2.0: punto de partida de LFM3-1.7B (b11940), las tres candidatas.
# A) llama-bench pp512/tg128 a contexto vacío (-r 5) y con contexto previo (-r 3).
# B) llama-server a 262144 de contexto (-np 1, KV f16): memoria y TTFT con prompt-largo.txt (3 peticiones).
# Uso:
#   portátil: bash LFM3-1.7B/scripts/2.0-partida.sh portatil
#   ai-lab:   scp script y prompt-largo.txt a ~/otros/pruebas/lfm3-2.0/ y, en tmux,
#             curl -s localhost:8080/unload; bash ~/otros/pruebas/lfm3-2.0/2.0-partida.sh ailab
set -uo pipefail
MAQ=$1
QUANTS="QAD-Q4_0 Q4_K_M Q8_0"
PUERTO=8090
case $MAQ in
  portatil)
    cd "$(dirname "$0")/.."
    BIN=~/.local/opt/llama.cpp/cpu-b11940; MD=~/models; OUT=bench/2.0-partida/portatil
    PROMPT=bench/2.0-partida/prompt-largo.txt
    DEV="-t 6"; DEPTH=8192; PUERTO=8091 ;;
  ailab)
    cd "$(dirname "$0")"
    BIN=~/.local/bin; MD=/data/ai-lab/models/llm; OUT=resultados
    PROMPT=prompt-largo.txt
    DEV="-ngl 99"; DEPTH=32768 ;;
  *) echo "máquina: portatil o ailab"; exit 1 ;;
esac
if [ $MAQ = portatil ]; then
  [ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ] || { echo "portátil sin enchufar: no se mide"; exit 1; }
  [ "$(powerprofilesctl get)" = performance ] || { echo "perfil distinto de performance: no se mide"; exit 1; }
fi
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { [ $MAQ = portatil ] || return 0; while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
marca() { echo "$1: $(date +%T)${2:+, $(temp) °C}" >> "$LOG"; }
{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  "$BIN/llama-bench" --version 2>&1 | tail -2
  if [ $MAQ = portatil ]; then
    echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
    echo "perfil: $(powerprofilesctl get 2>/dev/null)"
  else
    nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
    nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv
  fi
  free -m
} > "$LOG" 2>&1
T=; [ $MAQ = portatil ] && T=t

# A. llama-bench.
for q in $QUANTS; do
  m=$MD/LFM3-1.7B-$q-b3f2ae5.gguf
  enfria; marca "bench-$q-d0 inicio" $T
  "$BIN/llama-bench" -m "$m" $DEV -p 512 -n 128 -r 5 -o csv > "$OUT/bench-$q-d0.csv" 2> "$OUT/bench-$q-d0.log"
  marca "bench-$q-d0 fin" $T
  enfria; marca "bench-$q-d$DEPTH inicio" $T
  "$BIN/llama-bench" -m "$m" $DEV -p 512 -n 128 -d $DEPTH -r 3 -o csv > "$OUT/bench-$q-d$DEPTH.csv" 2> "$OUT/bench-$q-d$DEPTH.log"
  marca "bench-$q-d$DEPTH fin" $T
done

# B. Servidor a 262144: memoria y TTFT.
cuerpo=$(jq -Rs '{messages:[{role:"user",content:("Summarize the following text in one sentence.\n\n" + .)}],
  max_tokens:32, cache_prompt:false}' "$PROMPT")
echo "cuant,peticion,prompt_n,prompt_ms,prompt_tps" > "$OUT/ttft.csv"
for q in $QUANTS; do
  m=$MD/LFM3-1.7B-$q-b3f2ae5.gguf
  enfria; marca "server-$q inicio" $T
  t0=$(date +%s.%N)
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m "$m" $DEV -c 262144 -np 1 -fit off -v \
    --temp 0.1 --top-k 50 --repeat-penalty 1.1 > "$OUT/server-$q.log" 2>&1 &
  pid=$!
  ok=1
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do kill -0 $pid 2>/dev/null || { ok=0; break; }; sleep 0.5; done
  if [ $ok = 0 ]; then echo "server-$q: no arrancó" >> "$LOG"; gzip -f "$OUT/server-$q.log"; continue; fi
  echo "carga-$q s: $(awk "BEGIN{print $(date +%s.%N) - $t0}")" >> "$LOG"
  for i in 1 2 3; do
    curl -s localhost:$PUERTO/v1/chat/completions -H 'Content-Type: application/json' -d "$cuerpo" > "$OUT/ttft-$q-$i.json"
    jq -r --arg q $q --arg i $i '[$q, $i, .timings.prompt_n, .timings.prompt_ms, .timings.prompt_per_second]|@csv' \
      "$OUT/ttft-$q-$i.json" >> "$OUT/ttft.csv"
  done
  {
    echo "memoria-$q:"
    grep -E "^(VmRSS|RssAnon|RssFile)" /proc/$pid/status
    [ $MAQ = ailab ] && nvidia-smi --query-gpu=memory.used --format=csv,noheader
    grep -E "KV buffer size|compute buffer size|model buffer size|offloaded" "$OUT/server-$q.log"
  } >> "$LOG" 2>&1
  kill $pid; wait $pid 2>/dev/null
  gzip -f "$OUT/server-$q.log"
  marca "server-$q fin" $T
done
echo "hecho: $(date -Is)" >> "$LOG"
