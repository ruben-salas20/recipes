#!/usr/bin/env bash
# Paso 2.4c: calidad de Q4_K_M, Q4_0 e IQ4_NL de MiniCPM5-2B frente a Q8_0: perplejidad y divergencia KL
# sobre wikitext-2 (100 trozos de 512 tokens). Corre en el host de ai-lab con el llama.cpp del banco
# (b11028, ~/.local/bin), no en el contenedor, que no trae llama-perplexity. GPU libre antes:
#   curl -s localhost:8080/unload; bash /data/ai-lab/cache/huggingface/hub/pruebas/2.4c-calidad.sh
set -uo pipefail
P=/data/ai-lab/cache/huggingface/hub/pruebas
OUT=$P/2.4c-calidad
Q4KM=/data/ai-lab/cache/huggingface/hub/models--bartowski--MiniCPM5-2B-GGUF/snapshots/31fee0334c4ed9f1e079afe586ba30cb83e0f883/MiniCPM5-2B-Q4_K_M.gguf
TEXTO=$P/wiki.test.raw
BASE=$P/minicpm5-2b-q8_0-logits.bin
mkdir -p "$OUT"
{
  echo "fecha: $(date -Is)"
  ~/.local/bin/llama-perplexity --version 2>&1 | tail -2
  nvidia-smi --query-gpu=memory.used --format=csv,noheader
  sha256sum "$TEXTO"
} > "$OUT/entorno.log" 2>&1

COMUN=(-ngl 99 -fa on -c 512 --chunks 100 -f "$TEXTO")
~/.local/bin/llama-perplexity -m $P/MiniCPM5-2B-Q8_0.gguf "${COMUN[@]}" --kl-divergence-base "$BASE" \
  > "$OUT/q8_0.log" 2>&1
for q in Q4_K_M Q4_0 IQ4_NL; do
  m=$P/MiniCPM5-2B-$q.gguf; [ $q = Q4_K_M ] && m=$Q4KM
  ~/.local/bin/llama-perplexity -m "$m" -ngl 99 -fa on --kl-divergence-base "$BASE" --kl-divergence \
    > "$OUT/$q.log" 2>&1
done
rm -f "$BASE"
echo "hecho" >> "$OUT/entorno.log"
