#!/usr/bin/env python3
"""程序化生成 8-bit 音效与 chiptune BGM，输出到 assets/audio/。
运行：python3 tools/gen_audio.py
全部 WAV 由本脚本合成，无外部素材、无版权问题。"""
import wave
import math
import struct
import os
import random

SR = 44100
ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(ROOT, "..", "assets", "audio"))

random.seed(20260907)  # 固定随机种子，保证可复现


# ---------- 波形基元 ----------
def square(ph: float, duty: float = 0.5) -> float:
    return 1.0 if (ph % 1.0) < duty else -1.0


def tri(ph: float) -> float:
    p = ph % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def saw(ph: float) -> float:
    return 2.0 * (ph % 1.0) - 1.0


def noise() -> float:
    return random.uniform(-1.0, 1.0)


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


class Track:
    """可叠加的采样缓冲。"""

    def __init__(self, dur: float):
        self.n = int(dur * SR)
        self.buf = [0.0] * self.n

    def add(self, start: float, samples: list, gain: float = 1.0) -> None:
        i0 = int(start * SR)
        for i, s in enumerate(samples):
            j = i0 + i
            if 0 <= j < self.n:
                self.buf[j] += s * gain

    def normalize(self, peak: float = 0.62) -> None:
        m = max(1e-9, max(abs(s) for s in self.buf))
        k = peak / m
        self.buf = [s * k for s in self.buf]

    def write(self, path: str) -> None:
        self.normalize()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "w") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
                for s in self.buf))
        print("写出", os.path.relpath(path, OUT), f"{os.path.getsize(path)//1024}KB")


def tone(sweep, dur: float, wave_fn=square, duty: float = 0.5,
         attack: float = 0.004, release: float | None = None,
         vib: float = 0.0, gain_env: float = 0.9) -> list:
    """单音：sweep=(f0,f1) 指数扫频，attack/release 线性包络。"""
    n = int(dur * SR)
    out = []
    f0, f1 = sweep
    ph = 0.0
    rel = release if release is not None else dur * 0.5
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** t if (f0 > 0 and f1 > 0) else f0
        if vib:
            f *= 1.0 + vib * math.sin(2 * math.pi * 5.5 * i / SR)
        ph += f / SR
        s = wave_fn(ph, duty) if wave_fn is square else wave_fn(ph)
        a = min(1.0, i / (attack * SR + 1e-9))
        d = min(1.0, (n - i) / (rel * SR + 1e-9))
        out.append(s * a * min(d, 1.0) * gain_env)
    return out


def noise_burst(dur: float, decay: float = 0.9) -> list:
    n = int(dur * SR)
    return [noise() * (decay ** (i / SR * 60)) for i in range(n)]


def seq(notes, each: float, wave_fn=square, duty: float = 0.5,
        release: float | None = None, gap: float = 0.0) -> list:
    """琶音序列：notes 为频率列表。"""
    out: list = []
    for f in notes:
        seg = tone((f, f), each, wave_fn=wave_fn, duty=duty, release=release)
        out.extend(seg)
        if gap:
            out.extend([0.0] * int(gap * SR))
    return out


