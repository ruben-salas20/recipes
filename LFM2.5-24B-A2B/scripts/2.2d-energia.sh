#!/usr/bin/env bash
# Paso 2.2d: ¿qué frena el prefill del 24B en el portátil, los 35 W o la temperatura? Registra cada segundo
# vatios del paquete (RAPL), frecuencia media de las CPUs usadas y temperatura durante pp512 con 6 y 12 hilos.
# Necesita leer energy_uj: sudo chmod o+r /sys/class/powercap/intel-rapl:0/energy_uj (dura hasta reiniciar).
#   bash LFM2.5-24B-A2B/scripts/2.2d-energia.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2d-energia
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
mkdir -p "$OUT"
LOG=$OUT/entorno.log
[ -r $RAPL ] || { echo "no se puede leer $RAPL"; exit 1; }

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "rapl: PL1 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)/1000000 )) W, PL2 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw)/1000000 )) W"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
} > "$LOG" 2>&1

ACTUAL=$OUT/.actual
CPUS=$OUT/.cpus
echo inicio > "$ACTUAL"; echo 0 > "$CPUS"
echo "t,corrida,vatios,mhz_cpus_usadas,temp_c" > "$OUT/muestras.csv"
(
  e0=$(cat $RAPL); t0=$(date +%s.%N)
  while :; do
    sleep 1
    e1=$(cat $RAPL); t1=$(date +%s.%N)
    w=$(awk -v a=$e0 -v b=$e1 -v s=$t0 -v f=$t1 'BEGIN{d=b-a; if(d<0)d+=2^32; printf "%.1f", d/1e6/(f-s)}')
    mhz=$(for c in $(cat "$CPUS"); do cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq; done | awk '{s+=$1} END{printf "%.0f", s/NR/1000}')
    echo "$t1,$(cat "$ACTUAL"),$w,$mhz,$(temp)" >> "$OUT/muestras.csv"
    e0=$e1; t0=$t1
  done
) &
MUESTREO=$!
trap 'kill $MUESTREO 2>/dev/null; rm -f "$ACTUAL" "$CPUS"' EXIT

corre() {
  local nombre=$1 cpus=$2; shift 2
  enfria
  echo "$cpus" > "$CPUS"; echo "$nombre" > "$ACTUAL"
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -r 5 -o csv "$@" > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
  echo pausa > "$ACTUAL"
}

corre pp-t6-0x555   "0 2 4 6 8 10"            -t 6  -C 0x555 --cpu-strict 1 -p 512 -n 0
corre pp-t12-0xFFF  "0 1 2 3 4 5 6 7 8 9 10 11" -t 12 -C 0xFFF --cpu-strict 1 -p 512 -n 0
corre tg-t6-0x555   "0 2 4 6 8 10"            -t 6  -C 0x555 --cpu-strict 1 -p 0 -n 128

echo "hecho: $OUT" | tee -a "$LOG"
