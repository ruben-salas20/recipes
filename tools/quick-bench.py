#!/usr/bin/env python3
"""Quick benchmark for the text model recipes in this repository.

Starts llama-server with a recipe's flags, then measures prompt processing (prefill) and decode speed
with prompts of several lengths, so decode is also measured with the context already filled. Unlike
llama-bench, it goes through llama-server, so recipes with a draft model (speculative decoding) are
measured as you would actually run them.

Only the Python standard library is needed. Example:

  python3 quick-bench.py minicpm5-2b gpu --models-dir ~/models
  python3 quick-bench.py lfm2.5-24b-a2b cpu --models-dir ~/models --threads 6

At the end it prints a Markdown table you can paste in an issue or a post, and writes the same results,
plus your hardware and llama.cpp version, to a JSON file.
"""
import argparse, datetime, glob, hashlib, json, os, platform, re, shutil, socket, subprocess, sys, sysconfig, time
import urllib.error, urllib.request

# Recipe flags, as published in each recipe's README. Paths are filled in from --models-dir.
# "reference" holds this script's own results on the recipes' test machines (2026-10-14), as (prefill, decode)
# tok/s per prompt length, 0 being the task alone. They are 5-15 % below the llama-bench figures in the recipes:
# here every request goes through llama-server with a chat template and sampling, and runs back to back.
COMMON_CPU = ["-lm", "none", "-np", "1", "-c", "131072", "-fa", "on"]
RECIPES = {
    "lfm2.5-24b-a2b": {
        "gpu": {"model": "LFM2.5-24B-A2B-QAD-Q4_0.gguf",
                "flags": ["-ngl", "99", "-ncmoe", "32", "-b", "2048", "-ub", "2048", "-np", "1", "-c", "131072",
                          "-ctk", "q8_0", "-ctv", "q8_0"]},
        "cpu": {"model": "LFM2.5-24B-A2B-QAD-Q4_0.gguf", "flags": COMMON_CPU},
        "sampling": ["--temp", "0.1", "--top-k", "50", "--repeat-penalty", "1.05"],
        "reference": {"gpu": {"hw": "RTX 3050 6 GB, i5-9400, 16 GB", "mem": "5588 MiB VRAM",
                              "rows": {0: (51.6, 29.9), 4096: (646.8, 29.5), 32768: (752.7, 24.1)}},
                      "cpu": {"hw": "i7-13620H, 24 GB, -t 6 -C 0x555", "mem": "15.9 GB RAM",
                              "rows": {0: (64.3, 25.5), 2048: (69.8, 23.4), 8192: (63.5, 15.9)}}},
    },
    "minicpm5-2b": {
        "gpu": {"model": "MiniCPM5-2B-Q4_K_M.gguf", "draft": "MiniCPM5-2.6B-DSpark.gguf",
                "flags": ["--spec-type", "draft-dspark", "--spec-draft-n-max", "9", "--spec-draft-n-min", "0",
                          "--spec-draft-p-min", "0.5", "-ngl", "99", "-ngld", "99", "-fa", "on", "-np", "1",
                          "-c", "131072", "-ub", "256", "-b", "1024",
                          "-ctk", "q8_0", "-ctv", "q8_0", "-ctkd", "q4_0", "-ctvd", "q4_0", "--reasoning", "on"]},
        "cpu": {"model": "MiniCPM5-2B-IQ4_NL.gguf", "flags": COMMON_CPU + ["--reasoning", "on"]},
        "sampling": ["--temp", "1.0", "--top-p", "0.95", "--min-p", "0.0"],
        "reference": {"gpu": {"hw": "RTX 3050 6 GB, i5-9400, 16 GB", "mem": "5670 MiB VRAM",
                              "rows": {0: (1812.3, 78.6), 4096: (2302.6, 84.9), 32768: (1278.5, 43.6)}},
                      "cpu": {"hw": "i7-13620H, 24 GB, -t 6 -C 0x555", "mem": "8.0 GB RAM",
                              "rows": {0: (109.8, 25.0), 2048: (99.0, 19.4), 8192: (66.4, 10.8)}}},
    },
    "lfm2.5-2.6b": {
        "gpu": {"model": "LFM2.5-2.6B-Q4_K_M.gguf", "draft": "LFM2.5-2.6B-DSpark-Q4_K_M.gguf",
                "flags": ["--spec-type", "draft-dspark", "--spec-draft-n-max", "9", "--spec-draft-n-min", "0",
                          "-ngl", "99", "-ngld", "99", "-fa", "on", "-np", "1", "-c", "131072",
                          "-ctk", "q8_0", "-ctv", "q8_0", "-ctkd", "q8_0", "-ctvd", "q8_0"]},
        "cpu": {"model": "LFM2.5-2.6B-QAD-Q4_0.gguf", "flags": COMMON_CPU},
        "sampling": ["--temp", "0.1", "--top-k", "50", "--repeat-penalty", "1.1"],
        "reference": {"gpu": {"hw": "RTX 3050 6 GB, i5-9400, 16 GB", "mem": "4606 MiB VRAM",
                              "rows": {0: (1282.8, 121.0), 4096: (2477.4, 103.2), 32768: (2108.6, 74.6)}},
                      "cpu": {"hw": "i7-13620H, 24 GB, -t 6 -C 0x555", "mem": "4.2 GB RAM",
                              "rows": {0: (129.5, 24.9), 2048: (95.9, 21.6), 8192: (87.6, 16.0)}}},
    },
}
DEFAULT_SIZES = {"gpu": "0,4096,32768", "cpu": "0,2048,8192"}


