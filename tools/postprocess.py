# -*- coding: utf-8 -*-
"""
Постобработка сгенерированных ассетов:
  magenta -> альфа, подавление фиолетовой каймы, обрезка по содержимому, ресайз.

Запуск:  python tools/postprocess.py
Вход:    assets/raw/*.png   Выход: assets/*.png
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "raw")
OUT = os.path.join(ROOT, "assets")

# имя -> (максимальная сторона в пикселях, обрезать ли по содержимому)
TARGETS = {
    "santa_c1":   (128, True),
    "santa_c2":   (128, True),
    "santa_c3":   (128, True),
    "santa_c4":   (128, True),
    "santa_fly":  (128, True),
    "paddle":     (384, True),
    "item_brine": (96,  True),
    "item_snack": (96,  True),
    "item_wide":  (96,  True),
    "item_high":  (96,  True),
    "item_slow":  (96,  True),
    "item_coal":  (96,  True),
    "item_bottle": (96, True),
    "bg":         (900, False),
}

KEY = np.array([255.0, 0.0, 255.0])
HARD = 90.0    # ближе этого к чистой magenta — точно фон
SOFT = 165.0   # дальше этого — точно объект; между ними мягкий край


def key_out(img):
    """Хромакей по magenta с мягким краем и подавлением каймы."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    dist = np.linalg.norm(rgb - KEY, axis=2)

    alpha = np.clip((dist - HARD) / (SOFT - HARD), 0.0, 1.0)

    # Подавление каймы: у magenta красный и синий высоки, зелёный низок.
    # На краях спрайта фон подмешивается и даёт фиолетовый ореол — тянем
    # красный и синий вниз к зелёному ровно там, где такой перекос есть.
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = np.minimum(r, b) - g
    mask = (spill > 0) & (alpha > 0) & (alpha < 1)
    k = np.where(mask, np.minimum(spill, 60.0), 0.0)
    rgb[..., 0] = np.clip(r - k, 0, 255)
    rgb[..., 2] = np.clip(b - k, 0, 255)

    out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def trim(img, pad=2):
    a = np.asarray(img)[..., 3]
    ys, xs = np.where(a > 8)
    if len(xs) == 0:
        return img
    x0, x1 = max(0, xs.min() - pad), min(img.width, xs.max() + 1 + pad)
    y0, y1 = max(0, ys.min() - pad), min(img.height, ys.max() + 1 + pad)
    return img.crop((x0, y0, x1, y1))


def main():
    os.makedirs(OUT, exist_ok=True)
    done, missing = [], []
    for name, (size, do_trim) in TARGETS.items():
        src = os.path.join(RAW, name + ".png")
        if not os.path.exists(src):
            missing.append(name)
            continue
        img = Image.open(src)

        if name == "bg":
            # фон не режем по альфе — кадрируем под 3:2 и гасим контраст
            img = img.convert("RGB")
            w, h = img.size
            want = 900 / 600
            if w / h > want:
                nw = int(h * want)
                img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
            else:
                nh = int(w / want)
                img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
            img = img.resize((900, 600), Image.LANCZOS)
            img.save(os.path.join(OUT, name + ".png"), optimize=True)
            done.append((name, img.size))
            continue

        img = key_out(img)
        if do_trim:
            img = trim(img)
        scale = size / max(img.width, img.height)
        if scale < 1:
            img = img.resize((max(1, round(img.width * scale)),
                              max(1, round(img.height * scale))), Image.LANCZOS)
        img.save(os.path.join(OUT, name + ".png"), optimize=True)
        done.append((name, img.size))

    for n, s in done:
        print("  %-13s %sx%s" % (n, s[0], s[1]))
    if missing:
        print("  нет исходников:", ", ".join(missing))


if __name__ == "__main__":
    main()
