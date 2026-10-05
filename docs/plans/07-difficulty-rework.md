# 計画 07: 難易度の再設計

## 目的
ユーザーの指摘「ゲームとしてめちゃくちゃ簡単？」への対応。計画 06 で「クリック 1 つで救出」になった分、判定と制限時間で歯ごたえを出す。**クリア不能にはしない**（名人ボット + `balance_report.py` で必ず救出可能を確認）。

## 仕様の変更

### 1. ふつう既定を一段厳しく（既定 difficulty = 2）
- `settings.json` を読んだときの既定値を `1`（ふつう）から `2`（むずかしい相当）に変える
- 既存ユーザー（設定ファイルを持っている人）は、保存値を尊重（既定値が変わるのは新規・未保存の人だけ）
- `_apply_difficulty()` の `DIFFICULTY_TABLE` 自体も一段厳しく調整する（やさしい・ふつう・むずかしい の全体を上げる）

新しい `DIFFICULTY_TABLE`（[max_false_alarms, false_alarm_lock, fail_at 係数, belief 補正, need_warnings 補正]）:
| 段 | false_alarms | lock | fail 係数 | belief 補正 | need_warnings |
|---|---|---|---|---|---|
| やさしい (0) | 4 | 3.0 | 1.10 | +0.10 | -1 |
| ふつう (1) | 2 | 4.0 | 0.95 | 0.00 | 0 |
| むずかしい (2) | 2 | 5.0 | 0.85 | -0.05 | +1 |

（いまの「むずかしい」が false_alarms=2 / lock=4.0 / fail*0.9 / belief-0.1 なので、
 「ふつう」を一段厳しく、「むずかしい」をさらに厳しくする）

### 2. `fail_at` を「最大濃度に達する時刻 + 12〜15 秒」に縮める
各ステージの `ghost_curve` の最終時刻（最大の濃さに達する時刻）を `T_max` とし、
`fail_at = T_max + 余裕` とする。余裕は:
- stage1: T_max=95 → fail_at=90）（余裕 = -5? いやそれではプレイ時間が短すぎる。T_max + 10 = 105）
- いや、stage1 の fail_at は現在 110。T_max=95 なら余裕 = 15。これを 10 に縮める。
- stage2: T_max=80 → fail_at 95 → 縮める。余裕 = 15 → 12
- stage3: T_max=84 → fail_at 100 → 縮める。余裕 = 16 → 12

目標:
- stage1.json: fail_at = 105（T_max=95 → 余裕 10）
- stage2.json: fail_at = 92（T_max=80 → 余裕 12）
- stage3.json: fail_at = 96（T_max=84 → 余裕 12）

### 3. 練習ステージ以外で「見え始めの合図」を維持（変えない）
- stage1（練習）の「最初の creak 直後の音とヒント」はそのまま
- stage2/3 のうなり・緊張の台詞（`uneasy_at`）はそのまま
- 親切なヒント文は変えない（「画面下のボタンのみ」の見直しは計画 08）

## テスト

### 既存のテスト
- 既存 207 件はそのまま通ること（`fail_at` を縮めても、名人ボットが fail 前に救出できれば OK）
- 通しプレイ（`test_playthrough.gd`）の放置ボットは `fail_at - 1` 秒以上プレイしてから `state == FAILED` を確認する。`fail_at` を縮めると、ボットの最大ループ回数も影響する。`max_ticks = int(m.fail_at / TICK) + 100` で吸収しているはず（確認）

### 新規テスト
- `tests/test_logic.gd` の末尾に追加）:
    - difficulty の既定が変わったこと: 設定ファイルがない状態で `S.difficulty` を読むと 2 になる。`_load_settings()` は `persist=false`（テスト用）のときに呼ばれるが、未読込 `cfg.get_value` の第3引数（既定値）が変わっていれば反映される
    - DIFFICULTY_TABLE の値が変わったこと: `[4, 3.0, 1.10, 0.10, -1]` などを比較
- `tests/test_playthrough.gd`:
    - 7. 難易度 × 全ステージ × 名人/クリアiere の組み合わせで救出できること（既存 7 と同等）
    - 既存 7 で difficulty=2 のケースを追加して名人ボットが通ること

### `balance_report.py` の更新
- `python balance_report.py` で、新しい fail_at でも救出可能か計算
- 出力に「最大の濃さ + 余裕」が含まれるようにする

## 受け入れ条件
- `bash tools/run_tests.sh` が全部 OK（最終値は 207 + 新規 N 件）
- `bash tools/shot.sh 1/2/3` がエラーなく終わる
- `python balance_report.py` が新しい fail_at でも「救出可能」を示す
- exe: `outputs/build/screenlife-horror.exe --headless --quit-after 20 -- --stage=2` の終了コード 0
- 名人ボット（クリック経由・既存両方）が全難易度 × 全ステージで救出成功

## やらないこと
- 当たり判定の箱を人影の実際の大きさに絞る（画像解析が必要。次回以降）
- 人影の位置を spot ごとにばらつかせる（stage JSON 拡張。次回以降）
- 見え始めの合図の変更・削減（計画 09 以降で別途検討）
- 新しい画像・効果音の追加
- `tools/`・`project.godot`・`export_presets.cfg` の変更