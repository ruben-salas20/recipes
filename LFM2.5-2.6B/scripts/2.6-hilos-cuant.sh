#!/usr/bin/env bash
# Paso 2.6: hilos con afinidad y QAD-Q4_0 frente a Q4_K_M (con y sin reempaquetado) de LFM2.5-2.6B en el
# portátil. Portátil en reposo y enchufado:
#   bash LFM2.5-2.6B/scripts/2.6-hilos-cuant.sh
# Espera a que el paquete baje de 55 °C antes de cada corrida.
# Máscaras: CPUs 0-11 = núcleos P con HT (pares 0-1, 2-3...), 12-15 = núcleos E.
#   0x5 = 2 núcleos P, 0x55 = 4, 0x555 = 6, 0x5555 = 6 P + 2 E (CPUs 12 y 14).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
OUT=bench/2.6-hilos-cuant
mkdir -p "$OUT"
LOG=$OUT/entorno.log

temp() { sensors 2>/dev/null | grep -m1 'Package id 0' | grep -oP '\+\K[0-9.]+' | head -1; }
enfria() { while (( $(temp | cut -d. -f1) > 55 )); do sleep 5; done; }

{
  echo "fecha: $(date -Is)"
  echo "encendido: $(uptime -p)"
  echo "ac: $(cat /sys/class/power_supply/ADP0/online 2>/dev/null)"
  echo "perfil: $(powerprofilesctl get 2>/dev/null)"
  sha256sum ~/models/LFM2.5-2.6B-*.gguf
} > "$LOG" 2>&1

corre() {
  local nombre=$1 cuant=$2; shift 2
  enfria
  echo "$nombre: inicio $(date +%T), $(temp) °C" | tee -a "$LOG"
  "$BIN/llama-bench" -m ~/models/LFM2.5-2.6B-$cuant.gguf -fa 1 -r 3 -o csv "$@" \
    > "$OUT/$nombre.csv" 2> "$OUT/$nombre.log"
  echo "$nombre: fin $(date +%T), $(temp) °C" | tee -a "$LOG"
}

# A. Hilos (decode, Q4_K_M)
corre tg-t2     Q4_K_M -t 2 -C 0x5    --cpu-strict 1 -p 0 -n 128
corre tg-t4     Q4_K_M -t 4 -C 0x55   --cpu-strict 1 -p 0 -n 128
corre tg-t6     Q4_K_M -t 6 -C 0x555  --cpu-strict 1 -p 0 -n 128
corre tg-t8     Q4_K_M -t 8 -C 0x5555 --cpu-strict 1 -p 0 -n 128
corre tg-t6-b   Q4_K_M -t 6 -C 0x555  --cpu-strict 1 -p 0 -n 128

# B. Cuantización y reempaquetado (decode y prefill largo)
for c in Q4_K_M QAD-Q4_0; do
  for rp in 1 0; do
    corre "tg-$c-repack$rp" $c -t 6 -C 0x555 --cpu-strict 1 --repack $rp -p 0 -n 128
    corre "pp-$c-repack$rp" $c -t 6 -C 0x555 --cpu-strict 1 --repack $rp -p 2048 -n 0
  done
done

echo "hecho: $OUT" | tee -a "$LOG"
