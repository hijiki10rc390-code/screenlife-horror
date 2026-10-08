# プラン 31 — 選択肢に視覚的フィードバックを追加

## 0. ゴール

シーン選択肢の **believe 値（belief）を色で見える化** し、選択時の **delta 表示** で信頼度の変動をプレイヤーが体感できるようにする。

現状:
- 選択肢はすべて同じ modulate (Color(0.95, 0.95, 1.0))
- belief 変化は silent（信頼ゲージの色だけが変わる）
- 「誤った選択肢」を選んでも何の演出もない

改善:
1. 選択肢ボタンの背景に **belief の符号に応じた薄 tint** をつける（緑=信じてる、灰=中立、オレンジ=少し冷たい、赤=誤答寄り）
2. 選択時に **delta 値（+0.05 / -0.04 など）を floating 表示** する

## 1. 背景

### プラン 29/30 で増えたもの
- stage1-10 × 全シーンで 3 択目を追加
- 「誤った選択肢」が増えた分、選択の手応えが薄いとの印象が出てきた

### プレイテスト観察 (#4 関連)
- `outputs/playtest/observations.md`: 「会話の内容が薄い」「選択肢を選んでも反応が見えない」が P1〜P0
- 視覚的フィードバックを足すことでプレイヤーに「選んだ結果が伝わっている」と感じさせる

## 2. 仕様

### 2.1. 色分けルール（pre-selection tint）

各選択肢の `effect.belief` 値（_current_scene 内の choices[i]）に応じて、ボタンの **背景色 tint** を決める:

| belief 値の範囲 | tint 色 (RGBA) | 用途 |
|---|---|---|
| `>= +0.04` | `(0.30, 0.55, 0.40, 0.35)` 緑系 | 相手を安心させる返答 |
| `0.00 〜 +0.03` | `(0.50, 0.50, 0.55, 0.20)` 灰系 | ニュートラル |
| `-0.01 〜 -0.03` | `(0.65, 0.45, 0.30, 0.35)` 薄オレンジ系 | やや冷たい |
| `< -0.03` | `(0.65, 0.30, 0.30, 0.45)` 赤系 | 拒絶・無視 |

Tint は薄め（alpha 0.20〜0.45）にして、答えが明確にならないようにする。

### 2.2. tint の実装

`main.gd` に新規関数を追加:

```gdscript
# belief の符号・大きさから tint 色（RGBA）を返す
func _choice_tint_color(belief: float) -> Color:
    if belief >= 0.04:
        return Color(0.30, 0.55, 0.40, 0.35)   # 緑系
    elif belief >= 0.0:
        return Color(0.50, 0.50, 0.55, 0.20)   # 灰系
    elif belief >= -0.03:
        return Color(0.65, 0.45, 0.30, 0.35)   # 薄オレンジ系
    else:
        return Color(0.65, 0.30, 0.30, 0.45)   # 赤系


# tint を適用した StyleBoxFlat を作って返す（ボタン用に使い回す）
func _choice_tint_stylebox(tint: Color) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = tint
    sb.border_width_left = 2
    sb.border_width_top = 2
    sb.border_width_right = 2
    sb.border_width_bottom = 2
    sb.border_color = Color(1, 1, 1, 0.25)
    sb.corner_radius_top_left = 4
    sb.corner_radius_top_right = 4
    sb.corner_radius_bottom_left = 4
    sb.corner_radius_bottom_right = 4
    return sb
```

`_show_scene_buttons(choices)` の Button 生成時に `add_theme_stylebox_override("normal", _choice_tint_stylebox(...))` で適用。

### 2.3. delta の floating 表示（post-selection）

`_on_scene_choice(choice_idx)` 内で、選択直後に delta 表示 Label を出して 0.6 秒で消す:

```gdscript
# 選択時の delta を一発表示するラベル。_on_scene_choice 内に追加
var delta := float(eff.get("belief", 0.0))
if absf(delta) >= 0.01:
    _show_choice_delta(choice_idx, delta)
```

