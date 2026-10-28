#!/usr/bin/env bash
# 3.4b: extraer-json con max_tokens 32768, 3 pasadas. Lo demás igual que 3.4 (host b11940, Q4_K_M, todo en GPU,
# 262144 de contexto, caché f16, muestreo de la tarjeta). Espera a que acabe la tanda nocturna (tmux lfm3-noche).
#   scp a ~/otros/pruebas/lfm3-3.4/ y: tmux new -d -s lfm3-json32k 'bash ~/otros/pruebas/lfm3-3.4/3.4b-json-32k.sh'
set -uo pipefail
B=~/otros/pruebas/lfm3-3.4
PG=$B/pruebas-generales; O=~/otros/pruebas/lfm3-3.4b/resultados
GGUF=/data/ai-lab/models/llm/LFM3-1.7B-Q4_K_M-b3f2ae5.gguf
URL=http://127.0.0.1:8090/v1
mkdir -p $O
LOG=$O/entorno.log
log() { echo "$(date +%T) $*" | tee -a $LOG; }
while tmux has-session -t lfm3-noche 2>/dev/null; do sleep 60; done
curl -s localhost:8080/unload > /dev/null
~/.local/bin/llama-server --host 127.0.0.1 --port 8090 -m $GGUF -ngl 99 -np 1 -c 262144 > $B/server-json32k.log 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null' EXIT
until curl -sf localhost:8090/health > /dev/null; do kill -0 $pid || exit 1; sleep 1; done
{ date -Is; sha256sum $GGUF; ~/.local/bin/llama-server --version 2>&1 | tail -2 | head -1; nvidia-smi --query-gpu=memory.used --format=csv,noheader; } >> $LOG 2>&1

cd $PG/extraer-json
for p in 1 2 3; do
  python3 run_bench.py --base-url $URL --model lfm3-q4km-32k --temperature 0.1 --top-k 50 --repeat-penalty 1.1 \
    --max-tokens 32768 --out $O/json-p$p.json > $O/json-p$p.log 2>&1
  log "json p$p: $(grep -m1 -i 'nota media' $O/json-p$p.log)"
done
gzip -f $B/server-json32k.log
log "hecho"
