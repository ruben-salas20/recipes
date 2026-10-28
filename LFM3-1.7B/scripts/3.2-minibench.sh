#!/usr/bin/env bash
# Paso 3.2: mini-bench, 3 pasadas de QAD-Q4_0 y de Q4_K_M, entero en ai-lab. Servidor en el host (b11940: la imagen de
# llama-swap aún no trae LFM3), puerto 8090; benchmark desde el clon ~/projects/recetas; pytest de un entorno de uv.
# Configuración de la receta de ai-lab (2.0, 2.1): todo en la GPU, 262144 de contexto, caché f16, -np 1.
# Muestreo de la tarjeta (decisión 4); max_tokens 8192 por defecto, como las recetas anteriores.
#   scp a ~/otros/pruebas/lfm3-3.2/ y: tmux new -d -s lfm3-32 'bash ~/otros/pruebas/lfm3-3.2/3.2-minibench.sh'
set -uo pipefail
MB=~/projects/recetas/mini-bench-codigo
OUT=~/otros/pruebas/lfm3-3.2/resultados
MD=/data/ai-lab/models/llm
UV=~/.local/bin/uv
PUERTO=8090
mkdir -p "$OUT"
curl -s localhost:8080/unload > /dev/null
pid=
trap '[ -n "$pid" ] && kill $pid 2>/dev/null' EXIT
cd "$MB"
for q in QAD-Q4_0 Q4_K_M; do
  nombre=lfm3-1.7b-$(echo $q | tr 'A-Z_' 'a-z-')
  gguf=$MD/LFM3-1.7B-$q-b3f2ae5.gguf
  ~/.local/bin/llama-server --host 127.0.0.1 --port $PUERTO -m $gguf -ngl 99 -np 1 -c 262144 > "$OUT/server-$q.log" 2>&1 &
  pid=$!
  until curl -sf localhost:$PUERTO/health > /dev/null; do kill -0 $pid || exit 1; sleep 1; done
  { echo "$nombre: $(date -Is)"; sha256sum $gguf; ~/.local/bin/llama-server --version 2>&1 | tail -2 | head -1;
    nvidia-smi --query-gpu=memory.used --format=csv,noheader; } >> "$OUT/entorno.log" 2>&1
  for p in 1 2 3; do
    $UV run -q --no-project --with pytest python run_bench.py --base-url http://127.0.0.1:$PUERTO/v1 --model "$nombre" \
      --temperature 0.1 --top-k 50 --repeat-penalty 1.1 --out "$OUT/$nombre-p$p.json" > "$OUT/$nombre-p$p.log" 2>&1
    echo "$nombre p$p: $(grep -m1 Aprobadas "$OUT/$nombre-p$p.log") $(date +%T)" >> "$OUT/entorno.log"
  done
  kill $pid; wait $pid 2>/dev/null; pid=
  gzip -f "$OUT/server-$q.log"
done
echo "hecho: $(date -Is)" >> "$OUT/entorno.log"
