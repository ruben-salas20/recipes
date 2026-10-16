#!/usr/bin/env bash
# Fase 1.3: BF16 -> GGUF con sd-cli, uno tras otro. Corre en ai-lab, en tmux.
# Salida: un log por tipo, la RAM del sistema cada segundo y convertir.csv.
set -euo pipefail

SD=~/.local/opt/sd.cpp/build/bin/sd-cli
M=/data/ai-lab/models/flux-3-image-klein
OUT=${OUT:-$(cd "$(dirname "$0")/.." && pwd)/bench/1-humo/conversion}
TIPOS=${TIPOS:-"q8_0 q6_K q5_K q4_K"}
mkdir -p "$M/gguf" "$OUT"

# Parámetros reales del transformer, del encabezado del safetensors, para los bits por peso.
PARAMS=$(python3 -I - "$M/model.safetensors" <<'EOF'
import json, struct, sys, math
with open(sys.argv[1], "rb") as f:
    n = struct.unpack("<Q", f.read(8))[0]
    h = json.loads(f.read(n))
print(sum(math.prod(v["shape"]) for k, v in h.items() if k != "__metadata__"))
EOF
)
echo "parametros=$PARAMS" | tee "$OUT/parametros.txt"

CSV="$OUT/convertir.csv"
[ -f "$CSV" ] || echo "tipo,bytes,bits_por_peso,segundos,rss_pico_kb,ram_sistema_pico_mib,sha256" > "$CSV"

for t in $TIPOS; do
  f="$M/gguf/flux-3-image-klein-${t}.gguf"
  if grep -q "^$t," "$CSV"; then echo "$t ya hecho"; continue; fi
  free -m | awk '/^Mem:/{print "antes used_mib=" $3 " available_mib=" $7}' > "$OUT/ram-$t.txt"
  ( while :; do free -m | awk '/^Mem:/{print strftime("%T"), $3, $7; fflush()}'; sleep 1; done ) >> "$OUT/ram-$t.txt" &
  mon=$!
  trap 'kill $mon 2>/dev/null || true' EXIT
  ini=$(date +%s)
  /usr/bin/time -v "$SD" -M convert -m "$M/model.safetensors" -o "$f" --type "$t" -v > "$OUT/conv-$t.log" 2>&1
  fin=$(date +%s)
  kill "$mon"
  rss=$(awk -F': ' '/Maximum resident set size/{print $2}' "$OUT/conv-$t.log")
  pico=$(awk 'NR>1{if($2>m)m=$2}END{print m}' "$OUT/ram-$t.txt")
  bytes=$(stat -c %s "$f")
  bpw=$(python3 -c "print(round($bytes*8/$PARAMS, 3))")
  sha=$(sha256sum "$f" | cut -d' ' -f1)
  echo "$t,$bytes,$bpw,$((fin-ini)),$rss,$pico,$sha" | tee -a "$CSV"
done
echo "conversion ok $(date -Is)"
