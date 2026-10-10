#!/bin/bash
# Turbo, fase de configuración: una variable cada vez respecto a "t_base",
# sobre el anuncio (9:16) y el producto (1:1), semilla 42.
cd "$(dirname "$0")/.."
B=scripts/bench.sh
T=/data/ai-lab/models/qwen-image-2.1-turbo
Q4=$T/Qwen-Image-2.1-Turbo-AD-Q4_K.gguf
Q5=$T/Qwen-Image-2.1-Turbo-AD-Q5_K.gguf
# Calendario de 8 pasos del checkpoint (model_index.json → sample_sigmas) más el 0 final
SIG="1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0"

# Resoluciones por nivel: anuncio (9:16) y producto (1:1)
declare -A RES=([1mp:anuncio]="768 1344" [1mp:producto]="1024 1024"
                [14mp:anuncio]="896 1568" [14mp:producto]="1184 1184"
                [24mp:anuncio]="1152 2048" [24mp:producto]="1536 1536")

$B _calentamiento calentamiento "$Q4" 2 anuncio 512 512 -- --diffusion-fa > /dev/null

for p in anuncio producto; do
  $B turbo1 t_base   "$Q4" 8 $p ${RES[14mp:$p]} -- --diffusion-fa --sigmas "$SIG"
  $B turbo1 t_q5     "$Q5" 8 $p ${RES[14mp:$p]} -- --diffusion-fa --sigmas "$SIG"
  $B turbo1 t_1mp    "$Q4" 8 $p ${RES[1mp:$p]}  -- --diffusion-fa --sigmas "$SIG"
  $B turbo1 t_24mp   "$Q4" 8 $p ${RES[24mp:$p]} -- --diffusion-fa --sigmas "$SIG"
  # Sin el calendario propio: comprueba si de verdad hace falta
  $B turbo1 t_sinsig "$Q4" 8 $p ${RES[14mp:$p]} -- --diffusion-fa
done

# Codificador de texto Q8_0 (8,7 GB). Primero con sus pesos en disco, que ahorra RAM porque
# solo se usa una vez por imagen; después en RAM, que puede no caber (~14 GB de pesos).
TE8=/data/ai-lab/models/qwen-image-2.1/Qwen3VL-8B-Instruct-Q8_0.gguf
for p in anuncio producto; do
  LLM=$TE8 $B turbo1 t_te8disk "$Q4" 8 $p ${RES[14mp:$p]} -- --diffusion-fa --sigmas "$SIG" --params-backend "te=disk,diffusion=cpu,vae=cpu"
done
for p in anuncio producto; do
  LLM=$TE8 $B turbo1 t_te8ram  "$Q4" 8 $p ${RES[14mp:$p]} -- --diffusion-fa --sigmas "$SIG"
done
