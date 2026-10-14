#!/usr/bin/env bash
# Paso 2.6c: comprueba la perplejidad sospechosa de 2.6b con otro build y otro backend: b11588 en CPU (portátil),
# 10 trozos de 512 de wikitext-2 test, para Q8_0, Q4_K_M y QAD-Q4_0 de LFM2.5-2.6B.
#   bash LFM2.5-2.6B/scripts/2.6c-verifica-calidad.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=~/.local/opt/llama.cpp/cpu
OUT=bench/2.6c-verifica-calidad
mkdir -p "$OUT"
M=~/models/LFM2.5-2.6B-Q8_0.gguf
[ -f $M ] || curl -sL -o $M "https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q8_0.gguf"
{
  echo "fecha: $(date -Is)"
  "$BIN/llama-perplexity" --version 2>&1 | tail -2
  sha256sum ~/models/LFM2.5-2.6B-*.gguf ~/models/datos/wikitext-2-raw/wiki.test.raw
} > "$OUT/entorno.log" 2>&1
for q in Q8_0 Q4_K_M QAD-Q4_0; do
  "$BIN/llama-perplexity" -m ~/models/LFM2.5-2.6B-$q.gguf -t 6 -fa on -c 512 --chunks 10 \
    -f ~/models/datos/wikitext-2-raw/wiki.test.raw > "$OUT/$q.log" 2>&1
done
echo hecho >> "$OUT/entorno.log"
