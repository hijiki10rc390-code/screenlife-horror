# GitHub Pages デプロイ手順（screenlife-horror / Web ビルド）

スマホからのテスト・プレイのため、Web ビルドを GitHub Pages に配置する手順。

## 前提
- `gh` CLI がこの環境にないため、リポジトリ作成と最初の push は手動で行う
- リポジトリは **public** で作る（GitHub Pages の無料枠では private + Pages は不可）
- 既に master ブランチには Web 関連の変更がコミット済み（commit 6906eb0）

## 手順

### 1. GitHub でリポジトリを作成

ブラウザで https://github.com/new を開き：

- **Repository name**: `screenlife-horror`
- **Visibility**: `Public` を選ぶ（**重要**：Pages を無料で使うため）
- 「Initialize this repository with:」は **何もチェックしない**（空のまま作る）
- ページ下の「Create repository」をクリック

### 2. ローカーカル master を push

PowerShell を開いて：

```powershell
cd C:\Users\hijik\ClaudeCode\screenlife-horror
git remote add origin https://github.com/<あなたのユーザー名>/screenlife-horror.git
git push -u origin master
```

GitHub の認証が聞かれる。ユーザー名・パスワード入力。
（パスワードは PAT を使う — 2FA 設定済みの場合は Settings > Developer settings > Personal access tokens で発行）

### 3. gh-pages ブランチを push

`/tmp/gh-pages-tmp/` に Web ビルド用のローカルリポを 1 個作ってある（commit 1 個）。
それを push する：

```powershell
cd C:\tmp\gh-pages-tmp    # WSL から持ってきた場合はパスを調整
git remote add origin https://github.com/<あなたのユーザー名>/screenlife-horror.git
git push -u origin gh-pages
```

### 4. GitHub Pages を有効化

ブラウザで GitHub のリポジトリページを開き：

1. **Settings** タブをクリック
2. 左メニューの **Pages** をクリック
3. **Source**: `Deploy from a branch` を選ぶ
4. **Branch**: `gh-pages` を選ぶ / フォルダは `/ (root)` のまま
5. Save ボタンをクリック

数十秒後に「Your site is live at https://<ユーザー名>.github.io/screenlife-horror/」と表示される。

### 5. スマホでアクセス

スマホのブラウザ（Chrome / Safari）で：

```
https://<あなたのユーザー名>.github.io/screenlife-horror/
```

を開く。

## 確認チェックリスト

- [ ] ページが開く（白い画面に「Loading...」が出る）
- [ ] 数十秒後、Godot のスプラッシュ画面 → タイトル画面が出る
- [ ] 「はじめから」をタップ → ステージ選択
- [ ] 「応答する」をタップ → 着信音（鳴れば OK）
- [ ] 映像の怪しいところ（人影が出ている部分）をタップ → マーカーが出て警告

## うまくいかないとき

### 真っ白のまま動かない
- 開発者ツール（PC の Chrome で F12）を開いて Console を確認
- よくあるエラー: `SharedArrayBuffer is not defined` → `index.html` の COOP/COEP ヘッダーの問題。Godot のデフォルト HTML で出ているはずなので、もう少し時間を置く（wasm のロードに時間がかかってる可能性）

### 音声が出ない（iOS Safari）
- iOS の自動再生制限。タイトル画面で「はじめから」をタップ後に鳴るはず
- それでも無音なら、着信音の代わりに短い無音を鳴らす「unlock」処理を入れる必要がある

### 操作が重い・FPS が低い
- Web のサイズが大きい（43MB）。モバイル回線でロードに 1〜2 分かかる
- ロード後、操作が重い場合は SubViewport の更新モードを `UPDATE_WHEN_VISIBLE` に変更する改修が必要

### タップが反応しない
- モバイルブラウザでタッチイベントをマウスイベントに変換する処理が動いていない可能性
- 既に `main.gd:1107` で `InputEventScreenTouch` も拾うように改修済み

## 次のステップ（任意）

- 音声アンロック処理を iOS Safari に対応させる
- キーボード操作（Esc / Enter / 1,2,3 / R）のタッチ UI 化
- SubViewport 更新の軽量化
- ファイルサイズの最適化（PNG → WebP、WAV → OGG）

## 更新方法

Web ビルドを更新する場合：

1. `cd C:\Users\hijik\ClaudeCode\screenlife-horror`
2. （変更を加える）
3. Web ビルド：`outputs\web\` に再エクスポート

```powershell
& 'C:\Users\hijik\AppData\Local\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --export-release "Web" "outputs/web/index.html"
```

4. `/tmp/gh-pages-tmp/` に `outputs/web/*` をコピーし、コミット・push