#!/usr/bin/env python3
"""Paso 2.3a: MiniCPM5-2B en ai-lab sin borrador, con ngram-mod y con DSpark a varios p-min.

Corre dentro del contenedor llama-swap (GPU libre: curl -s localhost:8080/unload):
  docker exec llama-swap python3 /hf/hub/pruebas/2.3a-especulativa.py
Cada configuración arranca su llama-server en el puerto 8090 y resuelve 3 tareas del mini-bench
2 veces, con el muestreo y el razonamiento de minicpm5-2b-razona.
"""
import csv, json, os, subprocess, sys, time, urllib.request
from datetime import datetime

DIR = "/hf/hub/pruebas"
OUT = f"{DIR}/2.3a-especulativa"
MODELO = "/hf/hub/models--bartowski--MiniCPM5-2B-GGUF/snapshots/31fee0334c4ed9f1e079afe586ba30cb83e0f883/MiniCPM5-2B-Q4_K_M.gguf"
BORRADOR = "/hf/hub/models--openbmb--MiniCPM5-2B-DSpark-GGUF/snapshots/a261d2b4abc9c9ebfbad2af8a817a09802fc4ca3/MiniCPM5-2.6B-DSpark.gguf"
PUERTO = 8090
REPS = 2
MAX_TOKENS = 2048
SISTEMA = ("Eres un programador experto en Python. Responde solo con el código completo "
           "dentro de un único bloque ```python```. No escribas nada fuera del bloque.")

BASE = ["llama-server", "--host", "127.0.0.1", "--port", str(PUERTO), "-m", MODELO, "-fa", "on",
        "-ngl", "99", "-np", "1", "--ctx-size", "65536", "-ctk", "q8_0", "-ctv", "q8_0",
        "--reasoning", "on", "-fit", "off"]
DSPARK = ["-md", BORRADOR, "-ngld", "99", "-ctkd", "q8_0", "-ctvd", "q8_0",
          "--spec-draft-n-max", "9", "--spec-draft-n-min", "0"]
CONFIGS = {
    "sin-borrador": [],
    "ngram-mod": ["--spec-type", "ngram-mod"],
    "dspark-p0.0": DSPARK + ["--spec-type", "draft-dspark"],
    "dspark-p0.3": DSPARK + ["--spec-type", "draft-dspark", "--spec-draft-p-min", "0.3"],
    "dspark-p0.5": DSPARK + ["--spec-type", "draft-dspark", "--spec-draft-p-min", "0.5"],
    "dspark-p0.7": DSPARK + ["--spec-type", "draft-dspark", "--spec-draft-p-min", "0.7"],
    "ngram-mod+dspark-p0.0": DSPARK + ["--spec-type", "ngram-mod,draft-dspark"],
}


def vram():
    return subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                          capture_output=True, text=True).stdout.strip()


def pide(tarea):
    cuerpo = {"messages": [{"role": "system", "content": SISTEMA}, {"role": "user", "content": tarea}],
              "temperature": 1.0, "top_p": 0.95, "min_p": 0.0, "max_tokens": MAX_TOKENS}
    req = urllib.request.Request(f"http://127.0.0.1:{PUERTO}/v1/chat/completions",
                                 data=json.dumps(cuerpo).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def main():
    os.makedirs(OUT, exist_ok=True)
    tareas = json.load(open(f"{DIR}/2.3a-tareas.json"))
    solo = sys.argv[1:] or list(CONFIGS)
    with open(f"{OUT}/entorno.log", "a") as f:
        f.write(f"fecha: {datetime.now().isoformat()}\n")
        f.write(subprocess.run(["llama-server", "--version"], capture_output=True, text=True).stderr)
        f.write(f"vram usada al empezar: {vram()} MiB\n")
    nuevo = not os.path.exists(f"{OUT}/resultados.csv")
    salida = open(f"{OUT}/resultados.csv", "a", newline="")
    w = csv.writer(salida)
    if nuevo:
        w.writerow(["config", "tarea", "rep", "prompt_n", "prompt_tps", "predicted_n", "predicted_tps",
                    "draft_n", "draft_n_accepted", "finish_reason", "vram_mib"])
    for nombre in solo:
        log = open(f"{OUT}/server-{nombre}.log", "w")
        p = subprocess.Popen(BASE + CONFIGS[nombre], stdout=log, stderr=subprocess.STDOUT)
        for _ in range(300):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PUERTO}/health", timeout=2)
                break
            except Exception:
                if p.poll() is not None:
                    break
                time.sleep(1)
        if p.poll() is not None:
            print(f"{nombre}: el servidor no arrancó", flush=True)
            continue
        v = vram()
        pide("Di hola.")  # calentamiento, se descarta
        for nt, (tarea_id, tarea) in enumerate(tareas.items()):
            for rep in range(REPS):
                r = pide(tarea)
                t = r.get("timings", {})
                fila = [nombre, tarea_id, rep, t.get("prompt_n"), round(t.get("prompt_per_second", 0), 1),
                        t.get("predicted_n"), round(t.get("predicted_per_second", 0), 2),
                        t.get("draft_n"), t.get("draft_n_accepted"), r["choices"][0]["finish_reason"], v]
                w.writerow(fila); salida.flush()
                print(",".join(map(str, fila)), flush=True)
        p.terminate(); p.wait()
        time.sleep(3)
    print("hecho", flush=True)


main()
