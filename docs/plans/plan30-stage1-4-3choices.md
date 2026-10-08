# プラン 30 — stage1-4 の残りシーンにも 3 択目を追加

## 0. ゴール

プラン 29 で stage5-10 の 36 シーンに「誤った選択肢」を追加したが、stage1-4 には **23 シーン** が 2 択のまま残っている。これらを 3 択に揃えて、全 10 ステージで一貫した選択肢体験にする。

stage1: 6 シーン (intro / distant / after_work / ghost_nervous / end / urgent_warning)
stage2: 6 シーン (warm_open / cold_open / about_today / trust_check / ending / urgent_warning)
stage3: 5 シーン (chat_topic / about_viewer / feel_anxious / ending / urgent_warning)
stage4: 6 シーン (warm_open / cold_open / about_room / trust_check / ending / urgent_warning)

## 1. 背景

### プラン 29 の進捗
- stage5-10 の 36 シーンは 3 択化済み（コミット `622ced3`）
- 既存の hello / warm シーンは 2/3 になっていた

### 残作業
- stage1-4 の 23 シーンは 2 択のまま
- これら 23 個に「誤った選択肢」を追加する

## 2. 仕様

### 2.1. belief 値のルール
プラン 29 の方針を踏襲:

| シーン種別 | 3 択目 belief |
|---|---|
| 序盤・雑談 (intro / chat_topic など) | 0.0 〜 -0.03（中立寄り） |
| 別れの挨拶 (distant / cold_open) | -0.03 〜 -0.04 |
| ホラー兆候 (after_work / about_room / feel_anxious / about_today) | -0.03 〜 -0.04 |
| 信頼確認 (trust_check) | -0.03 〜 -0.04 |
| 終了前 (end / ending) | -0.03（信憑性低い返答） |
| 緊急 (urgent_warning) | -0.02（プラン 29 の標準「落ち着いて、もう少し」） |

### 2.2. next_scene
- 既存 2 択のうち **信念値がより低い方の next_scene** に揃える（誤選択肢＝先送り / 信頼下げる系）
- ending / urgent_warning は next_scene なし（ゲーム終了）
- 例: stage1 intro の "あとで聞かせて" は `distant` 行き → 新規 3 択目も `distant` 行き

### 2.3. キャラの口調
`docs/character-bible.md` に準拠:

| キャラ | 口調 | 例 |
|---|---|---|
| Mika (stage1) | 〜だね・〜かな・カジュアル | 「ちょっと疲れてるのかもよ」「考えすぎじゃない？」 |
| Aoi (stage2) | 〜ね・〜だよね・斜に構える | 「全然、つなげなくていいよ」「どうだろうね」 |
| ゆめ (stage3) | 〜！・配信コメント調・配信中の距離感 | 「配信中はそういうのやめて〜」「いや、ちらついてないよ」 |
| 蓮 (stage4) | 〜だ・〜かな・穏やか | 「あんまり怖がらないでよ」「寝ぼけてるんじゃない？」 |

### 2.4. 既存パターンとの整合
- `next_scene` の末尾 "." (ピリオド) の有無で chat 表示に差が出ないよう、既存選択肢の chat とスタイルを揃える
- 自動チャット欄 (`chat`) は `text` と同じ末尾ピリオドで統一

## 3. シーン別の追加選択肢

### stage1（Mika / カジュアル・女の子）

| scene | 既存 | 新規（誤選択肢） | belief | next_scene |
|---|---|---|---|---|
| intro | "えっ、なに、なに？"(+0.05→warm) / "あとで聞かせて"(-0.04→distant) | "...ふーん、で？" | -0.02 | distant |
| distant | "ごめん、聞くよ"(+0.03→after_work) / "うん"(-0.02→after_work) | "そっか、忙しかった？" | -0.03 | after_work |
| after_work | "どしたの？"(+0.04→ghost_nervous) / "気にしすぎじゃない？"(−0.03→ghost_nervous) | "ちょっと疲れてるのかもよ" | -0.03 | ghost_nervous |
| ghost_nervous | "おかしくないよ、信じるよ"(+0.07→end) / "大丈夫だって"(−0.04→end) | "考えすぎじゃない？" | -0.04 | end |
| end | "見える、ちゃんと見えるよ"(+0.08) / "誰かいるかも"(+0.05) | "何も見えないよ、大丈夫だよ" | -0.03 | (なし) |
| urgent_warning | "今すぐ逃げて"(+0.1) / "信じてる"(+0.08) | "落ち着いて、もう少し。" | -0.02 | (なし) |

### stage2（Aoi / 疑り深い女性）

| scene | 既存 | 新規 | belief | next_scene |
|---|---|---|---|---|
| warm_open | "ゆっくり話して"(+0.05→about_today) / "何かあった？"(+0.04→about_today) | "大丈夫、落ち着いて" | -0.03 | about_today |
| cold_open | "いや、話したいよ"(+0.04→about_today) / "大丈夫、続けて"(−0.01→about_today) | "全然、つなげなくていいよ" | -0.04 | about_today |
| about_today | "私も気をつけてる"(+0.06→trust_check) / "それは...気のせいでは"(−0.04→trust_check) | "ストレスかもよ" | -0.04 | trust_check |
| trust_check | "もちろん、信じる"(+0.07→ending) / "落ち着いて考えて"(−0.03→ending) | "どうだろうね、あまり信じられないかも" | -0.04 | ending |
| ending | "絶対に逃げて"(+0.06) / "今すぐ外へ"(+0.05) | "落ち着いて、もう少し。" | -0.02 | (なし) |
| urgent_warning | "今すぐ逃げて"(+0.1) / "信じてる"(+0.08) | "落ち着いて、もう少し。" | -0.02 | (なし) |

