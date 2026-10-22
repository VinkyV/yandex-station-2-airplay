#!/usr/bin/env python3
"""Генератор паттернов подсветки для Яндекс.Станции Midi.

Кольцо висит на /dev/fb0: 89 пикселей в строку, по 4 байта (R, G, B, 0 —
четвёртый байт не используется). Паттерн — просто последовательность кадров
по 356 байт, которые проигрыватель (scripts/device/led-lamp.sh) листает через dd.

Считать кадры на самой колонке нельзя: в busybox-awk нет cos(), а printf "%c"
портит байты больше 127 (пишет их как UTF-8). Поэтому кадры готовятся здесь.

    python3 led-patterns.py /tmp/ledpat        # все паттерны
"""
import math
import os
import sys

W = 89          # светодиодов в кольце
FRAME = W * 4   # 356 байт на кадр


def frame(r, g, b):
    return bytes([r, g, b, 0]) * W


def breathe(peak=(255, 255, 255), n=60):
    """Плавно: темнота -> пик -> темнота. Возвращает список кадров."""
    up = [(1 - math.cos(i * math.pi / (n - 1))) / 2 for i in range(n)]
    curve = up + up[-2::-1]
    r, g, b = peak
    return [frame(int(r * k), int(g * k), int(b * k)) for k in curve]


def cycle(colors, gap=2, n=60):
    """Дыхание по очереди: смена цвета только в полной темноте."""
    out = []
    for c in colors:
        out += breathe(c, n)
        out += [frame(0, 0, 0)] * gap
    return out


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ledpat"
    os.makedirs(out_dir, exist_ok=True)

    solids = {
        "solid_white": (255, 255, 255),
        "solid_red": (255, 0, 0),
        "solid_green": (0, 255, 0),
        "solid_blue": (0, 0, 255),
    }
    for name, c in solids.items():
        open(os.path.join(out_dir, name + ".pat"), "wb").write(frame(*c))

    single = {
        "violet": (90, 40, 160),
        "warm": (255, 170, 90),
        "blue": (30, 80, 255),
        "green": (40, 200, 90),
        "red": (255, 0, 0),
    }
    for name, c in single.items():
        open(os.path.join(out_dir, name + ".pat"), "wb").write(b"".join(breathe(c)))

    tri = cycle([(255, 255, 255), (30, 80, 255), (255, 0, 0)])
    open(os.path.join(out_dir, "tricolor.pat"), "wb").write(b"".join(tri))

    for f in sorted(os.listdir(out_dir)):
        p = os.path.join(out_dir, f)
        print(f"{f}: {os.path.getsize(p)} байт, {os.path.getsize(p)//FRAME} кадров")


if __name__ == "__main__":
    main()
