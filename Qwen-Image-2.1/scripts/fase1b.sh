#!/bin/bash
# Fase 1b: combinaciones con flash attention, el ganador de la fase 1.
cd "$(dirname "$0")/.."
B=scripts/bench.sh

$B _calentamiento calentamiento Q4_0-normal 2 anuncio 512 512 > /dev/null

$B fase1b fa_p20      Q4_0-normal 20 anuncio           -- --diffusion-fa
$B fase1b fa_p15      Q4_0-normal 15 anuncio           -- --diffusion-fa
$B fase1b fa_res14mp  Q4_0-normal 25 anuncio 896 1568  -- --diffusion-fa
$B fase1b fa_res24mp  Q4_0-normal 25 anuncio 1152 2048 -- --diffusion-fa