### stage3（ゆめ / 配信者）

| scene | 既存 | 新規 | belief | next_scene |
|---|---|---|---|---|
| chat_topic | "そのままの雰囲気で"(+0.05→about_viewer) / "近況でも聞かせて"(+0.04→about_viewer) | "スタンプだけでいいよ〜" | -0.03 | about_viewer |
| about_viewer | "どしたの？"(+0.06→feel_anxious) / "大丈夫？"(+0.05→feel_anxious) | "配信中はそういうのやめて〜" | -0.03 | feel_anxious |
| feel_anxious | "気のせいじゃない"(+0.07→ending) / "ちょっと待って"(−0.02→ending) | "いや、ちらついてないよ" | -0.04 | ending |
| ending | "絶対に気をつけて"(+0.07) / "今すぐ配信終了して"(+0.05) | "落ち着いて、もう少し。" | -0.02 | (なし) |
| urgent_warning | "今すぐ逃げて"(+0.1) / "信じてる"(+0.08) | "落ち着いて、もう少し。" | -0.02 | (なし) |

### stage4（蓮 / 男友達・プログラマー）

| scene | 既存 | 新規 | belief | next_scene |
|---|---|---|---|---|
| warm_open | "何が怖いの？"(+0.06→about_room) / "落ち着いて話して"(+0.04→about_room) | "あんまり怖がらないでよ" | -0.03 | about_room |
| cold_open | "いや、話して"(+0.05→about_room) / "大丈夫？"(−0.02→about_room) | "無理しないで休んで" | -0.03 | about_room |
| about_room | "確認した？"(+0.05→trust_check) / "気のせいじゃない？"(−0.05→trust_check) | "寝ぼけてるんじゃない？" | -0.04 | trust_check |
| trust_check | "もちろん、信じる"(+0.08→ending) / "落ち着いて"(−0.04→ending) | "どうだろうね" | -0.03 | ending |
| ending | "絶対に逃げて"(+0.07) / "今すぐ外へ"(+0.06) | "落ち着いて、もう少し。" | -0.02 | (なし) |
| urgent_warning | "今すぐ逃げて"(+0.1) / "信じてる"(+0.08) | "落ち着いて、もう少し。" | -0.02 | (なし) |

## 4. テスト

### 4.1. 追加するテスト
`tests/test_logic.gd` のプラン 29 用ループに stage1-4 を追加（合計 4 ステージ × 23 シーン）:

```gdscript
var plan30_stages = ["stage1", "stage2", "stage3", "stage4"]
for stage_id in plan30_stages:
    var data: Dictionary = JSON.parse_string(...)
    for scene in data.get("scenes", []):
        # プラン 30 で 3 択化したシーンのみ検証
        if scene.get("id") in PLAN30_SCENES:  # 23 シーンのリスト
            var choices = scene.get("choices", [])
            assert(choices.size() >= 3)
```

なおプラン 29 のループはそのまま残し、プラン 30 で 3 択化された scene のリストだけ別に管理する。

### 4.2. 既存テストの確認
- 既存の 708 OK が壊れないこと
- test_playthrough.gd が belief 値の累積変化に対応するか確認（プラン 29 で確認済み）

## 5. 実装手順

1. `docs/plans/plan30-stage1-4-3choices.md` をコミット（このファイル）
2. `stages/stage1.json` の 6 シーン (intro / distant / after_work / ghost_nervous / end / urgent_warning) に 3 択目を追加
3. `stages/stage2.json` の 6 シーン に追加
4. `stages/stage3.json` の 5 シーン に追加
5. `stages/stage4.json` の 6 シーン に追加
6. `tests/test_logic.gd` にプラン 30 用のテストを追加（23 シーン × 4 チェック = 92 件）
7. `bash tools/run_tests.sh` でテスト実行
8. exe 再ビルド
9. AI_HANDOVER.md / AI_TODO.md を更新（テスト数 708 → ?、新コミット）
10. コミット

## 6. exe 再ビルド

```bash
"/c/Users/hijik/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path C:/Users/hijik/ClaudeCode/screenlife-horror --export-release "Windows Desktop" outputs/build/screenlife-horror.exe
```

## 7. 想定リスク

- stage1 intro の "えっ、なに、なに？" → warm と "あとで聞かせて" → distant で分岐しているため、3 択目で distant ルートに入れると belief が大きく下がる
  - プラン 29 と同じ「next_scene = より低い belief の方の遷移先」方針で対応
- stage2 cold_open の "大丈夫、続けて" は belief -0.01 とほぼ中立。3 択目 (-0.04) よりマシ → cold_open への到達は Plan30 で維持
  - 既存選択肢より低い belief を入れると、cold_open 自体へ来なくなる可能性
- next_scene 設定を間違えると会話がループする → テストで choices.size() >= 3 と next_scene の存在を一緒に検証する
