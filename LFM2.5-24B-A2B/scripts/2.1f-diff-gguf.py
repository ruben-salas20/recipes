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
