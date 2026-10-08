# screenlife-horror

PC 画面（ビデオ通話アプリ）を操作して、相手の背後に映る霊などの異変に気づき、相手に警告して救う 2D ホラーゲーム（Godot 4）。素材は実写風（SDXL で生成）。

- 形式: スクリーンライフ型。画面そのものがゲーム画面。配布は Windows（exe 書き出し）
- 設計: `docs/design.md` / 素材の検証: `docs/assets-plan.md` / 参考作品: `docs/references.md`
- 引き継ぎ: `AI_HANDOVER.md` / タスク: `AI_TODO.md`

## 動かし方（現状は縦の1本の雛形）

```powershell
& "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64.exe" --path C:\Users\hijik\ClaudeCode\screenlife-horror
```

`outputs/build/screenlife-horror.exe`（単体・約179MB）ができる。配布前に、使ったモデルのライセンスを確認すること。

- テスト: `bash tools/run_tests.sh` で全 4 種（logic / scenes / outfit_unlock / playthrough）のテストを実行。すべて OK で終了コード 0
- 合計 800 OK / 0 NG（test_logic 568 + test_scenes 50 + test_outfit_unlock 71 + test_playthrough 111）

## 遊び方（全10ステージ）

1. ステージ1 通話（練習・Mika）: 人影を指して警告。すぐ信じてくれる
2. ステージ2 通話（疑り深い相手・Aoi）: 話しかけて信頼をためる。伝え方を選ぶ（「逃げて！」が一番強い）。信頼が足りないと流される
3. ステージ3 配信（ゆめ）: コメントで警告。人影が映っている間に3回、同じ警告を投稿する。映る前に騒ぐと荒らし扱い
4. ステージ4 通話（蓮・男友達）: 25歳・プログラマー・落ち着いた口調
5. ステージ5 通話（美咲・デザイナー）: 26歳・紫系チャット
6. ステージ6 通話（結衣・学生）: 24歳・暖色系
7. ステージ7 通話（千夏・イラストレーター）: 28歳・グリーン系
8. ステージ8 通話（海・プログラマー）: 22歳・ブルー系・茶髪パーカー
9. ステージ9 通話（蒼・映像制作）: 21歳・深紫系・ピアス
10. ステージ10 通話（凛・看護師）: 23歳・ティール系・黒髪ポニーテール

救出すると次のステージへ。最後まで（10 ステージ）救うと最初へ戻る。失敗したら同じステージをやり直す。
累計救出数に応じてエンディングが分岐：1 人目「初救出！」、5 人目「あなたは頼れる人ですね」、全クリア「全員救出！クリア！」。
ステージの設定は `stages/*.json`（画像・人影の範囲・時間割・台詞）。確認用に `-- --stage=2` で開始ステージを指定できる。
衣装は 3 種類（default / pajamas / hoodie）。信頼度 0.6 で pajamas、0.85 で hoodie がアンロックされる。

## exe の書き出し

```bash
"/c/Users/hijik/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path C:/Users/hijik/ClaudeCode/screenlife-horror --export-release "Windows Desktop" outputs/build/screenlife-horror.exe
```

`outputs/build/screenlife-horror.exe`（単体・約179MB）ができる。配布前に、使ったモデルのライセンスを確認すること。

## 素材パックの作り直し（外見を変えるとき）

```bash
# 設定: stages_src/stage2.src.json（背景・人影・人物の文章）。GPU は1本ずつ実行
C:/sd/venv-cuda/Scripts/python.exe build_stage.py stages_src/stage2.src.json base     # 背景の候補
C:/sd/venv-cuda/Scripts/python.exe build_stage.py stages_src/stage2.src.json figure   # 人影の候補（黒背景）
C:/sd/venv-cuda/Scripts/python.exe build_stage.py stages_src/stage2.src.json react    # 表情3種
C:/sd/venv-cuda/Scripts/python.exe build_stage.py stages_src/stage2.src.json pack 24  # 重ね画像を書き出す（24=採用した人影の番号）
```

## 難易度の目安

```bash
python balance_report.py
```

各ステージの「気づける時間の幅」と、疑り深い相手で警告が通る最初の時刻を、設定（`stages/*.json`）から計算して表示する。

## テスト


```powershell
& "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path C:\Users\hijik\ClaudeCode\screenlife-horror -s tests/test_logic.gd
```

全部 `OK` で終了コード 0 なら成功。

## 画面の撮影（目標との比較用）

`... --path <PJ> -- --shot` で `outputs/shot_a_t02.png` `shot_b_t45.png` `shot_c_t85.png`（人影なし／淡い／はっきり）を保存。

## 素材の作り方（SDXL）

```powershell
C:\sd\venv-cuda\Scripts\python.exe sd_test.py scenes 6        # 人物＋背景を6枚
C:\sd\venv-cuda\Scripts\python.exe sd_test.py ghost <画像> x1,y1,x2,y2 "<人影のプロンプト>"   # 範囲に人影を描き足す
```

CUDA 版の専用環境 `C:\sd\venv-cuda` を使う（A1111 の venv は CPU 版で使えない）。詳細は `docs/assets-plan.md`。