# ---------- 音效 ----------
def gen_sfx() -> None:
    d = os.path.join(OUT, "sfx")

    t = Track(0.22)
    t.add(0.0, tone((250, 700), 0.18, square, release=0.1), 0.9)
    t.write(os.path.join(d, "jump.wav"))

    t = Track(0.25)
    t.add(0.0, seq([988, 1319], 0.1, square, 0.35, release=0.07), 0.9)
    t.write(os.path.join(d, "coin.wav"))

    t = Track(0.35)
    t.add(0.0, tone((400, 80), 0.3, saw, release=0.2), 0.8)
    t.add(0.0, noise_burst(0.18, 0.75), 0.3)
    t.write(os.path.join(d, "hurt.wav"))

    t = Track(0.16)
    t.add(0.0, tone((380, 90), 0.12, square, release=0.08), 0.9)
    t.add(0.0, noise_burst(0.07, 0.6), 0.35)
    t.write(os.path.join(d, "stomp.wav"))

    t = Track(0.28)
    t.add(0.0, tone((150, 900), 0.22, square, 0.4, release=0.12), 0.9)
    t.write(os.path.join(d, "bounce.wav"))

    t = Track(0.9)
    fan = seq([523, 659, 784, 1047], 0.13, square, 0.4, release=0.1)
    t.add(0.0, fan, 0.8)
    t.add(0.52, tone((1047, 1047), 0.35, square, 0.4, vib=0.01), 0.8)
    t.write(os.path.join(d, "win.wav"))

    t = Track(1.15)
    g = seq([392, 330, 262], 0.24, square, 0.5, release=0.18)
    t.add(0.0, g, 0.8)
    t.add(0.72, tone((196, 190), 0.4, square, 0.5, release=0.35), 0.8)
    t.write(os.path.join(d, "game_over.wav"))

    t = Track(0.08)
    t.add(0.0, tone((900, 650), 0.055, square, release=0.03), 0.7)
    t.write(os.path.join(d, "click.wav"))


# ---------- BGM 作曲器 ----------
# C 大调五声音阶旋律（MIDI），0 = 休止，负数 = 延音（延长前一音）
LEVEL_MELODY = [
    # A 段（轻快跳跃）
    76, 79, 81, 79, 76, 74, 72, 74,
    76, 79, 81, 84, 81, 79, 76, 79,
    76, 79, 81, 79, 76, 74, 72, 74,
    72, 74, 76, 74, 72, 0, 67, 0,
    # B 段（推向高点）
    81, 84, 81, 79, 76, 79, 76, 74,
    72, 74, 76, 79, 81, 79, 76, 74,
    72, 74, 76, 79, 81, 84, 81, 79,
    76, 74, 72, 74, 72, 0, 72, 0,
]
LEVEL_BASS_ROOT = [48, 45, 41, 43]  # C3 A2 F2 G2 和弦进行，每小节(8步)换
MENU_MELODY = [
    72, 0, 76, 0, 79, 0, 76, 0,
    81, 0, 79, 0, 76, 0, 74, 0,
    72, 0, 76, 0, 79, 0, 81, 0,
    79, 0, 76, 0, 74, 0, 72, 0,
]
MENU_BASS_ROOT = [48, 45, 41, 43]


def make_music(melody: list, bass_roots: list, step: float,
               path: str, melody_duty: float = 0.35) -> None:
    total = len(melody) * step + 0.5
    t = Track(total)
    ph_acc = 0.0
    for i, m in enumerate(melody):
        if m > 0:
            f = midi_hz(m)
            seg = tone((f, f), step * 0.92, square, melody_duty,
                       attack=0.006, release=step * 0.35, vib=0.008)
            t.add(i * step, seg, 0.5)
        # 低音：每步都弹当前和弦根音（三角波，弱）
        root = bass_roots[(i // 8) % len(bass_roots)]
        bf = midi_hz(root)
        bseg = tone((bf, bf), step * 0.9, tri, attack=0.004, release=step * 0.3)
        t.add(i * step, bseg, 0.4)
        # hi-hat：每小节第 4/6 步轻噪声
        if i % 8 in (3, 6):
            t.add(i * step, noise_burst(0.03, 0.5), 0.12)
    t.write(path)


def gen_music() -> None:
    d = os.path.join(OUT, "music")
    make_music(LEVEL_MELODY, LEVEL_BASS_ROOT, 60 / 140 / 2,
               os.path.join(d, "level_theme.wav"))
    make_music(MENU_MELODY, MENU_BASS_ROOT, 60 / 116 / 2,
               os.path.join(d, "menu_theme.wav"), melody_duty=0.5)


if __name__ == "__main__":
    print("== 生成音效 ==")
    gen_sfx()
    print("== 生成 BGM ==")
    gen_music()
    print("完成 ✓")
