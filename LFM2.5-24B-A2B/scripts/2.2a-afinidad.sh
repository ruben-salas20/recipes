#!/usr/bin/env bash
# Paso 2.2a: afinidad de CPU del 24B en el portátil. Correr con el portátil en reposo y enchufado:
#   bash LFM2.5-24B-A2B/scripts/2.2a-afinidad.sh
# Topología (lscpu): CPUs 0-11 = 6 núcleos P con HT (pares 0-1, 2-3...), 12-15 = 4 núcleos E.
# 0x555 = CPUs 0,2,4,6,8,10 (un hilo por núcleo P); 0xFFF = los 12 hilos P.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=bench/2.2a-afinidad
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "rapl: PL1 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw)/1000000 )) W, PL2 $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw)/1000000 )) W"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "epp: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
  free -m
} > "$LOG" 2>&1

# Orden ABA en cada bloque: repetir la primera configuración al final detecta la deriva por calor.
corre() {
  local nombre=$1; shift
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m "$MODELO" -fa 1 -r 5 -o csv "$@" > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

# Decode (tg128)
corre tg-t6-libre     -t 6 -p 0 -n 128
corre tg-t6-0x555     -t 6 -C 0x555 --cpu-strict 1 -p 0 -n 128
corre tg-t6-libre-b   -t 6 -p 0 -n 128

# Prefill (pp512). llama-bench no tiene -tb: su -t vale para prefill y decode a la vez.
corre pp-t6-libre     -t 6 -p 512 -n 0
corre pp-t6-0x555     -t 6 -C 0x555 --cpu-strict 1 -p 512 -n 0
corre pp-t12-0xFFF    -t 12 -C 0xFFF --cpu-strict 1 -p 512 -n 0
corre pp-t16-libre    -t 16 -p 512 -n 0
corre pp-t6-libre-b   -t 6 -p 512 -n 0

echo "hecho: $OUT" | tee -a "$LOG"
