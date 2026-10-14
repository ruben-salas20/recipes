#!/usr/bin/env bash
# Paso 2.2c: de qué están hechos los 18,2 GB del 24B con 128k en el portátil, y si -lm none o --no-repack
# los bajan. Arranca llama-server con cada modo, manda una petición corta y lee /proc/PID/status.
#   bash LFM2.5-24B-A2B/scripts/2.2c-memoria.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2c-memoria
mkdir -p "$OUT"
LOG=$OUT/entorno.log
PUERTO=8091

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  free -m
} > "$LOG" 2>&1

rss() { awk '/^(VmRSS|RssAnon|RssFile|RssShmem):/{printf "%d,", $2/1024}' /proc/$1/status; }

echo "modo,momento,vmrss_mib,rssanon_mib,rssfile_mib,rssshmem_mib,repack_mib,kv_mib,compute_mib,carga_s" > "$OUT/memoria.csv"
mide() {
  local nombre=$1; shift
  local slog=$OUT/server-$nombre.log
  local t0=$(date +%s.%N)
  "$BIN/llama-server" --host 127.0.0.1 --port $PUERTO -m "$MODELO" -t 6 -C 0x555 --cpu-strict 1 \
    -np 1 --ctx-size 131072 -fa on "$@" > "$slog" 2>&1 &
  local pid=$!
  until curl -sf localhost:$PUERTO/health >/dev/null 2>&1; do
    kill -0 $pid 2>/dev/null || { echo "$nombre: el servidor murió" | tee -a "$LOG"; return; }
    sleep 1
  done
  local carga=$(awk "BEGIN{print $(date +%s.%N) - $t0}")
  sleep 5
  local repack=$(grep -m1 -oP 'CPU_REPACK model buffer size = +\K[0-9.]+' "$slog")
  local kv=$(grep -m1 -oP 'CPU KV buffer size = +\K[0-9.]+' "$slog")
  local cmp=$(grep -m1 -oP 'CPU compute buffer size = +\K[0-9.]+' "$slog")
  echo "$nombre,arrancado,$(rss $pid)$repack,$kv,$cmp,$carga" | tee -a "$OUT/memoria.csv"
  curl -s localhost:$PUERTO/completion -d '{"prompt":"Escribe una función de Python que sume una lista.","n_predict":32}' \
    > "$OUT/respuesta-$nombre.json"
  echo "$nombre,tras_peticion,$(rss $pid)$repack,$kv,$cmp,$carga" | tee -a "$OUT/memoria.csv"
  free -m >> "$LOG"
  kill $pid; wait $pid 2>/dev/null
  sleep 3
}

mide lm-auto
mide lm-none -lm none
mide lm-auto-norepack --no-repack

echo "hecho: $OUT" | tee -a "$LOG"
