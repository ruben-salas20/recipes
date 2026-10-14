#!/usr/bin/env bash
# Paso 2.0: tg128 de LFM2.5-2.6B en el portátil. Uso: ram-asimetrica.sh <etiqueta> (normal | mem16g)
set -euo pipefail
ETIQ=${1:?etiqueta: normal o mem16g}
BIN=~/.local/opt/llama.cpp/cpu
MODELO=~/models/LFM2.5-2.6B-Q4_K_M.gguf
OUT=$(dirname "$0")/../bench/2.0-ram-asimetrica
LOG=$OUT/$ETIQ.log

{
  echo "fecha: $(date -Is)"
  echo "kernel: $(uname -r)"
  echo "cmdline: $(cat /proc/cmdline)"
  grep -E 'MemTotal|MemAvailable' /proc/meminfo
  echo "corriente: $(cat /sys/class/power_supply/A*/online 2>/dev/null || echo ?)"
  echo "perfil: $(powerprofilesctl get 2>/dev/null || echo ?)"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  echo "sha256: $(sha256sum "$MODELO" | cut -c1-16)"
  "$BIN/llama-bench" --version 2>&1 | tail -2
} > "$LOG"

# Tres tandas seguidas para ver la variación entre cargas, no solo entre repeticiones.
for i in 1 2 3; do
  "$BIN/llama-bench" -m "$MODELO" -t 6 -fa 1 -p 0 -n 128 -r 5 -o csv \
    | { [ "$i" = 1 ] && cat || tail -n +2; } >> "$OUT/$ETIQ.csv" 2>>"$LOG"
done
echo "hecho: $OUT/$ETIQ.csv" | tee -a "$LOG"