def parse_args():
    p = argparse.ArgumentParser(description="Measure prefill and decode speed of a recipe with llama-server.",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__.split("Example:")[1])
    p.add_argument("recipe", choices=sorted(RECIPES))
    p.add_argument("machine", choices=["gpu", "cpu"], help="gpu: the RTX 3050 recipe; cpu: the CPU-only recipe")
    p.add_argument("--models-dir", default=".", help="folder with the GGUF files (default: current folder)")
    p.add_argument("--model", help="path to the main GGUF (overrides --models-dir)")
    p.add_argument("--draft", help="path to the draft GGUF, for GPU recipes that use one")
    p.add_argument("--server", default=shutil.which("llama-server") or "llama-server", help="llama-server binary")
    p.add_argument("--sizes", help="prompt lengths in tokens, comma-separated; 0 sends the coding task alone "
                   "(default: gpu %s, cpu %s)" % (DEFAULT_SIZES["gpu"], DEFAULT_SIZES["cpu"]))
    p.add_argument("--decode", type=int, help="maximum tokens to generate per request (default: gpu 1024, cpu 256). "
                   "With a draft model, short answers understate decode speed")
    p.add_argument("--reps", type=int, default=3, help="runs per prompt length, one coding task each; the median is reported (default: 3)")
    p.add_argument("--threads", type=int, help="CPU recipes: threads (-t). Use one per performance core. "
                   "Default: half the logical CPUs")
    p.add_argument("--cpu-mask", help="CPU recipes: affinity mask for -C with --cpu-strict 1, e.g. 0x555 "
                   "(one bit per performance core). Default: no pinning")
    p.add_argument("--port", type=int, default=0, help="server port (default: a free one)")
    p.add_argument("--no-hash", action="store_true", help="skip the SHA-256 of the GGUF files")
    p.add_argument("--out", help="JSON results file (default: quick-bench-<recipe>-<machine>-<date>.json)")
    p.add_argument("extra", nargs="*", help="extra llama-server flags, after --")
    return p.parse_args()


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    return port


def http(url, body=None, timeout=3600):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 24), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return (r.stdout + r.stderr).strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def system_info(server):
    info = {"os": platform.platform(), "python": platform.python_version()}
    cpu = ""
    if os.path.exists("/proc/cpuinfo"):
        m = re.search(r"model name\s*:\s*(.+)", open("/proc/cpuinfo").read())
        cpu = m.group(1) if m else ""
    info["cpu"] = cpu or run(["sysctl", "-n", "machdep.cpu.brand_string"]) or platform.processor()
    info["logical_cpus"] = os.cpu_count()
    if os.path.exists("/proc/meminfo"):
        kb = int(re.search(r"MemTotal:\s*(\d+)", open("/proc/meminfo").read()).group(1))
        info["ram_gb"] = round(kb / 1024 / 1024, 1)
    gpu = run(["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"])
    info["gpu"] = gpu or "none detected"
    version = run([server, "--version"])
    m = re.search(r"build (\d+), commit ([0-9a-f]+)", version) or re.search(r"version:\s*(\d+) \(([0-9a-f]+)\)", version)
    # Builds from a shallow clone report build 1; the commit is then the only reliable identifier.
    info["llama_cpp"] = (f"commit {m.group(2)}" if m.group(1) == "1" else f"b{m.group(1)} ({m.group(2)})") if m else "unknown"
    return info


