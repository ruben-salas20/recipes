#!/usr/bin/env bash
# 3.2c: ¿la errata `compressir_repeticiones` (tarea 01) es de la cuantización? 10 pasadas de la tarea 01 con Q4_K_M,
# Q8_0 y BF16. Host b11940, todo en GPU, -c 40960, caché f16, muestreo de la tarjeta, max_tokens 32768.
# Espera a que acabe la tanda 3.4b (tmux lfm3-json32k).
#   scp a ~/otros/pruebas/lfm3-3.2c/ y: tmux new -d -s lfm3-errata 'bash ~/otros/pruebas/lfm3-3.2c/3.2c-errata-cuant.sh'
set -uo pipefail
B=~/otros/pruebas/lfm3-3.2c; O=$B/resultados; MB=~/projects/recetas/mini-bench-codigo
UV=~/.local/bin/uv; URL=http://127.0.0.1:8090/v1
mkdir -p $O; LOG=$O/entorno.log
log() { echo "$(date +%T) $*" | tee -a $LOG; }
while tmux has-session -t lfm3-json32k 2>/dev/null; do sleep 60; done
curl -s localhost:8080/unload > /dev/null
~/.local/bin/llama-server --version 2>&1 | tail -2 | head -1 >> $LOG
cd $MB
for q in Q4_K_M Q8_0 BF16; do
  GGUF=/data/ai-lab/models/llm/LFM3-1.7B-$q-b3f2ae5.gguf
  ~/.local/bin/llama-server --host 127.0.0.1 --port 8090 -m $GGUF -ngl 99 -np 1 -c 40960 > $B/server-$q.log 2>&1 &
  pid=$!
  until curl -sf localhost:8090/health > /dev/null; do kill -0 $pid || { log "$q no arrancó"; continue 2; }; sleep 1; done
  log "$q: $(sha256sum $GGUF | cut -c1-16), $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
  for p in $(seq 1 10); do
    $UV run -q --no-project --with pytest python run_bench.py --base-url $URL --model lfm3-$q --tasks 01 \
      --temperature 0.1 --top-k 50 --repeat-penalty 1.1 --max-tokens 32768 --out $O/$q-p$p.json > $O/$q-p$p.log 2>&1
    log "$q p$p: $(grep -m1 Aprobadas $O/$q-p$p.log) $(grep -o 'def [a-z_]*' $O/$q-p$p.json | head -1)"
  done
  kill $pid; wait $pid 2>/dev/null
  gzip -f $B/server-$q.log
done
log "hecho"
