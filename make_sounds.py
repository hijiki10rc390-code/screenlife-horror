"""効果音を合成して assets/sound/ に書き出す（権利問題を避けるため全部自作）。
実行: python make_sounds.py   （numpy が必要）
ループ音は継ぎ目が出ないよう、周波数を「1/長さ」の整数倍にそろえている。
"""
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).parent / "assets" / "sound"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)


def save(name: str, x: np.ndarray, peak: float = 0.9) -> None:
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("保存:", OUT / name)


def t_axis(sec: float) -> np.ndarray:
    return np.arange(int(SR * sec)) / SR


def loop_freq(f: float, sec: float) -> float:
    return round(f * sec) / sec        # ループの継ぎ目を消すため整数周期に丸める


def colored_noise(sec: float, lo: float, hi: float) -> np.ndarray:
    """周期的な帯域ノイズ（周波数領域で作るので、そのまま継ぎ目なしでループできる）"""
    n = int(SR * sec)
    spec = np.zeros(n // 2 + 1, complex)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    band = (freqs >= lo) & (freqs <= hi)
    spec[band] = rng.normal(size=band.sum()) + 1j * rng.normal(size=band.sum())
    return np.fft.irfft(spec, n)


# 1. 部屋の空気音（16秒ループ）: 低いこもったノイズ + 電気のうなり
D = 16.0
t = t_axis(D)
room = colored_noise(D, 30, 400) * 1.0 + colored_noise(D, 400, 2500) * 0.18
room = room / np.max(np.abs(room)) * 0.7
room += 0.12 * np.sin(2 * np.pi * loop_freq(60, D) * t) + 0.05 * np.sin(2 * np.pi * loop_freq(120, D) * t)
save("ambient_room.wav", room, 0.6)

# 2. 唸り（12秒ループ）: わずかにずれた低音のうねり + ゆっくりした揺れ
D = 12.0
t = t_axis(D)
drone = (np.sin(2 * np.pi * loop_freq(55.0, D) * t) + np.sin(2 * np.pi * loop_freq(56.5, D) * t)
         + 0.6 * np.sin(2 * np.pi * loop_freq(82.5, D) * t) + 0.35 * np.sin(2 * np.pi * loop_freq(116.0, D) * t))
drone *= 0.75 + 0.25 * np.sin(2 * np.pi * (1 / D) * 3 * t)
drone += 0.25 * colored_noise(D, 60, 300)
save("drone.wav", drone, 0.8)

# 3. 通話アプリの通知音（2音）
t = t_axis(0.35)
ping = (np.sin(2 * np.pi * 880 * t) * (t < 0.15) + np.sin(2 * np.pi * 1175 * t) * (t >= 0.12)) * np.exp(-t * 11)
save("ping.wav", ping, 0.5)

# 4. 床のきしみ: 低音ののこぎり波が滑り下りる + 不規則な振幅
t = t_axis(1.4)
f = 95 - 38 * (t / 1.4)
phase = 2 * np.pi * np.cumsum(f) / SR
creak = (2 * ((phase / (2 * np.pi)) % 1) - 1) * (0.5 + 0.5 * np.sin(2 * np.pi * 17 * t + 2 * np.sin(2 * np.pi * 3 * t)))
creak = creak * np.sin(np.pi * t / 1.4) ** 1.5 + 0.25 * colored_noise(1.4, 150, 900)[: len(t)] * np.sin(np.pi * t / 1.4)
save("creak.wav", creak, 0.55)

# 5. 悲鳴: 急上昇する高音 + ビブラート + 歪み + ノイズ（失敗時）
t = t_axis(2.2)
f = 700 + 1500 * (1 - np.exp(-t * 6)) + 60 * np.sin(2 * np.pi * 9 * t)
phase = 2 * np.pi * np.cumsum(f) / SR
scream = np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase)
scream = np.tanh(scream * 3.0) + 0.35 * colored_noise(2.2, 1000, 6000)[: len(t)]
env = np.minimum(1.0, t / 0.02) * np.exp(-np.maximum(0.0, t - 0.9) * 2.2)
save("scream.wav", scream * env, 0.9)

# 6. 安堵の音（救出時）: ゆっくり消える柔らかい和音
t = t_axis(2.4)
relief = sum(np.sin(2 * np.pi * f0 * t) for f0 in (261.6, 329.6, 392.0)) * np.exp(-t * 1.6)
save("relief.wav", relief * np.minimum(1.0, t / 0.05), 0.5)

# 7. 警告ボタンの送信音（短いクリック）
t = t_axis(0.12)
send = np.sin(2 * np.pi * 520 * t) * np.exp(-t * 40)
save("send.wav", send, 0.4)

# 8. 心音（1秒ループ）: 人影が濃くなるほど、速く・大きくする（ゲーム側で再生速度と音量を変える）
t = t_axis(1.0)


def thump(t0, amp, f0):
    tt = np.clip(t - t0, 0, None)
    return amp * np.sin(2 * np.pi * f0 * tt) * np.exp(-tt * 22) * (t >= t0)


heart = thump(0.0, 1.0, 58) + thump(0.27, 0.65, 52)
heart[-200:] *= np.linspace(1, 0, 200)   # 継ぎ目のクリックを防ぐ
save("heart.wav", heart, 0.85)


# 9. 着信音（3秒ループ）: 2回鳴って、少し休む
t = t_axis(3.0)
ring = np.zeros_like(t)
for start in (0.0, 0.6):
    tt = t - start
    seg = (tt >= 0) & (tt < 0.4)
    tone = np.sin(2 * np.pi * 440 * tt) + np.sin(2 * np.pi * 480 * tt)
    env = np.clip(np.minimum(tt / 0.01, (0.4 - tt) / 0.02), 0, 1)
    ring += seg * tone * env
save("ring.wav", ring, 0.5)
