#!/usr/bin/env python3
"""Pasos 2.3e y 2.5d: prefill de MiniCPM5-2B y LFM2.5-2.6B en ai-lab con la receta de 128k (borrador incluido).

Corre dentro del contenedor llama-swap (GPU libre: curl -s localhost:8080/unload):
  docker exec llama-swap python3 /hf/hub/pruebas/2.3e-2.5d-prefill.py
Para cada modelo arranca llama-server con los flags de prueba-agente-pi/3.3/servidor-128k.sh, recorta un texto
a N tokens exactos y lo manda 3 veces sin caché de prompt, con n_predict 1. Anota timings.prompt_per_second.
"""
import csv, glob, json, os, subprocess, time, urllib.request
from datetime import datetime

H = "/hf/hub"
OUT = f"{H}/pruebas/2.3e-2.5d-prefill"
PUERTO = 8090
TAMANOS = [512, 4096, 16384, 65536]
REPS = 3
COMUN = ["--spec-type", "draft-dspark", "--spec-draft-n-max", "9", "--spec-draft-n-min", "0",
         "-fa", "on", "-ngl", "99", "-ngld", "99", "-np", "1", "--ctx-size", "131072"]
MODELOS = {
    "minicpm5-2b": ["-m", f"{H}/models--bartowski--MiniCPM5-2B-GGUF/snapshots/31fee0334c4ed9f1e079afe586ba30cb83e0f883/MiniCPM5-2B-Q4_K_M.gguf",
                    "-md", f"{H}/models--openbmb--MiniCPM5-2B-DSpark-GGUF/snapshots/a261d2b4abc9c9ebfbad2af8a817a09802fc4ca3/MiniCPM5-2.6B-DSpark.gguf",
                    "--spec-draft-p-min", "0.5", "-ub", "256", "-b", "1024",
                    "-ctk", "q8_0", "-ctv", "q8_0", "-ctkd", "q4_0", "-ctvd", "q4_0", "--reasoning", "on"] + COMUN,
    "lfm2.5-2.6b": ["-m", f"{H}/models--LiquidAI--LFM2.5-2.6B-GGUF/snapshots/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q4_K_M.gguf",
                    "-md", f"{H}/models--LiquidAI--LFM2.5-2.6B-DSpark-GGUF/snapshots/7bc2896af56d82ccc7e156800197408db464d63b/LFM2.5-2.6B-DSpark-Q4_K_M.gguf",
                    "-ctk", "q8_0", "-ctv", "q8_0", "-ctkd", "q8_0", "-ctvd", "q8_0",
                    "--no-reasoning-preserve", "--reasoning", "off"] + COMUN,
}


def post(ruta, cuerpo, timeout=900):
    req = urllib.request.Request(f"http://127.0.0.1:{PUERTO}{ruta}", data=json.dumps(cuerpo).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def texto_base():
    # Código y documentación de la imagen: texto variado y real, sin depender de la red.
    partes = []
    for f in sorted(glob.glob("/app/**/*.py", recursive=True) + glob.glob("/app/*.md")):
        try:
            partes.append(open(f, errors="ignore").read())
        except OSError:
            pass
    return "\n".join(partes)


def main():
    os.makedirs(OUT, exist_ok=True)
    base = texto_base()
    filas = []
    for nombre, flags in MODELOS.items():
        log = open(f"{OUT}/server-{nombre}.log", "w")
        srv = subprocess.Popen(["llama-server", "--host", "127.0.0.1", "--port", str(PUERTO)] + flags,
                               stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(300):
                try:
                    urllib.request.urlopen(f"http://127.0.0.1:{PUERTO}/health", timeout=2)
                    break
                except Exception:
                    time.sleep(1)
            tokens = post("/tokenize", {"content": base})["tokens"]
            while len(tokens) < max(TAMANOS):
                tokens += tokens
            for n in TAMANOS:
                for r in range(REPS):
                    t = post("/completion", {"prompt": tokens[:n], "n_predict": 1, "cache_prompt": False})["timings"]
                    filas.append({"modelo": nombre, "tokens": n, "rep": r + 1, "prompt_n": t["prompt_n"],
                                  "prompt_ms": round(t["prompt_ms"], 1), "pp_tok_s": round(t["prompt_per_second"], 1)})
                    print(filas[-1], flush=True)
        finally:
            srv.terminate(); srv.wait()
            time.sleep(3)
    with open(f"{OUT}/prefill.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        w.writeheader(); w.writerows(filas)
    with open(f"{OUT}/entorno.log", "a") as f:
        f.write(f"hecho: {datetime.now().isoformat()}, texto base {len(base)} caracteres\n")


if __name__ == "__main__":
    main()
