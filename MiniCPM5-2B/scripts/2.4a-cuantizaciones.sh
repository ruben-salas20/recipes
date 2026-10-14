#!/usr/bin/env bash
# Paso 2.4a: velocidad de Q4_K_M, Q4_0 e IQ4_NL de MiniCPM5-2B en el portátil. Portátil en reposo y enchufado:
#   bash MiniCPM5-2B/scripts/2.4a-cuantizaciones.sh
# Espera a que el paquete baje de 55 °C antes de cada corrida.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
OUT=bench/2.4a-cuantizaciones
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
  sha256sum ~/models/MiniCPM5-2B-*.gguf
} > "$LOG" 2>&1

corre() {
  local nombre=$1 cuant=$2; shift 2
  enfria
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m ~/models/MiniCPM5-2B-$cuant.gguf -fa 1 -t 6 -r 5 -p 512 -n 128 -o csv "$@" \
    > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

corre q4km     Q4_K_M
corre q4_0     Q4_0
corre iq4nl    IQ4_NL
corre q4km-b   Q4_K_M

echo "hecho: $OUT" | tee -a "$LOG"
