# -*- coding: utf-8 -*-
"""
Генерация звука для игры. Синтез офлайн в WAV, дальше ffmpeg жмёт музыку в OGG.
Никаких сторонних сэмплов — значит никаких вопросов по лицензиям.

Запуск:  python tools/sound.py
Выход:   assets/audio/*.wav, assets/audio/music.ogg
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")


def save(name, sig, sr=SR):
    sig = np.clip(sig, -1.0, 1.0)
    data = (sig * 32000).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    return path


def t(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(n, attack, decay, sr=SR):
    """Экспоненциальный спад с коротким выходом на максимум."""
    a = max(1, int(attack * sr))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[a:] = np.exp(-np.arange(n - a) / (decay * sr))
    return e


def resonator(x, freq, q):
    """Двухполюсный резонансный фильтр — дёшево и достаточно для формант."""
    w = 2 * np.pi * freq / SR
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    y[0] = x[0]
    y[1] = x[1] - a1 * y[0]
    for i in range(2, len(x)):
        y[i] = x[i] - a1 * y[i - 1] - a2 * y[i - 2]
    return y * (1 - r)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = a * acc + (1 - a) * x[i]
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


# ------------------------------------------------------------------ икота --
def hiccup():
    """
    «Ик» — это резкий вдох на схлопывании голосовой щели. Собираем как
    импульсный генератор с падающей высотой, прогнанный через три форманты,
    плюс короткий шумовой щелчок в самом начале.
    """
    dur = 0.22
    x = t(dur)
    n = len(x)

    # частота основного тона: рывок вверх и быстрый спад
    f0 = 210 * np.exp(-x * 9) + 125
    phase = np.cumsum(2 * np.pi * f0 / SR)
    # пилообразный сигнал богат гармониками — то, что нужно голосовым формантам
    glottal = 2 * (phase / (2 * np.pi) % 1.0) - 1.0
    glottal *= env(n, 0.004, 0.055)

    voiced = (1.0 * resonator(glottal, 700, 9) +
              0.6 * resonator(glottal, 1180, 11) +
              0.25 * resonator(glottal, 2600, 13))

    click = np.random.randn(n) * env(n, 0.0005, 0.008) * 0.5
    click = highpass(click, 900)

    sig = voiced * 3.2 + click
    sig *= env(n, 0.003, 0.07)
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.9


# ------------------------------------------------- протрезвел и улетел ----
def whistle():
    dur = 0.5
    x = t(dur)
    n = len(x)
    f = 520 * np.exp(x * 2.4)                    # восходящий свист
    f += 22 * np.sin(2 * np.pi * 11 * x)         # лёгкое вибрато
    phase = np.cumsum(2 * np.pi * f / SR)
    sig = np.sin(phase) + 0.22 * np.sin(2 * phase)
    sig *= env(n, 0.02, 0.22)
    sig *= np.clip(np.linspace(1.4, 0, n), 0, 1) ** 0.6
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.85


# ---------------------------------------------------------------- промах --
def thud():
    dur = 0.32
    x = t(dur)
    n = len(x)
    f = 105 * np.exp(-x * 7) + 44
    phase = np.cumsum(2 * np.pi * f / SR)
    body = np.sin(phase) * env(n, 0.002, 0.075)
    noise = lowpass(np.random.randn(n), 320) * env(n, 0.001, 0.03) * 1.6
    sig = body * 1.1 + noise
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.95


# ----------------------------------------------------------------- звон ---
def chime():
    dur = 0.75
    x = t(dur)
    n = len(x)
    sig = np.zeros(n)
    # неточные обертоны дают колокольчик, а не орган
    for mult, amp, dec in ((1.0, 1.0, 0.30), (2.76, 0.5, 0.20),
                           (5.40, 0.28, 0.13), (8.93, 0.14, 0.09)):
        sig += amp * np.sin(2 * np.pi * 1046.5 * mult * x) * np.exp(-x / dec)
    sig *= env(n, 0.002, 0.34)
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.8


# ------------------------------------------------------- бьющееся стекло --
def glass():
    dur = 0.55
    n = int(dur * SR)
    x = t(dur)
    sig = highpass(np.random.randn(n), 2200) * env(n, 0.0008, 0.045) * 1.4
    # осколки: несколько затухающих высоких резонансов вразнобой
    rs = np.random.RandomState(7)
    for _ in range(9):
        f = rs.uniform(2600, 8200)
        start = int(rs.uniform(0.005, 0.30) * SR)
        ln = n - start
        if ln <= 64:
            continue
        xs = np.arange(ln) / SR
        shard = np.sin(2 * np.pi * f * xs) * np.exp(-xs / rs.uniform(0.02, 0.09))
        sig[start:] += shard * rs.uniform(0.15, 0.5)
    sig *= env(n, 0.001, 0.20)
    return sig / (np.max(np.abs(sig)) + 1e-9) * 0.85


# --------------------------------------------------------------- музыка ---
# «Jingle Bells» (James Lord Pierpont, 1857) — общественное достояние.
BPM = 124
BEAT = 60.0 / BPM
MELODY = [
    (64, 1), (64, 1), (64, 2),
    (64, 1), (64, 1), (64, 2),
    (64, 1), (67, 1), (60, 1.5), (62, 0.5), (64, 4),
    (65, 1), (65, 1), (65, 1.5), (65, 0.5),
    (65, 1), (64, 1), (64, 1), (64, 0.5), (64, 0.5),
    (64, 1), (62, 1), (62, 1), (64, 1),
    (62, 2), (67, 2),
    (64, 1), (64, 1), (64, 2),
    (64, 1), (64, 1), (64, 2),
    (64, 1), (67, 1), (60, 1.5), (62, 0.5), (64, 4),
    (65, 1), (65, 1), (65, 1.5), (65, 0.5),
    (65, 1), (64, 1), (64, 1), (64, 0.5), (64, 0.5),
    (67, 1), (67, 1), (65, 1), (62, 1),
    (60, 4),
]
# аккорды на такт: C F C G7 ... упрощённо по два такта
BASS = [48, 48, 48, 48, 53, 53, 55, 55, 48, 48, 48, 48, 53, 55, 48]


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def voice(freq, dur, kind="tri", amp=0.5):
    n = int(dur * SR)
    x = np.arange(n) / SR
    ph = 2 * np.pi * freq * x
    if kind == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    elif kind == "square":
        w = np.sign(np.sin(ph)) * 0.6
    else:
        w = np.sin(ph)
    a = max(1, int(0.008 * SR))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    rel = max(1, int(min(0.12, dur * 0.45) * SR))
    e[-rel:] *= np.linspace(1, 0, rel)
    return w * e * amp


def music():
    total_beats = sum(d for _, d in MELODY)
    n = int(total_beats * BEAT * SR) + SR // 2
    buf = np.zeros(n)

    pos = 0.0
    for m, d in MELODY:
        s = int(pos * BEAT * SR)
        v = voice(midi_hz(m), d * BEAT * 0.92, "tri", 0.42)
        buf[s:s + len(v)] += v
        pos += d

    # бас по два такта на аккорд, четвертями
    beat_i = 0
    while beat_i < total_beats:
        chord = BASS[min(int(beat_i // 4), len(BASS) - 1)]
        s = int(beat_i * BEAT * SR)
        v = voice(midi_hz(chord - 12), BEAT * 0.85, "square", 0.20)
        buf[s:s + len(v)] += v
        beat_i += 1

    # бубенцы восьмыми — шум через высокий фильтр, короткая огибающая
    sh = np.zeros(n)
    k = 0.0
    while k < total_beats:
        s = int(k * BEAT * SR)
        ln = int(0.075 * SR)
        if s + ln < n:
            e = np.exp(-np.arange(ln) / (0.012 * SR))
            sh[s:s + ln] += np.random.randn(ln) * e * (0.5 if k % 1 == 0 else 0.3)
        k += 0.5
    sh = highpass(sh, 5200) * 0.5
    buf += sh

    buf /= np.max(np.abs(buf)) + 1e-9
    return buf * 0.75


def main():
    os.makedirs(OUT, exist_ok=True)
    np.random.seed(3)
    save("hit.wav", hiccup())
    save("sober.wav", whistle())
    save("miss.wav", thud())
    save("bonus.wav", chime())
    save("hazard.wav", glass())
    mp = save("music_raw.wav", music())

    ogg = os.path.join(OUT, "music.ogg")
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp,
                        "-c:a", "libvorbis", "-q:a", "3", ogg])
    if r.returncode == 0:
        os.remove(mp)
    else:
        os.replace(mp, os.path.join(OUT, "music.wav"))

    for f in sorted(os.listdir(OUT)):
        print("  %-14s %6.1f КБ" % (f, os.path.getsize(os.path.join(OUT, f)) / 1024))


if __name__ == "__main__":
    main()
