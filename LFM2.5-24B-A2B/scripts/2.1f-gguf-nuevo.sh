#!/usr/bin/env bash
# Paso 2.1f: GGUF nuevo del 24B (0912d33) frente al medido (f97fc8a). Corre dentro del contenedor llama-swap
# (GPU libre: curl -s localhost:8080/unload). Antes, en el host, descargar el nuevo a pruebas/:
#   curl -L -o .../pruebas/LFM2.5-24B-A2B-QAD-Q4_0-0912d33.gguf \
#     https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-GGUF/resolve/0912d33/LFM2.5-24B-A2B-QAD-Q4_0.gguf
#   docker exec llama-swap bash /hf/hub/pruebas/2.1f-gguf-nuevo.sh
set -uo pipefail
P=/hf/hub/pruebas
VIEJO=$P/LFM2.5-24B-A2B-QAD-Q4_0.gguf
NUEVO=$P/LFM2.5-24B-A2B-QAD-Q4_0-0912d33.gguf
OUT=$P/2.1f-gguf-nuevo
mkdir -p "$OUT"
RECETA="-ngl 99 -ncmoe 32 -b 2048 -ub 2048 -ctk q8_0 -ctv q8_0 -fa 1"
{ echo "fecha: $(date -Is)"; sha256sum "$VIEJO" "$NUEVO"; } > "$OUT/entorno.log"

python3 - "$VIEJO" "$NUEVO" > "$OUT/diferencias.txt" 2>&1 <<'PY'
import sys, hashlib
sys.path.insert(0, "/app/gguf-py")
try:
    from gguf import GGUFReader
except ImportError:
    import subprocess; subprocess.run([sys.executable, "-m", "pip", "install", "-q", "gguf"]); from gguf import GGUFReader
a, b = GGUFReader(sys.argv[1]), GGUFReader(sys.argv[2])
def campos(r):
    d = {}
    for k, f in r.fields.items():
        try: v = f.contents()
        except Exception: v = [bytes(p).hex()[:64] for p in f.parts[-1:]]
        d[k] = v if not isinstance(v, (list, str)) or len(str(v)) < 300 else hashlib.sha256(str(v).encode()).hexdigest()[:16] + f" ({len(str(v))} car.)"
    return d
fa, fb = campos(a), campos(b)
for k in sorted(set(fa) | set(fb)):
    if fa.get(k) != fb.get(k): print("METADATO", k, "|", fa.get(k), "->", fb.get(k))
ta = {t.name: t for t in a.tensors}; tb = {t.name: t for t in b.tensors}
print("tensores", len(ta), len(tb))
distintos = []
for n in ta:
    x, y = ta[n], tb.get(n)
    if y is None: print("FALTA en el nuevo", n); continue
    if x.tensor_type != y.tensor_type or list(x.shape) != list(y.shape):
        print("TIPO/FORMA", n, x.tensor_type.name, list(x.shape), "->", y.tensor_type.name, list(y.shape))
    if bytes(x.data.tobytes()) != bytes(y.data.tobytes()): distintos.append(n)
print("tensores con bytes distintos:", len(distintos))
for n in distintos[:40]: print("  ", n, ta[n].tensor_type.name)
PY

for m in viejo nuevo viejo-b; do
  f=$VIEJO; [ $m = nuevo ] && f=$NUEVO
  llama-bench -m "$f" $RECETA -p 4096 -n 128 -r 3 -o csv > "$OUT/bench-$m.csv" 2> "$OUT/bench-$m.log"
done
for m in viejo nuevo; do
  f=$VIEJO; [ $m = nuevo ] && f=$NUEVO
  llama-perplexity -m "$f" -ngl 99 -ncmoe 32 -fa on -c 512 --chunks 20 -f $P/wiki.test.raw > "$OUT/ppl-$m.log" 2>&1
done
echo "hecho: $(date -Is)" >> "$OUT/entorno.log"
