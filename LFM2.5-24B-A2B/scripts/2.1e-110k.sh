#!/usr/bin/env bash
# Paso 2.1e: receta del 24B en ai-lab con un prompt de 110 000 tokens. Antes: GPU de ai-lab libre.
#   bash LFM2.5-24B-A2B/scripts/2.1e-110k.sh
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=bench/2.1e-110k; mkdir -p "$OUT"
RECETA="-m /models/pruebas/LFM2.5-24B-A2B-QAD-Q4_0.gguf --n-gpu-layers 99 --n-cpu-moe 32 -b 2048 -ub 2048 -np 1 --ctx-size 131072 --cache-type-k q8_0 --cache-type-v q8_0"
IP=$(ssh ai-lab 'docker inspect llama-swap --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"')
ssh -N -o ExitOnForwardFailure=yes -L 18090:$IP:8090 ai-lab & TUNEL=$!
trap 'ssh ai-lab "docker exec llama-swap sh -c \"kill \\\$(cat /tmp/2.1e.pid); rm -f /tmp/2.1e.pid\""; kill $TUNEL' EXIT
ssh ai-lab 'curl -s localhost:8080/unload >/dev/null'
ssh ai-lab "docker exec -d llama-swap sh -c 'echo \$\$ > /tmp/2.1e.pid; exec llama-server --host 0.0.0.0 --port 8090 $RECETA > /hf/hub/pruebas/2.1e-server.log 2>&1'"
until curl -sf localhost:18090/health >/dev/null 2>&1; do sleep 2; done
echo "vram al arrancar: $(ssh ai-lab 'nvidia-smi --query-gpu=memory.used --format=csv,noheader')" > "$OUT/entorno.log"
python3 scripts/2.1e-110k.py http://127.0.0.1:18090 "$OUT/resultado.csv" >> "$OUT/entorno.log" 2>&1
echo "vram al terminar: $(ssh ai-lab 'nvidia-smi --query-gpu=memory.used --format=csv,noheader')" >> "$OUT/entorno.log"
scp -q ai-lab:/data/ai-lab/cache/huggingface/hub/pruebas/2.1e-server.log "$OUT/server.log"
