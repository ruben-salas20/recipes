#!/usr/bin/env bash
# ai-lab, host b11940. Primero 2.1 (velocidad con contexto largo) y después 3.1 (KL), sin solaparse.
#   2.1: QAD-Q4_0, llama-bench -d 131072,245760 -p 512 -n 128 -r 2, caché f16 / q8_0 / f16 (ABA).
#   3.1: llama-perplexity -c 512 --chunks 100 sobre wiki.test.raw; referencia BF16; KL de las tres candidatas.
# Uso: scp a ~/otros/pruebas/lfm3-2.1/ y, en tmux:
#   curl -s localhost:8080/unload; bash ~/otros/pruebas/lfm3-2.1/2.1-3.1-ailab.sh
set -uo pipefail
BIN=~/.local/bin; MD=/data/ai-lab/models/llm
M() { echo $MD/LFM3-1.7B-$1-b3f2ae5.gguf; }
O21=~/otros/pruebas/lfm3-2.1/resultados; O31=~/otros/pruebas/lfm3-3.1/resultados
TEXTO=~/otros/pruebas/lfm3-3.1/wiki.test.raw; BASE=~/otros/pruebas/lfm3-3.1/base-bf16.kld
mkdir -p $O21 $O31
{ date -Is; $BIN/llama-bench --version 2>&1 | tail -2; nvidia-smi --query-gpu=memory.used --format=csv,noheader; free -m; } > $O21/entorno.log 2>&1

# 2.1
i=0
for kv in f16 q8_0 f16; do
  i=$((i+1))
  echo "$i-$kv inicio: $(date +%T)" >> $O21/entorno.log
  $BIN/llama-bench -m $(M QAD-Q4_0) -ngl 99 -ctk $kv -ctv $kv -p 512 -n 128 -d 131072,245760 -r 2 -o csv \
    > $O21/bench-$i-$kv.csv 2> $O21/bench-$i-$kv.log
  echo "$i-$kv fin: $(date +%T)" >> $O21/entorno.log
done
echo "hecho: $(date -Is)" >> $O21/entorno.log

# 3.1
{ date -Is; sha256sum $TEXTO; } > $O31/entorno.log
$BIN/llama-perplexity -m $(M BF16) -ngl 99 -c 512 --chunks 100 -f $TEXTO --kl-divergence-base $BASE > $O31/BF16.log 2>&1
echo "BF16: $(grep -m1 'Final estimate' $O31/BF16.log)" >> $O31/entorno.log
for q in QAD-Q4_0 Q4_K_M Q8_0; do
  $BIN/llama-perplexity -m $(M $q) -ngl 99 --kl-divergence-base $BASE --kl-divergence > $O31/$q.log 2>&1
  echo "$q: $(grep -m1 -E 'Mean +KLD' $O31/$q.log | tr -s ' ')" >> $O31/entorno.log
done
ls -l $BASE >> $O31/entorno.log; rm -f $BASE
echo "hecho: $(date -Is)" >> $O31/entorno.log
