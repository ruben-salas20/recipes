#!/usr/bin/env bash
# 3.3: Pi, 3 tareas × 3 pasadas, aislado con bwrap en el portátil, contra el host de ai-lab (b11940, Q4_K_M, todo en
# GPU, 128k, caché f16, muestreo de la tarjeta) por un túnel en localhost:18090. Espera a que acaben las tandas de
# ai-lab (tmux lfm3-json32k y lfm3-errata).
#   bash LFM3-1.7B/scripts/3.3-pi.sh <carpeta de bench/> [ruta de pi] [modelo: lfm3-1.7b o lfm3-1.7b-32k]
# lfm3-1.7b: maxTokens 16384 por turno (modelos-lfm3.json); lfm3-1.7b-32k: 32768 (modelos-lfm3-32k.json).
set -uo pipefail
cd "$(dirname "$0")/.."
R=$(readlink -f ..)
D=bench/$1; PI=${2:-pi}; M=${3:-lfm3-1.7b}; mkdir -p $D
J=modelos-lfm3.json; [ $M = lfm3-1.7b-32k ] && J=modelos-lfm3-32k.json
GGUF=/data/ai-lab/models/llm/LFM3-1.7B-Q4_K_M-b3f2ae5.gguf
SRV="-m $GGUF -ngl 99 -np 1 -c 131072 --temp 0.1 --top-k 50 --repeat-penalty 1.1"
while ssh ai-lab 'tmux has-session -t lfm3-json32k 2>/dev/null || tmux has-session -t lfm3-errata 2>/dev/null'; do sleep 60; done
ssh ai-lab "curl -s localhost:8080/unload >/dev/null; nohup ~/.local/bin/llama-server --host 127.0.0.1 --port 8090 $SRV > ~/otros/pruebas/lfm3-3.3-server.log 2>&1 < /dev/null & echo \$! > ~/otros/pruebas/lfm3-3.3.pid"
ssh -f -N -o ExitOnForwardFailure=yes -L 18090:127.0.0.1:8090 ai-lab
TUNEL=$(pgrep -n -f "[1]8090:127.0.0.1:8090")
for _ in $(seq 1 180); do curl -sf localhost:18090/health >/dev/null && break; sleep 1; done
{ echo "fecha: $(date -Is)"; echo "servidor (ai-lab): $SRV"; ssh ai-lab "~/.local/bin/llama-server --version 2>&1 | head -1; sha256sum $GGUF | cut -c1-16; nvidia-smi --query-gpu=memory.used --format=csv,noheader";
  echo "pi: $($PI --version)"; echo "ac: $(cat /sys/class/power_supply/ADP0/online)"; } > $D/entorno.log 2>&1
PI_MODELS=$R/prueba-agente-pi/3.3/$J PI_BIN=$PI bash $R/prueba-agente-pi/3.3/correr.sh 3 $M > $D/correr.log 2>&1
grep "^$M," $R/prueba-agente-pi/3.3/resultados.csv > $D/resultados.csv && sed -i "/^$M,/d" $R/prueba-agente-pi/3.3/resultados.csv
mkdir -p $D/runs && mv $R/prueba-agente-pi/3.3/runs/$M-t* $D/runs/
ssh ai-lab 'kill $(cat ~/otros/pruebas/lfm3-3.3.pid); rm -f ~/otros/pruebas/lfm3-3.3.pid'; scp -q ai-lab:otros/pruebas/lfm3-3.3-server.log $D/server.log; gzip -f $D/server.log
kill $TUNEL 2>/dev/null
echo "hecho: $(date -Is); $(awk -F, '{split($5,v,"/"); split($6,o,"/"); a+=(v[1]==v[2] && o[1]==o[2] && o[2]>0 && $7=="intactos")} END{print a"/"NR" aprobadas"}' $D/resultados.csv)" >> $D/entorno.log
