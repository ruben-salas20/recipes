#!/usr/bin/env python3
"""Paso 2.5b: como 2.5a, con temperature 0: el texto sale igual en todas las configuraciones y solo cambia la velocidad.

Corre dentro del contenedor llama-swap (GPU libre: curl -s localhost:8080/unload):
  docker exec llama-swap python3 /hf/hub/pruebas/2.5b-temp0.py
Cada configuración arranca su llama-server en el puerto 8090 y resuelve 6 tareas del mini-bench
1 vez, con el muestreo de la entrada lfm2.5-2.6B de llama-swap.
"""
import csv, json, os, subprocess, sys, time, urllib.request
from datetime import datetime

DIR = "/hf/hub/pruebas"
OUT = f"{DIR}/2.5b-temp0"
MODELO = "/hf/hub/models--LiquidAI--LFM2.5-2.6B-GGUF/snapshots/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q4_K_M.gguf"
BORRADOR = "/hf/hub/models--LiquidAI--LFM2.5-2.6B-DSpark-GGUF/snapshots/7bc2896af56d82ccc7e156800197408db464d63b/LFM2.5-2.6B-DSpark-Q4_K_M.gguf"
PUERTO = 8090
REPS = 1
MAX_TOKENS = 2048
SISTEMA = ("Eres un programador experto en Python. Responde solo con el código completo "
           "dentro de un único bloque ```python```. No escribas nada fuera del bloque.")

BASE = ["llama-server", "--host", "127.0.0.1", "--port", str(PUERTO), "-m", MODELO, "-fa", "on",
        "-ngl", "99", "-np", "1", "--ctx-size", "96000",
        "--reasoning", "off", "--no-reasoning-preserve", "-fit", "off"]
DSPARK = ["-md", BORRADOR, "-ngld", "99", "--spec-type", "draft-dspark", "--spec-draft-n-min", "0"]
CONFIGS = {
    "sin-borrador": [],
    "dspark-n5": DSPARK + ["--spec-draft-n-max", "5"],
    "dspark-n7": DSPARK + ["--spec-draft-n-max", "7"],
    "dspark-n9": DSPARK + ["--spec-draft-n-max", "9"],
    "dspark-n9-p0.3": DSPARK + ["--spec-draft-n-max", "9", "--spec-draft-p-min", "0.3"],
    "dspark-n9-p0.5": DSPARK + ["--spec-draft-n-max", "9", "--spec-draft-p-min", "0.5"],
}


def vram():
    return subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                          capture_output=True, text=True).stdout.strip()


def pide(tarea):
    cuerpo = {"messages": [{"role": "system", "content": SISTEMA}, {"role": "user", "content": tarea}],
              "temperature": 0.0, "repeat_penalty": 1.1, "max_tokens": MAX_TOKENS}
    req = urllib.request.Request(f"http://127.0.0.1:{PUERTO}/v1/chat/completions",
                                 data=json.dumps(cuerpo).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def main():
    os.makedirs(OUT, exist_ok=True)
    tareas = json.load(open(f"{DIR}/2.5b-tareas.json"))
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
