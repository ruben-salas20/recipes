#!/usr/bin/env bash
# Paso 2.1d: subagentes con la receta del 24B en ai-lab. Servidor en el contenedor (puerto 8090), cliente aquí por
# un túnel (18090). Antes: GPU de ai-lab libre.  bash LFM2.5-24B-A2B/scripts/2.1d-subagentes.sh
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=bench/2.1d-subagentes; mkdir -p "$OUT"; LOG=$OUT/entorno.log
RECETA="-m /models/pruebas/LFM2.5-24B-A2B-QAD-Q4_0.gguf --n-gpu-layers 99 --n-cpu-moe 32 -b 2048 -ub 2048 --ctx-size 131072 --cache-type-k q8_0 --cache-type-v q8_0"
IP=$(ssh ai-lab 'docker inspect llama-swap --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"')
ssh -N -o ExitOnForwardFailure=yes -L 18090:$IP:8090 ai-lab & TUNEL=$!
para() { ssh ai-lab 'docker exec llama-swap sh -c "[ -f /tmp/2.1d.pid ] && kill \$(cat /tmp/2.1d.pid); rm -f /tmp/2.1d.pid"'; sleep 5; }
trap 'para; kill $TUNEL' EXIT
ssh ai-lab 'curl -s localhost:8080/unload >/dev/null'
echo "fecha: $(date -Is)" > "$LOG"
for v in "np1-cram8192|-np 1" "np1-cram0|-np 1 --cache-ram 0" "np2-kvu|-np 2 --kv-unified"; do
  IFS='|' read -r nombre flags <<< "$v"
  ssh ai-lab "docker exec -d llama-swap sh -c 'echo \$\$ > /tmp/2.1d.pid; exec llama-server --host 0.0.0.0 --port 8090 $RECETA $flags > /hf/hub/pruebas/2.1d-server-$nombre.log 2>&1'"
  until curl -sf localhost:18090/health >/dev/null 2>&1; do sleep 2; done
  echo "$nombre: inicio $(date +%T)" >> "$LOG"
  ( while sleep 10; do echo "$nombre $(date +%T) $(ssh ai-lab "free -m | awk '/Mem:/{printf \"ram_usada %d \", \$3} /Swap:/{printf \"swap %d \", \$3}'; nvidia-smi --query-gpu=memory.used --format=csv,noheader")"; done ) >> "$OUT/memoria.log" & VIG=$!
  python3 scripts/subagentes.py http://127.0.0.1:18090 "$nombre" "$OUT/resultados.csv" 30000 4000 >> "$LOG" 2>&1
  kill $VIG; para
done
scp -q "ai-lab:/data/ai-lab/cache/huggingface/hub/pruebas/2.1d-server-*.log" "$OUT/"
echo "hecho: $(date -Is)" >> "$LOG"
