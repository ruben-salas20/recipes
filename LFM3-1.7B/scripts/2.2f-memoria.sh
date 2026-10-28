#!/usr/bin/env bash
# Paso 2.2f: memoria de la receta del portátil de LFM3-1.7B (QAD-Q4_0) con 128k, con -lm auto y -lm none,
# como 2.6d de LFM2.5-2.6B, y la velocidad de los dos modos con llama-bench. Portátil enchufado y en reposo:
#   bash LFM3-1.7B/scripts/2.2f-memoria.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu-b11940
MODELO=~/models/LFM3-1.7B-QAD-Q4_0-b3f2ae5.gguf
OUT=bench/2.2f-memoria
mkdir -p "$OUT"
LOG=$OUT/entorno.log
PUERTO=8091

[[ $(cat /sys/class/power_supply/ADP0/online) == 1 && $(powerprofilesctl get) == performance ]] \
  || { echo "enchufa el portátil y pon el perfil performance"; exit 1; }
temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{
  echo "fecha: $(date -Is)"; echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online)"; echo "perfil: $(powerprofilesctl get)"
  "$BIN/llama-server" --version 2>&1 | grep version
  sha256sum "$MODELO"; free -m
} > "$LOG" 2>&1

rss() { awk '/^(VmRSS|RssAnon|RssFile):/{printf "%d,", $2/1024}' /proc/$1/status; }
echo "modo,momento,vmrss_mib,rssanon_mib,rssfile_mib,kv_mib" > "$OUT/memoria.csv"
mide() {
  local nombre=$1; shift
  local slog=$OUT/server-$nombre.log
  enfria
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m "$MODELO" -t 6 -tb 16 -fa off \
    -np 1 --ctx-size 131072 "$@" > "$slog" 2>&1 &
  local pid=$!
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do kill -0 $pid 2>/dev/null || return; sleep 1; done
  sleep 3
  local kv=$(grep -m1 -oP 'CPU KV buffer size = +\K[0-9.]+' "$slog")
  echo "$nombre,arrancado,$(rss $pid)$kv" | tee -a "$OUT/memoria.csv"
  curl -s localhost:$PUERTO/completion -d '{"prompt":"Escribe una función de Python que sume una lista.","n_predict":32}' > /dev/null
  echo "$nombre,tras_peticion,$(rss $pid)$kv" | tee -a "$OUT/memoria.csv"
  kill $pid; wait $pid 2>/dev/null; sleep 3
}
mide lm-auto
mide lm-none -lm none

enfria
echo "bench: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
"$BIN/llama-bench" -m "$MODELO" -t 6 -fa 0 -lm auto,none -r 5 -o csv > "$OUT/bench.csv" 2> "$OUT/bench.log"
echo "bench: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
echo "hecho: $OUT" | tee -a "$LOG"
