# LPIPS (AlexNet, CPU) de cada imagen frente a una referencia. Menor = más parecida; 0 = idéntica.
# Uso: uv run --no-project --with lpips --with pillow python lpips_vs.py <referencia.png> <imagen.png>...
import sys

import lpips
import numpy as np
import torch
from PIL import Image


def cargar(ruta):
    a = np.asarray(Image.open(ruta).convert("RGB"), dtype=np.float32) / 127.5 - 1.0
    return torch.from_numpy(a).permute(2, 0, 1).unsqueeze(0)


modelo = lpips.LPIPS(net="alex", verbose=False)
ref = cargar(sys.argv[1])
print("imagen,referencia,lpips")
with torch.no_grad():
    for ruta in sys.argv[2:]:
        print(f"{ruta},{sys.argv[1]},{modelo(ref, cargar(ruta)).item():.4f}")
