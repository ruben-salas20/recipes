#!/usr/bin/env python3
"""Paso 2.1e: un prompt de 110 000 tokens al servidor de ai-lab con la receta del 24B.

Lo lanza 2.1e-110k.sh (servidor y túnel). Uso: python3 2.1e-110k.py URL CSV
"""
import csv, glob, json, os, sys, time, urllib.request

URL, CSV = sys.argv[1], sys.argv[2]
N = 110000


def post(ruta, cuerpo):
    req = urllib.request.Request(URL + ruta, data=json.dumps(cuerpo).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=7200) as r:
        return json.load(r)


base = glob.glob(os.path.expanduser("~/.local/share/mise/installs/python/latest/lib/python3*"))[0]
texto = "\n".join(open(f, errors="ignore").read() for f in sorted(glob.glob(base + "/**/*.py", recursive=True))[:1500])
tok = post("/tokenize", {"content": texto})["tokens"][:N]
t0 = time.time()
r = post("/completion", {"prompt": tok, "n_predict": 128, "cache_prompt": False, "temperature": 0})
t = r["timings"]
fila = {"tokens": t["prompt_n"], "prefill_s": round(t["prompt_ms"] / 1000, 1), "prefill_tok_s": round(t["prompt_per_second"], 1),
        "decode_n": t["predicted_n"], "decode_tok_s": round(t["predicted_per_second"], 1), "total_s": round(time.time() - t0, 1)}
print(fila)
with open(CSV, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(fila)); w.writeheader(); w.writerow(fila)
