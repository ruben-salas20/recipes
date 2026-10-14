#!/usr/bin/env bash
# Paso 2.4b: prefill largo de las tres cuantizaciones y afinidad con Q4_0, MiniCPM5-2B en el portátil. Portátil en reposo y enchufado:
#   bash MiniCPM5-2B/scripts/2.4b-prefill-afinidad.sh
# Espera a que el paquete baje de 55 °C antes de cada corrida.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
OUT=bench/2.4b-prefill-afinidad
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
  "$BIN/llama-bench" -m ~/models/MiniCPM5-2B-$cuant.gguf -fa 1 -r 3 -o csv "$@" \
    > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}


# Prefill de 2048 tokens: dura lo bastante para caer en los 35 W sostenidos.
corre pp-q4km     Q4_K_M -t 6 -p 2048 -n 0
corre pp-q4_0     Q4_0   -t 6 -p 2048 -n 0
corre pp-iq4nl    IQ4_NL -t 6 -p 2048 -n 0
corre pp-q4km-b   Q4_K_M -t 6 -p 2048 -n 0

# Afinidad con Q4_0, en orden ABAB.
corre tg-libre    Q4_0 -t 6 -p 0 -n 128
corre tg-0x555    Q4_0 -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128
corre tg-libre-b  Q4_0 -t 6 -p 0 -n 128
corre tg-0x555-b  Q4_0 -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128

echo "hecho: $OUT" | tee -a "$LOG"
