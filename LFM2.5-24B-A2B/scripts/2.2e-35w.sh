#!/usr/bin/env bash
# Paso 2.2e: prefill y decode del 24B en el portátil con el límite sostenido a 25 W (de fábrica) y a 35 W,
# en orden 25-35-25. Necesita escribir el límite de intel-rapl-mmio (dura hasta reiniciar):
#   sudo chown ruben /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
#   sudo chmod o+r /sys/class/powercap/intel-rapl:0/energy_uj
#   bash LFM2.5-24B-A2B/scripts/2.2e-35w.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2e-35w
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
LIMITE=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
mkdir -p "$OUT"
LOG=$OUT/entorno.log
[ -r $RAPL ] && [ -w $LIMITE ] || { echo "faltan permisos sobre $RAPL o $LIMITE"; exit 1; }
ORIGINAL=$(cat $LIMITE)

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "límite mmio original: $ORIGINAL uW"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
} > "$LOG" 2>&1

ACTUAL=$OUT/.actual
echo inicio > "$ACTUAL"
echo "t,corrida,vatios,mhz_p,temp_c" > "$OUT/muestras.csv"
(
  e0=$(cat $RAPL); t0=$(date +%s.%N)
  while :; do
    sleep 1
    e1=$(cat $RAPL); t1=$(date +%s.%N)
    w=$(awk -v a=$e0 -v b=$e1 -v s=$t0 -v f=$t1 'BEGIN{d=b-a; if(d<0)d+=2^32; printf "%.1f", d/1e6/(f-s)}')
    mhz=$(cat /sys/devices/system/cpu/cpu{0,2,4,6,8,10}/cpufreq/scaling_cur_freq | awk '{s+=$1} END{printf "%.0f", s/NR/1000}')
    echo "$t1,$(cat "$ACTUAL"),$w,$mhz,$(temp)" >> "$OUT/muestras.csv"
    e0=$e1; t0=$t1
  done
) &
MUESTREO=$!
trap 'kill $MUESTREO 2>/dev/null; echo $ORIGINAL > $LIMITE; rm -f "$ACTUAL"' EXIT

corre() {
  local nombre=$1 vatios=$2; shift 2
  echo $(( vatios * 1000000 )) > $LIMITE
  enfria
  echo "$nombre" > "$ACTUAL"
  echo "$nombre: límite $(( $(cat $LIMITE)/1000000 )) W, inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -t 6 -C 0x555 --cpu-strict 1 -r 3 -o csv "$@" \
    > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
  echo pausa > "$ACTUAL"
}

# pp2048 dura ~90 s: casi todo cae en la fase sostenida, no en la ráfaga de 28 s.
corre pp-25w   25 -p 2048 -n 0
corre pp-35w   35 -p 2048 -n 0
corre pp-25w-b 25 -p 2048 -n 0
corre tg-25w   25 -p 0 -n 128
corre tg-35w   35 -p 0 -n 128

echo "hecho: $OUT, límite devuelto a $ORIGINAL uW" | tee -a "$LOG"
