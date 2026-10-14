# Contributing

Thanks for wanting to help. The recipes here are only useful if their numbers are real, so every contribution follows one rule: **say exactly what you measured, on what, and how.**

*Resumen en español [al final](#en-español).*

## Share your results

The easiest and most useful contribution. Did you run a recipe on another GPU, CPU or laptop?

1. Run [`tools/quick-bench.py`](tools/README.md) with the recipe (a few minutes).
2. Open an issue with the **Share results** form and paste the Markdown table it prints. Attach the JSON file if you can.
3. Mention anything you changed from the recipe (flags, quantization, llama.cpp version) and anything unusual (laptop on battery, other programs using the GPU).

Results that do not match the recipe are as welcome as the ones that do.

## Report a problem

Open an issue with the recipe, your hardware, your llama.cpp version (`llama-server --version`), the exact command and the error or the numbers you got. If a recipe stopped working after a llama.cpp update, say which version last worked.

## Improve a recipe or add a new one

Open an issue first to discuss it, then a pull request. A change to a recipe needs:

- **The measurement behind it.** The script you ran and its raw output (CSV or JSON), in the recipe's `scripts/` and `bench/` folders, named after the round.
- **The full configuration.** Model file and its SHA-256, quantization, flags, context size, llama.cpp version and commit, and the machine (GPU and VRAM, CPU, RAM). A number is only valid for the configuration it was measured with: if one of these changes, measure again.
- **Real sizes.** Report bits per weight and file size, not only the quantization label.
- **Enough runs.** For speed, repeat and report the spread; on laptops, note the temperature, because heat changes the results. For quality, use at least 3 runs: one run of the coding benchmark varies by 1–2 tasks.
- **Both languages.** Each recipe has an English `README.md` and a Spanish `README.es.md`. If you can only write one, say so in the pull request and we will translate the other.

Keep the style of the existing recipes: the exact command first, then why each flag is there, then the numbers.

## What not to send

- **Model weights.** They are never stored in this repository: link to their source and give the SHA-256.
- **Numbers without a way to check them.** If it cannot be reproduced, it cannot go in a recipe.

## License

By contributing, you agree that your contributions are released under the repository's [MIT license](LICENSE). Model weights keep their own licenses; each recipe says which.

## En español

Gracias por querer ayudar. Las recetas solo sirven si sus números son reales, así que toda contribución sigue una regla: **di exactamente qué mediste, en qué y cómo.**

- **Compartir resultados** (lo más fácil y útil): ejecuta [`tools/quick-bench.py`](tools/README.es.md) con la receta y abre un *issue* con el formulario **Share results** y la tabla que imprime. Indica lo que hayas cambiado respecto a la receta. Los resultados que no coinciden con la receta también son bienvenidos.
- **Informar de un problema:** abre un *issue* con la receta, tu equipo, tu versión de llama.cpp, el comando exacto y el error o los números obtenidos.
- **Mejorar una receta o añadir una:** abre primero un *issue* y después un *pull request* con la medición que lo respalda (script y datos en bruto), la configuración completa (fichero y SHA-256, opciones, contexto, versión de llama.cpp, máquina), bits por peso reales, suficientes corridas (3 como mínimo para calidad) y los dos idiomas (`README.md` y `README.es.md`); si solo puedes escribir uno, dilo y traducimos el otro.
- **No envíes** pesos de modelos ni números que no se puedan comprobar.
- **Licencia:** lo que aportes se publica bajo la [licencia MIT](LICENSE) del repositorio.
