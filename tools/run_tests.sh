#!/usr/bin/env bash
# tests/test_*.gd を全部実行して、成功数・失敗数を表示する。
# 使い方: bash tools/run_tests.sh
G="/c/Users/hijik/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.." || exit 1
P="$(pwd -W)"
"$G" --headless --path "$P" --import >/dev/null 2>&1
total_ok=0; total_ng=0; bad=0
for f in tests/test_*.gd; do
  log="/tmp/$(basename "$f" .gd).log"
  timeout 600 "$G" --headless --path "$P" -s "$f" > "$log" 2>&1
  code=$?
  ok=$(grep -c '^OK' "$log"); ng=$(grep -c '^NG' "$log")
  echo "$f: exit=$code OK=$ok NG=$ng"
  total_ok=$((total_ok + ok)); total_ng=$((total_ng + ng))
  [ "$code" -ne 0 ] && bad=1
  grep -E '^NG|SCRIPT ERROR|Parse Error' "$log" | head -20
done
echo "合計: OK=$total_ok NG=$total_ng"
exit $bad
