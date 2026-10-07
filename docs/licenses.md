# 素材・モデルのライセンス（配布前確認）

> 2026-10-07 作成。配布前に必ず目を通すこと。

## 概要

このゲームは以下の AI モデル・ライブラリで生成した素材を使っている。
配布前に、各ライセンスで「商用利用 OK か」「表記義務があるか」を再確認すること。

| 素材 | 生成元 | ライセンス | 商用利用 |
|---|---|---|---|
| 人物・衣装・人影・表情 | **RealVisXL V5.0**（`SG161222/RealVisXL_V5.0`） | CreativeML Open RAIL++-M | ✅ 可（用途制限あり） |
| 上記の補助（任意） | **SDXL 1.0 base**（`stabilityai/stable-diffusion-xl-base-1.0`） | CreativeML Open RAIL++-M | ✅ 可（用途制限あり） |
| 輪郭切り出し | **rembg**（`danielgatis/rembg`） | MIT | ✅ 可（表記任意） |
| 顔のランドマーク | **face_alignment**（`1adrianb/face-alignment`） | Apache-2.0 / BSD | ✅ 可（表記必要） |
| 画像処理 | **Pillow (PIL)** | HPND | ✅ 可 |
| 数値計算 | **numpy** | BSD-3-Clause | ✅ 可 |
| 音の合成 | 自作（`tools/make_sounds.py` / `tools/make_lunge_se.py`） | — | ✅ 自作 |
| Godot エンジン | **Godot 4.7.2-stable** | MIT | ✅ 可 |

## 商用利用の可否（要点のみ）

### RealVisXL V5.0
- ライセンス: CreativeML Open RAIL++-M（OpenRAIL の拡張）
- 商用利用: **可** だが「禁止用途」の範囲が広い（違法・差別的・偽情報・性的搾取など）
- 配布時にモデル自体を再配布する場合は `OTHERWISE_LICENSE.md` を同梱
- 出典: https://huggingface.co/SG161222/RealVisXL_V5.0

### SDXL 1.0 base
- ライセンス: CreativeML Open RAIL++-M
- 商用利用: **可**（生成画像の所有権は利用者）
- 禁止用途: 違法コンテンツ・個人攻撃・性的搾取・偽情報など
- 出典: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md

### rembg
- ライセンス: MIT
- 商用利用: 可

### face_alignment
- ライセンス: BSD-3-Clause（コード）/ Apache-2.0（モデル）
- 商用利用: 可

## このゲームにおける禁止事項との適合

このゲームのコンテンツ方針（`docs/character-direction.md`）:
- キャラクターは成人（23〜28 歳）
- 露骨な性的描写なし
- 暴力は限定的（人影が映る・襲いかかる演出。血・武器などグロテスク要素なし）
- 実在人物には似せない

Open RAIL++-M の典型的な禁止事項:
- ❌ 違法コンテンツ
- ❌ 個人への嫌がらせ・誹謗中傷
- ❌ 性的搾取
- ❌ 偽情報（ディープフェイク含む）
- ❌ 差別

→ このゲームのコンテンツはいずれにも該当しない。**配布可** と判断できる。

## 配布時に同梱すべきもの：
- ✅ 各モデルの LICENSE ファイル（Open RAIL の義務）
- ✅ このゲームが AI 生成素材を使っていることの説明（README 等）
- ❌ 個別画像の出典表記は不要（Open RAIL は「モデル利用のライセンス」であって「画像 1 枚ずつに著作権表示が必要」ではない）

## やらないこと

- モデルファイルの再配布（HuggingFace / CivitAI からのリンクで配布する）
- 画像 1 枚ずつの作者表記
- 生成に使ったプロンプトの公開義務

## 今後の更新

- 新しいモデルを採用したら表に追加する
- ライセンスが改定されたら再確認する（Stability AI は SD3 から Community License に変わった）