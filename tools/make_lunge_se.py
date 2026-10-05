"""lunge SE を生成: 風切り音 + 低音インパクト + 叫び風の混合。
実行: /c/sd/venv-cuda/Scripts/python.exe tools/make_lunge_se.py
"""
import numpy as np
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
DURATION = 1.2
OUT = Path(__file__).parent.parent / "assets/sound" / "lunge.wav"


def save_wav(path: Path, audio: np.ndarray) -> None:
    audio = np.clip(audio, -1.0, 1.0)
    pcm16 = (audio * 32767).astype(np.int16)
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm16.tobytes())
    print(f"保存: {path}")


def whoosh() -> np.ndarray:
    """0.4 秒の下降する風切り音。"""
    n = int(SAMPLE_RATE * 0.4)
    t = np.linspace(0, 0.4, n, endpoint=False)
    # 高いノイズが 2000Hz → 200Hz にスイープ
    sweep = np.cumsum(np.linspace(2 * np.pi * 2000 / SAMPLE_RATE, 2 * np.pi * 200 / SAMPLE_RATE, n))
    noise = np.random.normal(0, 1, n)
    sig = noise * np.sin(sweep) * np.exp(-t * 3.0)
    return sig * 0.7


def impact() -> np.ndarray:
    """0.3 秒の低音インパクト。"""
    n = int(SAMPLE_RATE * 0.3)
    t = np.linspace(0, 0.3, n, endpoint=False)
    # 60Hz のサイン + 高調波 + ノイズ
    f = 60
    sig = (np.sin(2 * np.pi * f * t) * 0.8
           + np.sin(2 * np.pi * f * 2 * t) * 0.3
           + np.sin(2 * np.pi * f * 3 * t) * 0.2)
    # ノイズ
    sig += np.random.normal(0, 0.3, n)
    sig *= np.exp(-t * 8.0)
    return sig * 0.9


def scream_burst() -> np.ndarray:
    """0.5 秒の叫び風（明るい高周波 + 揺らぎ）。"""
    n = int(SAMPLE_RATE * 0.5)
    t = np.linspace(0, 0.5, n, endpoint=False)
    # 周波数を 800 → 400 → 200 と動かす
    f = 800 - 600 * t + 200 * np.sin(2 * np.pi * 5 * t)
    sig = np.sin(2 * np.pi * np.cumsum(f / SAMPLE_RATE))
    # 倍音
    sig += np.sin(2 * np.pi * 2 * np.cumsum(f / SAMPLE_RATE)) * 0.3
    # ビブラート
    sig *= 1.0 + 0.2 * np.sin(2 * np.pi * 6 * t)
    sig *= np.exp(-t * 2.5)
    return sig * 0.4


def main():
    # 風切り + インパクト + 叫び（少し重ねる）
    w = whoosh()                    # 0.4s
    i = impact()                    # 0.3s
    s = scream_burst()              # 0.5s
    total = int(SAMPLE_RATE * DURATION)
    audio = np.zeros(total)
    # whoosh: 0s〜0.4s
    audio[:len(w)] += w
    # impact: 0.2s〜0.5s (whoosh と重ねる)
    impact_start = int(SAMPLE_RATE * 0.2)
    audio[impact_start:impact_start + len(i)] += i
    # scream: 0.5s〜1.0s
    scream_start = int(SAMPLE_RATE * 0.5)
    audio[scream_start:scream_start + len(s)] += s
    # 最後の無音
    save_wav(OUT, audio)
    print(f"長さ: {DURATION}秒")


if __name__ == "__main__":
    main()
