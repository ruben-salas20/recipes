#!/usr/bin/env bash
# Paso 2.1: barrido -ub x -ncmoe del 24B. Corre dentro del contenedor llama-swap:
#   docker exec llama-swap bash /hf/hub/pruebas/2.1-ub-ncmoe.sh
# Antes: GPU libre (curl -s localhost:8080/unload) y nadie usando el chat.
set -uo pipefail
MODELO=/models/pruebas/LFM2.5-24B-A2B-QAD-Q4_0.gguf
OUT=/hf/hub/pruebas/2.1-ub-ncmoe
mkdir -p "$OUT"
LOG=$OUT/entorno.log

{
  echo "fecha: $(date -Is)"
  llama-server --version 2>&1 | tail -2
  nvidia-smi --query-gpu=name,memory.used,memory.total,pcie.link.gen.max,pcie.link.width.current --format=csv
  nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv
} > "$LOG" 2>&1

# A. ¿Cabe con 128k? Arranca el servidor real con cada combinación y anota los búferes.
echo "ub,ncmoe,cabe,modelo_cuda_mib,kv_cuda_mib,compute_cuda_mib,vram_usada_mib" > "$OUT/cabe.csv"
for ub in 512 1024 2048; do
  for nc in 30 31 32; do
    slog=$OUT/server-ub$ub-nc$nc.log
    llama-server --host 127.0.0.1 --port 8090 -m "$MODELO" -ngl 99 -ncmoe $nc -np 1 \
      --ctx-size 131072 -ctk q8_0 -ctv q8_0 -fa on -fit off -b 2048 -ub $ub -v > "$slog" 2>&1 &
    pid=$!
    cabe=no; vram=
    for _ in $(seq 1 180); do
      if curl -sf localhost:8090/health >/dev/null 2>&1; then
        cabe=si; vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits); break
      fi
      kill -0 $pid 2>/dev/null || break
      sleep 1
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    mod=$(grep -m1 -oP 'CUDA0 model buffer size = +\K[0-9.]+' "$slog")
    kv=$(grep -m1 -oP 'CUDA0 KV buffer size = +\K[0-9.]+' "$slog")
    cmp=$(grep -m1 -oP 'CUDA0 compute buffer size = +\K[0-9.]+' "$slog")
    echo "$ub,$nc,$cabe,$mod,$kv,$cmp,$vram" | tee -a "$OUT/cabe.csv"
    sleep 3
  done
done

# B. Velocidad. Un proceso por -ncmoe (recarga el modelo); los -ub van dentro.
for nc in 30 31 32; do
  llama-bench -m "$MODELO" -ngl 99 -ncmoe $nc -ctk q8_0 -ctv q8_0 -fa on -b 2048 \
    -ub 512,1024,2048 -p 512,4096 -n 128 -r 3 -o csv \
    > "$OUT/bench-nc$nc.csv" 2> "$OUT/bench-nc$nc.log"
done
echo "hecho: $OUT" | tee -a "$LOG"
