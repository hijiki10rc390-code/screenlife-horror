#!/usr/bin/env bash
# screenlife-horror の Web ビルドを GitHub Pages にデプロイする
# 使い方:
#   1. 認証: gh auth login（ブラウザでログイン or PAT 貼り付け）
#   2. このスクリプトを実行: bash tools/deploy_web.sh
#
# 必要なもの:
#   - gh CLI（WSL: apt install gh / PowerShell: winget install GitHub.cli）
#   - GitHub アカウント
#   - このフォルダの master に変更がコミット済みであること

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W)"

echo "=== 1. 認証確認 ==="
if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub にログインしていません。下記を実行してください:"
  echo "  gh auth login           # ブラウザでログイン"
  echo "  gh auth login --with-token <<< <PAT>"  # PAT を使う場合
  exit 1
fi
USER="$(gh api user --jq .login)"
echo "ログイン中: $USER"

echo ""
echo "=== 2. リポジトリ作成（既存ならスキップ） ==="
REPO="screenlife-horror"
if gh repo view "$USER/$REPO" >/dev/null 2>&1; then
  echo "既存リポジトリ: https://github.com/$USER/$REPO"
else
  # public リポジトリ。GitHub Pages の無料枠を使うため public 必須
  gh repo create "$REPO" --public --description "画面越しのホラー（Godot / Web）" --source=. --remote=origin
  echo "リポジトリ作成完了"
fi

echo ""
echo "=== 3. master を push ==="
git push -u origin master || true   # 既に push 済みならエラーでも続行

echo ""
echo "=== 4. gh-pages 用ディレクトリを確認 ==="
GH_TMP="/tmp/gh-pages-tmp"
if [ ! -d "$GH_TMP" ]; then
  echo "gh-pages 用ディレクトリが見つかりません。再生成します..."
  mkdir -p "$GH_TMP"
  cp -r outputs/web/* "$GH_TMP/"
  touch "$GH_TMP/.nojekyll"
  cp "$GH_TMP/index.html" "$GH_TMP/404.html"
  cd "$GH_TMP"
  git init -b gh-pages --quiet
  git -c user.email="claude@anthropic.com" -c user.name="Claude Code" add -A
  git -c user.email="claude@anthropic.com" -c user.name="Claude Code" commit -m "Web ビルドを GitHub Pages に配置" --quiet
  cd "$ROOT"
fi

echo ""
echo "=== 5. gh-pages ブランチを push ==="
cd "$GH_TMP"
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$USER/$REPO.git"
git push -u origin gh-pages --force
cd "$ROOT"

echo ""
echo "=== 6. GitHub Pages を有効化 ==="
# 既に有効ならエラーでも続行
gh repo edit "$USER/$REPO" --enable-pages --pages-source=gh-pages 2>&1 || true

# 最新のリポジトリ設定を確認
sleep 3
echo ""
echo "=== 7. Pages 状態 ==="
gh api "repos/$USER/$REPO/pages" 2>&1 | head -20 || echo "Pages 情報の取得に失敗"

echo ""
echo "=== 完了 ==="
echo "公開 URL: https://$USER.github.io/$REPO/"
echo ""
echo "スマホでアクセスしてください。初回ロードは 30 秒〜 2 分かかる場合があります。"