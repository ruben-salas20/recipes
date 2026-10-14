# Paso 2.0 · Comandos para Rubén

Dos arranques. En cada uno, mide nada más arrancar, con el portátil enchufado y sin abrir nada más.

## 1. Arranque con `mem=16G`

En el menú de limine:

1. Selecciona la entrada de Omarchy y pulsa `e`.
2. Ve al final de la línea `cmdline` y añade un espacio y `mem=16G`.
3. Pulsa `F10` para arrancar. El cambio solo vale para este arranque.

Si limine no deja editar, para aquí.

Ya dentro, comprueba que está activo (debe salir `mem=16G` y unos 12 GB: el corte es por dirección física y el hueco bajo 4 GB no tiene RAM):

```bash
grep -o 'mem=16G' /proc/cmdline; free -g | head -2
```

Mide (unos 2 minutos):

```bash
~/Projects/AI-Engineer/recetas/LFM2.5-2.6B/scripts/ram-asimetrica.sh mem16g
```

## 2. Arranque normal

Reinicia sin tocar nada en limine. Comprueba que `mem=16G` ya no está (no debe salir nada):

```bash
grep -o 'mem=16G' /proc/cmdline
```

Mide:

```bash
~/Projects/AI-Engineer/recetas/LFM2.5-2.6B/scripts/ram-asimetrica.sh normal
```

## 3. Después

Abre una sesión con Claude en `~/Projects/AI-Engineer/recetas` y di que sigamos con el paso 2.0.
Los resultados quedan en esta carpeta: `mem16g.csv`, `mem16g.log`, `normal.csv`, `normal.log`.
