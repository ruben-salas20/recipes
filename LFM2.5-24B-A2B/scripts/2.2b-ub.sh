#!/usr/bin/env bash
# Paso 2.2b: barrido de -ub del 24B en el portátil, prefill de 2048 tokens. Portátil en reposo y enchufado:
#   bash LFM2.5-24B-A2B/scripts/2.2b-ub.sh
# Antes de cada corrida espera a que el paquete baje de 55 °C, para que todas arranquen igual.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2b-ub
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
} > "$LOG" 2>&1

corre() {
  local nombre=$1; shift
  enfria
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -t 6 -C 0x555 --cpu-strict 1 -b 2048 -r 3 -o csv "$@" \
    > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

corre ub512    -ub 512  -p 2048 -n 0
corre ub1024   -ub 1024 -p 2048 -n 0
corre ub2048   -ub 2048 -p 2048 -n 0
corre ub256    -ub 256  -p 2048 -n 0
corre ub512-b  -ub 512  -p 2048 -n 0

echo "hecho: $OUT" | tee -a "$LOG"
