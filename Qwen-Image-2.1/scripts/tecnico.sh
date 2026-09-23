#!/bin/bash
# Frente técnico/académico: imágenes sin texto, receta rápida (flash attention, 15 pasos), 2 semillas por tema.
cd "$(dirname "$0")/.."
B=scripts/bench.sh
export PROMPTS=prompts/tecnico.tsv

$B _calentamiento calentamiento Q4_0-normal 2 corazon 512 512 > /dev/null

for id in $(tail -n +2 "$PROMPTS" | cut -f1); do
  for s in 42 7; do
    SEED=$s $B tecnico rapida Q4_0-normal 15 "$id" -- --diffusion-fa
  done
done
