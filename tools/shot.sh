#!/usr/bin/env bash
# 指定ステージを実際に起動して、画面を outputs/ に撮る（ステージ1は shot_*.png、2以降は s<N>_shot_*.png）。
# 使い方: bash tools/shot.sh <ステージ番号 1〜3>
G="/c/Users/hijik/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.." || exit 1
P="$(pwd -W)"
N="${1:-1}"
timeout 180 "$G" --path "$P" -- --shot --stage="$N" 2>&1 | grep -E 'SCRIPT ERROR|Parse Error|ERROR: [^0-9]' | head -10
echo "撮影完了: ステージ$N"
