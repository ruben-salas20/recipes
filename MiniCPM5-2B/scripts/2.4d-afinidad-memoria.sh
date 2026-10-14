#!/usr/bin/env bash
# Paso 2.4d: receta del portátil de MiniCPM5-2B (IQ4_NL). Decode libre frente a afinidad (ABAB) y memoria de
# llama-server con 128k, con -lm auto y -lm none. Portátil en reposo y enchufado:
#   bash MiniCPM5-2B/scripts/2.4d-afinidad-memoria.sh
# Espera a que el paquete baje de 55 °C antes de cada corrida.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/MiniCPM5-2B-IQ4_NL.gguf
OUT=bench/2.4d-afinidad-memoria
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
corre tg-libre    -t 6 -p 0 -n 128
corre tg-0x555    -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128
corre tg-libre-b  -t 6 -p 0 -n 128
corre tg-0x555-b  -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128

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