def vram_used_mib():
    out = run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"])
    return int(out.splitlines()[0]) if out else None


def rss_gb(pid):
    try:
        kb = int(re.search(r"VmRSS:\s*(\d+)", open(f"/proc/{pid}/status").read()).group(1))
        return round(kb / 1024 / 1024, 2)
    except (OSError, AttributeError):
        return None


# Coding requests asked after the context, one per run, so decode is measured on a real answer. With a draft
# model the decode speed depends on how predictable the answer is; a fixed set keeps runs comparable.
TASKS = [
    "Using the code above as context, write a Python function `parse_duration(text)` that converts strings "
    "like '1h30m' or '45s' into seconds. Include type hints and a docstring.",
    "Using the code above as context, write a Python class `LRUCache` with `get` and `put` methods, both O(1), "
    "using only the standard library. Include type hints.",
    "Using the code above as context, write a Python function `top_words(text, n)` that returns the n most "
    "frequent words as (word, count) pairs, ignoring case and punctuation.",
]


# Same instruction as the recipe measurements: code-only answers, which is also what a coding agent mostly writes.
SYSTEM = ("You are an expert Python programmer. Reply only with the complete code inside a single ```python``` "
          "block. Write nothing outside the block.")


def median(xs):
    xs = sorted(xs); k = len(xs) // 2
    return xs[k] if len(xs) % 2 else round((xs[k - 1] + xs[k]) / 2, 1)


def prompt_text():
    # Source files of Python's standard library: long, varied and present on every machine.
    files = sorted(glob.glob(os.path.join(sysconfig.get_paths()["stdlib"], "**", "*.py"), recursive=True))
    return "\n".join(open(f, errors="ignore").read() for f in files[:1500])


