#!/usr/bin/env bash
# Paso 2.6b: calidad de Q4_K_M y QAD-Q4_0 de LFM2.5-2.6B frente a Q8_0: perplejidad y divergencia KL
# sobre wikitext-2 (100 trozos de 512 tokens). Corre en el host de ai-lab con el llama.cpp del banco
# (b11028, ~/.local/bin), no en el contenedor, que no trae llama-perplexity. GPU libre antes:
#   curl -s localhost:8080/unload; bash /data/ai-lab/cache/huggingface/hub/pruebas/2.6b-calidad.sh
set -uo pipefail
P=/data/ai-lab/cache/huggingface/hub/pruebas
OUT=$P/2.6b-calidad
Q4KM=/data/ai-lab/cache/huggingface/hub/models--LiquidAI--LFM2.5-2.6B-GGUF/snapshots/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q4_K_M.gguf
TEXTO=$P/wiki.test.raw
BASE=$P/lfm25-26b-q8_0-logits.bin
mkdir -p "$OUT"
{
  echo "fecha: $(date -Is)"
  ~/.local/bin/llama-perplexity --version 2>&1 | tail -2
  nvidia-smi --query-gpu=memory.used --format=csv,noheader
  sha256sum "$TEXTO"
} > "$OUT/entorno.log" 2>&1

COMUN=(-ngl 99 -fa on -c 512 --chunks 100 -f "$TEXTO")
~/.local/bin/llama-perplexity -m $P/LFM2.5-2.6B-Q8_0.gguf "${COMUN[@]}" --kl-divergence-base "$BASE" \
  > "$OUT/q8_0.log" 2>&1
for q in Q4_K_M QAD-Q4_0; do
  m=$P/LFM2.5-2.6B-$q.gguf; [ $q = Q4_K_M ] && m=$Q4KM
  ~/.local/bin/llama-perplexity -m "$m" -ngl 99 -fa on --kl-divergence-base "$BASE" --kl-divergence \
    > "$OUT/$q.log" 2>&1
done
rm -f "$BASE"
echo "hecho" >> "$OUT/entorno.log"
