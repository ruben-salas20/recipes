#!/usr/bin/env bash
# Paso 2.6d: memoria de la receta del portátil de LFM2.5-2.6B (QAD-Q4_0): llama-server con 128k,
# con -lm auto y -lm none. La afinidad ya está medida en 2.6. Portátil en reposo:
#   bash LFM2.5-2.6B/scripts/2.6d-memoria.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-2.6B-QAD-Q4_0.gguf
OUT=bench/2.6d-memoria
mkdir -p "$OUT"
LOG=$OUT/entorno.log
PUERTO=8091

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }
{
  echo "fecha: $(date -Is)"; echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"; echo "perfil: $(powerprofilesctl get 2>/dev/null)"
  sha256sum "$MODELO"; free -m
} > "$LOG" 2>&1

corre() {
  local nombre=$1; shift
  enfria
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -r 5 -o csv "$@" > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

rss() { awk '/^(VmRSS|RssAnon|RssFile):/{printf "%d,", $2/1024}' /proc/$1/status; }
echo "modo,momento,vmrss_mib,rssanon_mib,rssfile_mib,kv_mib" > "$OUT/memoria.csv"
mide() {
  local nombre=$1; shift
  local slog=$OUT/server-$nombre.log
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m "$MODELO" -t 6 -C 0x555 --cpu-strict 1 \
    -np 1 --ctx-size 131072 -fa on "$@" > "$slog" 2>&1 &
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
echo "hecho: $OUT" | tee -a "$LOG"