def main():
    a = parse_args()
    recipe = RECIPES[a.recipe]
    cfg = recipe[a.machine]
    model = os.path.expanduser(a.model or os.path.join(a.models_dir, cfg["model"]))
    files = [model]
    cmd = [a.server, "--host", "127.0.0.1", "-m", model]
    if "draft" in cfg:
        draft = os.path.expanduser(a.draft or os.path.join(a.models_dir, cfg["draft"]))
        files.append(draft); cmd += ["-md", draft]
    for f in files:
        if not os.path.exists(f):
            sys.exit(f"Model file not found: {f}\nDownload it (links in the recipe's README) or use --models-dir.")
    cmd += cfg["flags"] + recipe["sampling"]
    if a.machine == "cpu":
        cmd += ["-t", str(a.threads or max(1, (os.cpu_count() or 2) // 2))]
        if a.cpu_mask:
            cmd += ["-C", a.cpu_mask, "--cpu-strict", "1"]
    port = a.port or free_port()
    cmd += ["--port", str(port)] + a.extra
    sizes = [int(s) for s in (a.sizes or DEFAULT_SIZES[a.machine]).split(",")]
    a.decode = a.decode or (1024 if a.machine == "gpu" else 256)
    url = f"http://127.0.0.1:{port}"

    info = system_info(a.server)
    print(f"quick-bench · {a.recipe} · {a.machine} recipe")
    print(f"  CPU: {info['cpu']} · GPU: {info['gpu']} · RAM: {info.get('ram_gb', '?')} GB · llama.cpp {info['llama_cpp']}")
    hashes = {}
    if not a.no_hash:
        for f in files:
            print(f"  hashing {os.path.basename(f)}…", flush=True)
            hashes[os.path.basename(f)] = sha256(f)
    print("  " + " ".join(cmd), flush=True)

    vram_before = vram_used_mib() if a.machine == "gpu" else None
    log = open(f"quick-bench-server-{a.recipe}-{a.machine}.log", "w")
    t0 = time.time()
    srv = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    rows, memory = [], {}
    try:
        while True:
            if srv.poll() is not None:
                sys.exit(f"llama-server exited (code {srv.returncode}). See {log.name}.")
            try:
                if http(url + "/health", timeout=2).get("status") == "ok":
                    break
            except (urllib.error.URLError, OSError, ValueError):
                pass
            time.sleep(1)
        load_s = round(time.time() - t0, 1)
        print(f"  server ready in {load_s} s", flush=True)

        tokens = http(url + "/tokenize", {"content": prompt_text()})["tokens"]
        need = sum(sizes) * a.reps + 512
        while len(tokens) < need:
            tokens += tokens
        http(url + "/completion", {"prompt": tokens[:64], "n_predict": 8, "cache_prompt": False})  # warm-up

        offset = 64
        for n in sizes:
            runs = []
            for r in range(a.reps):
                task = TASKS[r % len(TASKS)]
                if n:
                    # A different slice of context each time, so nothing is reused from the prompt cache. The
                    # prompt ends up a little longer than n because of the task and the chat template.
                    ctx = http(url + "/detokenize", {"tokens": tokens[offset:offset + n]})["content"]; offset += n
                    content = ctx + "\n\n" + task
                else:
                    content = task.replace("Using the code above as context, w", "W")
                resp = http(url + "/v1/chat/completions", {
                    "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": content}],
                    "max_tokens": a.decode, "cache_prompt": False})
                t = resp["timings"]
                row = {"prompt_tokens": t["prompt_n"], "prefill_tok_s": round(t["prompt_per_second"], 1),
                       "decode_tokens": t["predicted_n"], "decode_tok_s": round(t["predicted_per_second"], 1)}
                if t.get("draft_n"):
                    row["draft_acceptance"] = round(t.get("draft_n_accepted", 0) / t["draft_n"], 2)
                runs.append(row)
                print(f"  {n:>6} tokens, run {r + 1}: prefill {row['prefill_tok_s']} tok/s, "
                      f"decode {row['decode_tok_s']} tok/s ({row['decode_tokens']} tokens)", flush=True)
            dec = [x["decode_tok_s"] for x in runs]
            summary = {"prompt_tokens": n or median([x["prompt_tokens"] for x in runs]), "prefill_tok_s": median([x["prefill_tok_s"] for x in runs]),
                       "decode_tok_s": median(dec), "decode_min": min(dec), "decode_max": max(dec), "runs": runs}
            if any("draft_acceptance" in x for x in runs):
                summary["draft_acceptance"] = median([x.get("draft_acceptance", 0) for x in runs])
            rows.append(summary)
        if a.machine == "gpu":
            memory["vram_mib"] = vram_used_mib()
            if vram_before is not None and memory["vram_mib"] is not None:
                memory["vram_mib_server"] = memory["vram_mib"] - vram_before
        else:
            memory["rss_gb"] = rss_gb(srv.pid)
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=30)
        except subprocess.TimeoutExpired:
            srv.kill()

    result = {"tool": "quick-bench", "date": datetime.datetime.now().isoformat(timespec="seconds"),
              "recipe": a.recipe, "machine": a.machine, "system": info, "command": cmd[1:], "files_sha256": hashes,
              "load_seconds": load_s, "memory": memory, "results": rows,
              "reference": recipe["reference"][a.machine]}
    ref = recipe["reference"][a.machine]
    out = a.out or f"quick-bench-{a.recipe}-{a.machine}-{datetime.date.today()}.json"
    json.dump(result, open(out, "w"), indent=2)

    mem = (f"{memory.get('vram_mib_server', memory.get('vram_mib'))} MiB VRAM" if a.machine == "gpu"
           else f"{memory.get('rss_gb')} GB RAM")
    print(f"\n### {a.recipe} · {a.machine} recipe\n")
    print(f"{info['cpu']} · GPU: {info['gpu']} · {info.get('ram_gb', '?')} GB RAM · llama.cpp {info['llama_cpp']} · {mem}\n")
    draft = any("draft_acceptance" in r for r in rows)
    sizes_run = [n for n in sizes]
    print("| Prompt | Prefill | Decode with that context (median, range) |" + (" Draft acceptance |" if draft else "")
          + " Reference prefill / decode |")
    print("|---|---|---|" + ("---|" if draft else "") + "---|")
    for n, r in zip(sizes_run, rows):
        line = (f"| {r['prompt_tokens']} tokens | {r['prefill_tok_s']} tok/s | "
                f"{r['decode_tok_s']} tok/s ({r['decode_min']}–{r['decode_max']}) |")
        if draft:
            line += f" {r.get('draft_acceptance', 0):.0%} |"
        pf_dec = ref["rows"].get(n)
        line += f" {pf_dec[0]} / {pf_dec[1]} tok/s |" if pf_dec else " — |"
        print(line)
    print(f"\nReference: quick-bench on the recipe's test machine ({ref['hw']}, {ref['mem']}).")
    print("It reads 5-15 % below the llama-bench figures in the recipe, which is expected.")
    print(f"Full results: {out}")


if __name__ == "__main__":
    main()
