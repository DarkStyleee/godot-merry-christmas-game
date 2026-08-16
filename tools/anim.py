# -*- coding: utf-8 -*-
"""
Сборка спрайтшита из кадров, выданных WAN i2v.

Видеомодель уводит масштаб и положение персонажа от кадра к кадру — если
склеить как есть, анимация будет «дышать». Поэтому каждый кадр выравнивается
по центроиде альфы и нормируется по площади силуэта: так персонаж стоит на
месте и не меняет размер, а меняются только поза и наклон.

Запуск:  python tools/anim.py santa_anim santa_c2_sheet 0 10 6
         (префикс кадров, имя листа, первый кадр, последний, сколько взять)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "raw")
OUT = os.path.join(ROOT, "assets")
CELL = 128           # сторона ячейки спрайтшита


def key_magenta(im):
    """Фон magenta уходит в альфу. Ключуем по оттенку: у фона и красный, и
    синий сильно выше зелёного, а у красной шубы синий низкий."""
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (r - g > 45) & (b - g > 45)
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8))
    alpha = alpha.filter(ImageFilter.MedianFilter(5))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    al = np.asarray(alpha)

    # подавление фиолетовой каймы на полупрозрачных краях
    spill = np.minimum(r, b) - g
    m = (spill > 0) & (al > 0) & (al < 255)
    k = np.where(m, np.minimum(spill, 70.0), 0.0)
    a[..., 0] = np.clip(r - k, 0, 255)
    a[..., 2] = np.clip(b - k, 0, 255)
    return Image.fromarray(np.dstack([a, al]).astype(np.uint8), "RGBA")


def stats(img):
    al = np.asarray(img)[..., 3]
    ys, xs = np.where(al > 40)
    if len(xs) == 0:
        return None
    cx, cy = xs.mean(), ys.mean()
    # максимальный вынос силуэта от центроиды — по нему потом подбираем общий
    # масштаб, чтобы персонаж заполнял ячейку, а не болтался в ней
    reach = max(cx - xs.min(), xs.max() - cx, cy - ys.min(), ys.max() - cy)
    return {"area": len(xs), "cx": cx, "cy": cy, "reach": reach}


def main():
    prefix, name = sys.argv[1], sys.argv[2]
    first, last, count = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

    files = []
    for i in range(first, last + 1):
        f = os.path.join(RAW, "%s.png" % prefix if i == 0 else "%s_%02d.png" % (prefix, i))
        if os.path.exists(f):
            files.append(f)
    if not files:
        raise SystemExit("кадров не найдено: " + prefix)

    # равномерно прореживаем до count кадров
    idx = [round(i * (len(files) - 1) / max(1, count - 1)) for i in range(count)]
    files = [files[i] for i in idx]

    frames = [key_magenta(Image.open(f)) for f in files]
    st = [stats(f) for f in frames]
    if any(s is None for s in st):
        raise SystemExit("пустой кадр после ключевания")

    # нормируем по площади силуэта — устойчивее, чем по габаритам: поза меняет
    # ширину, но почти не меняет площадь
    ref_area = st[0]["area"]
    k = [(ref_area / s["area"]) ** 0.5 for s in st]
    # общий масштаб подбираем по самому «размашистому» кадру, чтобы ни один не
    # обрезался, но и пустого поля в ячейке не оставалось
    reach = max(s["reach"] * ki for s, ki in zip(st, k))
    gscale = (CELL * 0.48) / reach

    sheet = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
    for i, (img, s) in enumerate(zip(frames, st)):
        scale = k[i] * gscale
        w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
        small = img.resize((w, h), Image.LANCZOS)
        # совмещаем центроиды
        cx, cy = s["cx"] * scale, s["cy"] * scale
        sheet.paste(small, (round(i * CELL + CELL / 2 - cx), round(CELL / 2 - cy)), small)

    path = os.path.join(OUT, name + ".png")
    sheet.save(path, optimize=True)
    print("%s: %d кадров, %sx%s" % (name, len(frames), sheet.width, sheet.height))


if __name__ == "__main__":
    main()
