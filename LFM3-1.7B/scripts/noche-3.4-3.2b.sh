#!/usr/bin/env bash
# Tanda nocturna en ai-lab (host b11940, Q4_K_M, todo en GPU, 262144 de contexto, caché f16).
#   3.4: extraer-json, resumir y traducir, 3 pasadas cada una, muestreo de la tarjeta, max_tokens 8192.
#   3.2b-A: mini-bench, 3 pasadas, max_tokens 32768, repeat-penalty 1.1.
#   3.2b-B: igual con repeat-penalty 1.0.
# Pruebas copiadas a ~/otros/pruebas/lfm3-3.4/pruebas-generales (commit 1189f46); mini-bench del clon ~/projects/recetas.
#   scp a ~/otros/pruebas/lfm3-3.4/ y: tmux new -d -s lfm3-noche 'bash ~/otros/pruebas/lfm3-3.4/noche-3.4-3.2b.sh'
set -uo pipefail
B=~/otros/pruebas/lfm3-3.4
PG=$B/pruebas-generales; MB=~/projects/recetas/mini-bench-codigo
O34=$B/resultados; O32=~/otros/pruebas/lfm3-3.2b/resultados
GGUF=/data/ai-lab/models/llm/LFM3-1.7B-Q4_K_M-b3f2ae5.gguf
UV=~/.local/bin/uv; URL=http://127.0.0.1:8090/v1
CARTA="--temperature 0.1 --top-k 50 --repeat-penalty 1.1"
mkdir -p $O34 $O32
LOG=$O34/entorno.log
log() { echo "$(date +%T) $*" | tee -a $LOG; }
curl -s localhost:8080/unload > /dev/null
~/.local/bin/llama-server --host 127.0.0.1 --port 8090 -m $GGUF -ngl 99 -np 1 -c 262144 > $B/server-noche.log 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null' EXIT
until curl -sf localhost:8090/health > /dev/null; do kill -0 $pid || exit 1; sleep 1; done
{ date -Is; sha256sum $GGUF; ~/.local/bin/llama-server --version 2>&1 | tail -2 | head -1; nvidia-smi --query-gpu=memory.used --format=csv,noheader; } >> $LOG 2>&1

for p in 1 2 3; do
  cd $PG/extraer-json && python3 run_bench.py --base-url $URL --model lfm3-q4km $CARTA --out $O34/json-p$p.json > $O34/json-p$p.log 2>&1
  log "json p$p: $(grep -m1 -i 'nota media' $O34/json-p$p.log)"
  cd $PG/resumir && python3 run_bench.py --base-url $URL --model lfm3-q4km $CARTA --out $O34/resumir-p$p.json > $O34/resumir-p$p.log 2>&1
  log "resumir p$p: $(grep -m1 -i 'aprobados' $O34/resumir-p$p.log)"
  cd $PG/traducir && $UV run -q --no-project --with sacrebleu python run_bench.py --base-url $URL --model lfm3-q4km $CARTA --out $O34/traducir-p$p.json > $O34/traducir-p$p.log 2>&1
  log "traducir p$p: $(grep -m1 -i 'chrf' $O34/traducir-p$p.log)"
done

cd $MB
for t in A B; do
  rp=1.1; [ $t = B ] && rp=1.0
  for p in 1 2 3; do
    $UV run -q --no-project --with pytest python run_bench.py --base-url $URL --model lfm3-q4km-32k-rp$rp \
      --temperature 0.1 --top-k 50 --repeat-penalty $rp --max-tokens 32768 --out $O32/$t-p$p.json > $O32/$t-p$p.log 2>&1
    log "3.2b $t (rp $rp) p$p: $(grep -m1 Aprobadas $O32/$t-p$p.log)"
  done
done
gzip -f $B/server-noche.log
log "hecho"
