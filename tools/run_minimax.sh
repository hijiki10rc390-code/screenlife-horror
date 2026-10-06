#!/usr/bin/env bash
# 計画書（docs/plans/NN-xxx.md）を MiniMax に実装させる。画面操作なしで最後まで走る。
# 使い方: bash tools/run_minimax.sh docs/plans/01-xxx.md [最大ターン数=60]
#   - 実装の前に、主要ファイルを _archive/before_<計画名>/ にバックアップする（レビューの差分用）
#   - 許可する操作: 読み書き・編集・検索と、tools/run_tests.sh / tools/shot.sh だけ
#   - 禁止: git、ウェブアクセス、tools/・project.godot・export_presets.cfg の書き換え（実行を許した道具を書き換えさせない）
#   - balance_report.py は MiniMax に実行させない（レビューで私が実行する）
#   - 認証キーは ~/.secrets/minimax-key.txt から読む（表示・保存しない）
set -e
cd "$(dirname "$0")/.."
PLAN="$1"
MAXT="${2:-60}"
[ -f "$PLAN" ] || { echo "計画書がありません: $PLAN"; exit 1; }
NAME="$(basename "$PLAN" .md)"
mkdir -p outputs/minimax "_archive/before_$NAME"
cp main.gd audio_manager.gd webcam.gdshader balance_report.py build_stage.py "_archive/before_$NAME/" 2>/dev/null || true
cp -r tests stages "_archive/before_$NAME/" 2>/dev/null || true

export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < /c/Users/hijik/.secrets/minimax-key.txt)"
export ANTHROPIC_MODEL="MiniMax-M3[1m]"
unset ANTHROPIC_API_KEY
# 道具（Bash）のプロセスに、認証情報を引き継がせない
export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1

PROMPT="あなたはこのプロジェクト（Godot 4 のホラーゲーム screenlife-horror）の実装担当です。
$PLAN を読み、その計画だけを実装してください。計画に書かれていない変更はしないでください。
守ること:
- 回答・コードのコメントは日本語。既存コードの書き方・コメントの密度に合わせる
- 実装後に bash tools/run_tests.sh を実行し、全部成功させる。失敗したら直す
- 計画の「やらないこと」には触れない。計画と食い違う点や、バグらしきものを見つけたら、直さずに最後の報告に書く
- git は使わない。このフォルダの外のファイルは触らない
- 最後に、変更したファイル、テスト結果、気になった点を、箇条書きで短く報告する"

claude -p "$PROMPT" \
  --max-turns "$MAXT" \
  --permission-mode acceptEdits \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(bash tools/run_tests.sh:*),Bash(bash tools/shot.sh:*)" \
  --disallowedTools "Bash(git:*),WebFetch,WebSearch,Edit(tools/**),Edit(export_presets.cfg),Edit(project.godot)" \
  --output-format text \
  > "outputs/minimax/$NAME.log" 2>&1 < /dev/null
echo "完了: outputs/minimax/$NAME.log"
