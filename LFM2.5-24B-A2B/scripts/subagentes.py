#!/usr/bin/env python3
"""Pasos 2.1d y 2.2g: una sesión principal larga que cede el servidor a un subagente y luego retoma.

Cliente de un llama-server ya arrancado (lo arrancan 2.1d-subagentes.sh y 2.2g-subagentes.sh):
  python3 subagentes.py URL VARIANTE CSV TOKENS_PRINCIPAL TOKENS_SUBAGENTE
Por repetición: (1) la principal procesa su contexto en frío; (2) el subagente procesa el suyo;
(3) la principal retoma con un mensaje corto: se mide cuántos tokens vuelve a procesar y cuánto tarda;
(4) principal y subagente piden a la vez 128 tokens: se mide el tiempo de cada una.
"""
import csv, glob, json, os, sys, threading, time, urllib.request

URL, VARIANTE, CSV = sys.argv[1], sys.argv[2], sys.argv[3]
N_PRINCIPAL, N_SUB = int(sys.argv[4]), int(sys.argv[5])
REPS = 2


def post(ruta, cuerpo):
    req = urllib.request.Request(URL + ruta, data=json.dumps(cuerpo).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3600) as r:
        return json.load(r)


def completa(tokens, n):
    t0 = time.time()
    r = post("/completion", {"prompt": tokens, "n_predict": n, "cache_prompt": True, "temperature": 0})
    return r, time.time() - t0


def texto(patron):
    # Fuentes de la biblioteca estándar de Python: texto real y largo, sin red.
    return "\n".join(open(f, errors="ignore").read() for f in sorted(glob.glob(patron, recursive=True))[:400])


def fila(rep, paso, r, seg):
    t = r["timings"]
    return {"variante": VARIANTE, "rep": rep, "paso": paso, "tokens_procesados": t["prompt_n"],
            "prefill_ms": round(t["prompt_ms"]), "decode_tok_s": round(t["predicted_per_second"], 1),
            "segundos": round(seg, 1)}


def main():
    py = glob.glob(os.path.expanduser("~/.local/share/mise/installs/python/latest/lib/python3*"))
    base = py[0] if py else "/usr/lib/python3*"
    tok = post("/tokenize", {"content": texto(base + "/**/*.py")})["tokens"]
    filas = []
    for rep in range(1, REPS + 1):
        # Cada repetición usa trozos distintos para no heredar caché de la anterior.
        ini = (rep - 1) * (N_PRINCIPAL + N_SUB)
        principal = tok[ini:ini + N_PRINCIPAL]
        sub = tok[ini + N_PRINCIPAL:ini + N_PRINCIPAL + N_SUB]
        r, s = completa(principal, 32); filas.append(fila(rep, "1-principal-frio", r, s))
        principal += post("/tokenize", {"content": r["content"]})["tokens"]
        r, s = completa(sub, 64); filas.append(fila(rep, "2-subagente", r, s))
        sub += post("/tokenize", {"content": r["content"]})["tokens"]
        principal += post("/tokenize", {"content": "\n\nResumen del subagente: hecho. Sigue con el siguiente paso."})["tokens"]
        r, s = completa(principal, 32); filas.append(fila(rep, "3-principal-retoma", r, s))
        principal += post("/tokenize", {"content": r["content"] + "\nContinúa."})["tokens"]
        sub += post("/tokenize", {"content": "\nContinúa."})["tokens"]
        res = {}
        hilos = [threading.Thread(target=lambda k, t: res.__setitem__(k, completa(t, 128)), args=(k, t))
                 for k, t in (("4-a-la-vez-principal", principal), ("4-a-la-vez-subagente", sub))]
        for h in hilos: h.start()
        for h in hilos: h.join()
        for k in sorted(res): filas.append(fila(rep, k, *res[k]))
        for f in filas[-5:]: print(f, flush=True)
    nuevo = not os.path.exists(CSV)
    with open(CSV, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        if nuevo: w.writeheader()
        w.writerows(filas)


if __name__ == "__main__":
    main()