```gdscript
# delta を floating label で表示。0.6 秒で fadeout して queue_free
func _show_choice_delta(choice_idx: int, delta: float) -> void:
    var label := Label.new()
    var s := ("+" if delta > 0 else "") + "%.2f" % delta
    label.text = s
    # ボタンの隣（縦に並ぶボタンの下）に表示
    var btn_pos := Vector2(1035, _scene_btns[choice_idx].position.y + 12 if choice_idx < _scene_btns.size() else Vector2(1035, VIDEO_POS.y + VIDEO_SIZE.y - 50))
    label.position = btn_pos
    # delta 値に応じて色
    label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4, 1.0) if delta >= 0 else Color(0.95, 0.4, 0.4, 1.0))
    add_child(label)
    # 0.6 秒で fadeout
    var tw := create_tween()
    tw.tween_property(label, "modulate:a", 0.0, 0.6)
    tw.tween_callback(label.queue_free)
```

### 2.4. 信頼ゲージのアニメーション速度

現行の `0.5x` 速度は控えめなので、`1.0x` に上げて変化を体感しやすくする:

```gdscript
# 変更前
trust_bar_fill.size.x = move_toward(trust_bar_fill.size.x, target_w, delta * VIDEO_SIZE.x * 0.5)
# 変更後
trust_bar_fill.size.x = move_toward(trust_bar_fill.size.x, target_w, delta * VIDEO_SIZE.x * 1.0)
```

## 3. 実装手順

1. `docs/plans/plan31-choice-feedback.md` をコミット（このファイル）
2. `main.gd` に `_choice_tint_color()` / `_choice_tint_stylebox()` を追加
3. `_show_scene_buttons` で各 choice に tint を適用
4. `_on_scene_choice` に `_show_choice_delta()` 呼び出しを追加
5. `_show_choice_delta()` を実装
6. 信頼ゲージのアニメーション速度を 1.0x に変更
7. `tests/test_logic.gd` に以下を追加:
   - `_choice_tint_color(belief=0.05)` が緑系（g が一番大きい）
   - `_choice_tint_color(belief=0.0)` が灰系（r=g=b）
   - `_choice_tint_color(belief=-0.02)` がオレンジ系（r>g>b）
   - `_choice_tint_color(belief=-0.05)` が赤系（r > g 且つ r > b）
   - `_show_scene_buttons` で `belief >= 0.04` の選択肢に緑系 stylebox が適用されている
8. `bash tools/run_tests.sh` でテスト実行
9. exe 再ビルド
10. AI_HANDOVER.md / AI_TODO.md / README.md を更新
11. コミット / push

## 4. テスト

### 4.1. 追加するテスト
- `_choice_tint_color` の挙動: belief の境界値で正しい tint を返すか（4 件）
- `_show_scene_buttons` 実行後に `theme_stylebox` が設定されているか（1 件 × 数ステージ）
- pre-existing 800 OK が壊れないこと

### 4.2. 既存テストの確認
- test_playthrough.gd の信念値累積依存テスト
- test_scenes.gd の選択肢ボタン数テスト
- test_logic.gd の選択肢 belief 反映テスト

## 5. exe 再ビルド

```bash
"/c/Users/hijik/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path C:/Users/hijik/ClaudeCode/screenlife-horror --export-release "Windows Desktop" outputs/build/screenlife-horror.exe
```

## 6. 想定リスク

- 色分けが見えるようになると、プレイヤーが常に緑を選ぶようになり tension が下がる
  - tint を薄め（alpha 0.20〜0.45）にして subtle にとどめる
  - 誤答でも救出できるように、belief の累積合計は ±0.5 以内に保つべき（plan30 で達成済み）
- delta ラベルが他の UI と被る可能性
  - 画面右側のチャット欄を避けて位置決め
- 既存テストの stylebox 期待値が変わる可能性
  - テストを追加する前に既存 800 OK の状態を確認
