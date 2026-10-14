#!/usr/bin/env bash
# Paso 2.2a2: confirma la afinidad en decode (orden inverso al de 2.2a) y registra la frecuencia
# durante el prefill para probar la hipótesis del límite de 35 W. Portátil en reposo y enchufado:
#   bash LFM2.5-24B-A2B/scripts/2.2a2-confirmacion.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2a2-confirmacion
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "rapl: PL1 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)/1000000 )) W, PL2 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw)/1000000 )) W"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
} > "$LOG" 2>&1

# Frecuencia media (MHz) de los núcleos P (CPUs 0-11) y temperatura, una muestra por segundo.
echo "t,corrida,mhz_p,mhz_max_p,temp_c" > "$OUT/frecuencia.csv"
ACTUAL=$OUT/.actual
echo inicio > "$ACTUAL"
(
  while :; do
    f=$(cat /sys/devices/system/cpu/cpu{0..11}/cpufreq/scaling_cur_freq | awk '{s+=$1; if($1>m)m=$1} END{printf "%.0f,%.0f", s/NR/1000, m/1000}')
    echo "$(date +%s),$(cat "$ACTUAL"),$f,$(temp)" >> "$OUT/frecuencia.csv"
    sleep 1
  done
) &
MUESTREO=$!
trap 'kill $MUESTREO 2>/dev/null; rm -f "$ACTUAL"' EXIT

corre() {
  local nombre=$1; shift
  echo "$nombre" > "$ACTUAL"
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -r 5 -o csv "$@" > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

corre tg-t6-0x555     -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128
corre tg-t6-libre     -t 6 -p 0 -n 128
corre tg-t6-0x555-b   -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128

corre pp-t6-0x555     -t 6 -C 0x555 --cpu-strict 1 -p 512 -n 0
corre pp-t12-0xFFF    -t 12 -C 0xFFF --cpu-strict 1 -p 512 -n 0

echo "hecho: $OUT" | tee -a "$LOG"
