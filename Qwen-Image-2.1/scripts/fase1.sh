#!/bin/bash
# Fase 1: velocidad y memoria. Un prompt y una semilla; cada fila cambia UNA variable respecto a "base".
cd "$(dirname "$0")/.."
B=scripts/bench.sh

# Calentamiento: carga los pesos en la caché de página para que ninguna fila pague la lectura del HDD
$B _calentamiento calentamiento Q4_0-normal 2 anuncio 512 512 > /dev/null

$B fase1 base     Q4_0-normal     25 anuncio
$B fase1 fa       Q4_0-normal     25 anuncio -- --diffusion-fa
$B fase1 p20      Q4_0-normal     20 anuncio
$B fase1 p15      Q4_0-normal     15 anuncio
$B fase1 q4k      Q4_K-normal     25 anuncio
$B fase1 q50      Q5_0-normal     25 anuncio
$B fase1 res14mp  Q4_0-normal     25 anuncio 896 1568
$B fase1 res24mp  Q4_0-normal     25 anuncio 1152 2048
