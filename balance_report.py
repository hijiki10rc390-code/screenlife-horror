"""各ステージの難易度の目安を、ステージ設定（stages/*.json）から計算して表示する。
実行: python balance_report.py        （標準ライブラリだけで動く）

見るところ:
  - 人影が「映った」と扱われる最初の時刻（濃さ 0.08 以上）と、失敗までの余裕
  - 疑り深い相手（信頼度つき）で、警告が通る最初の時刻（伝え方ごと・話しかけ回数ごと）
注意: 人影の濃さには 0.7〜1.0 倍のちらつきが入るので、実際の境目は数秒ぶれる。
"""
import glob
import json
import math
from pathlib import Path

SEEN = 0.08
PHRASE_BONUS = [0.10, 0.30, 0.20]
PHRASES = ["後ろ見て！", "逃げて！", "外に出て！"]
TALK_TRUST = 0.05
TALK_COOLDOWN = 4.0
TRUST_MILESTONE = 0.6
# 難易度（main.gd の DIFFICULTY_TABLE と同じ並び）[false_alarms, lock, fail 係数, belief 補正, need_warnings 補正]
DIFFICULTY_FAIL_MULT = [1.10, 0.95, 0.85]
DIFFICULTY_FALSE_ALARMS = [4, 2, 2]
DIFFICULTY_BELIEF_ADD = [0.10, 0.0, -0.05]
DIFFICULTY_NEED_WARNINGS = [-1, 0, 1]
DIFFICULTY_LOCK = [3.0, 4.0, 5.0]


def alpha_at(curve, t):
    for i in range(1, len(curve)):
        a, b = curve[i - 1], curve[i]
        if t <= b[0]:
            k = (t - a[0]) / (b[0] - a[0]) if b[0] != a[0] else 1.0
            return a[1] + (b[1] - a[1]) * k
    return curve[-1][1]


def first_time(pred, fail_at, step=0.5):
    t = 0.0
    while t <= fail_at:
        if pred(t):
            return t
        t += step
    return None


def main():
    for path in sorted(glob.glob(str(Path(__file__).parent / "stages" / "stage*.json"))):
        d = json.load(open(path, encoding="utf-8"))
        curve, fail_at = d["ghost_curve"], d["fail_at"]
        seen_at = first_time(lambda t: alpha_at(curve, t) >= SEEN, fail_at)
        t_max = curve[-1][0]
        margin = fail_at - t_max
        print(f"■ {d['id']}（{d['friend']} / {d.get('mode', 'call')}）")
        print(f"  制限時間 {fail_at:.0f}秒 / 人影が映る最初の時刻 {seen_at:.1f}秒 / 気づける時間の幅 {fail_at - seen_at:.0f}秒 / 最大の濃さに達する時刻 {t_max:.0f}秒 + 余裕 {margin:.0f}秒")
        relief = d.get("relief", [])
        if relief:
            windows = " / ".join(f"{int(a)}〜{int(b)}秒" for a, b in relief)
            print(f"  緩和: {windows}")
        else:
            print(f"  緩和: なし")
        belief0 = d.get("belief_start", 1.0)
        # 難易度別の目安（やさしい/ふつう/むずかしい）。制限時間は倍率を掛けて整数に丸める
        times = "/".join(f"{int(fail_at * m)}秒" for m in DIFFICULTY_FAIL_MULT)
        limits = "/".join(str(n) for n in DIFFICULTY_FALSE_ALARMS)
        locks = "/".join(f"{l:.0f}秒" for l in DIFFICULTY_LOCK)
        diff_extra = ""
        if belief0 < 1.0:
            beliefs = "/".join(f"{belief0 + a:.2f}" for a in DIFFICULTY_BELIEF_ADD)
            diff_extra = f" / 初期信頼 {beliefs}"
        if d.get("mode", "call") == "stream":
            needs = "/".join(str(d.get("need_warnings", 3) + a) for a in DIFFICULTY_NEED_WARNINGS)
            diff_extra += f" / 配信の必要回数 {needs}"
        print(f"  難しさ別（やさしい/ふつう/むずかしい）： 制限時間 {times} / 誤警告の上限 {limits} / ロック {locks}{diff_extra}")
        if d.get("mode", "call") == "stream":
            print(f"  配信: 警告コメントを {d.get('need_warnings', 3)} 回、{d.get('warn_window', 20)}秒以内に。"
                  f"映った直後から投稿でき、最短 {seen_at + 2 * 0.5:.1f}秒付近で救出可能")
        elif belief0 < 1.0:
            print(f"  信頼の初期値 {belief0:.2f}（話しかけるたび +{TALK_TRUST}、{TALK_COOLDOWN:.0f}秒に1回まで）。警告が通る最初の時刻:")
            if belief0 >= TRUST_MILESTONE:
                n_talks = 0
            else:
                n_talks = math.ceil((TRUST_MILESTONE - belief0) / TALK_TRUST)
            print(f"  信頼 {int(TRUST_MILESTONE * 100)}% まで 話しかけ {n_talks} 回")
            for talks in (0, 3, 5):
                row = []
                for i, name in enumerate(PHRASES):
                    b = min(1.0, belief0 + talks * TALK_TRUST)
                    t = first_time(lambda t, b=b, i=i: b + alpha_at(curve, t) * 0.8 + PHRASE_BONUS[i] >= 1.0, fail_at)
                    row.append(f"{name}={'-' if t is None else f'{t:.0f}秒'}")
                print(f"    話しかけ{talks}回: " + " / ".join(row))
        else:
            print(f"  すぐ信じる（練習）。映った {seen_at:.1f}秒 以降、人影を指して警告すれば成功")
        print()


if __name__ == "__main__":
    main()
