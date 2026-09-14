#!/usr/bin/env bash
#
# plan-reviewer / implementation-reviewer が作業ツリーを検証中(ミューテーション実測)の
# あいだ、git add / commit / push を拒否する PreToolUse フック(matcher: Bash)。
# 分類 `subagent-control`。マーカーは track-verification-agent-activity.sh が置く。
#
# pr-391 #18: implementation-reviewer がミューテーションを当てている最中に git add が
# 走り、その瞬間の書き換え(nodeDrag.grabNode の枝を外す形)をコミットへ取り込んで
# CI が 4 ファイル 19 件落ちた(design-composer の pr-391)。
# implementation-flow「サブエージェントの使い方」の「返ってきたら git status を見る」は
# 戻ってきた**後**の話で、**実行中**にコミットするなとは書かれていなかった穴を塞ぐ。
#
# CI / git hooks(層1・2)では代替できない。この競合はセッションの実行タイミングだけが原因で、
# コミット後のリポジトリの状態には痕跡が残らない。block-npx.sh と同じ「セッション中の
# 行為の禁止」であり、push の時点では代替できない
# (.claude/hooks/README.md「カバー範囲と残る穴」)。層3(ここ)止まりで、発火しない
# 実行環境では効かないことを許容する(block-npx.sh と同じ扱い)。
#
# 外部コマンドに依存しない(hook-canary.sh と同じ理由: jq の無い環境で
# フェイルオープンになるとしても、判定自体は bash の組み込みだけで完結させる)。
set -uo pipefail

input="$(cat)"
extract() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$input" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

command_text="$(extract command)"
[[ "$command_text" =~ git[[:space:]]+(add|commit|push)([[:space:]]|$) ]] || exit 0

session_id="$(extract session_id)"
lock_dir="${TMPDIR:-/tmp}/agent-harness-verification-agents-${session_id:-unknown}"
[ -d "$lock_dir" ] || exit 0

# 実行が異常終了して消し忘れたマーカーで恒久的にブロックし続けないよう、
# 一定時間より古いマーカーは無視する(フェイルオープン側へ倒す)。
stale_seconds=1800
now="$(date +%s)"
active=0
for marker in "$lock_dir"/active.*; do
  [ -e "$marker" ] || continue
  mtime="$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || printf '0')"
  if [ $(( now - mtime )) -le "$stale_seconds" ]; then
    active=$(( active + 1 ))
  fi
done

[ "$active" -gt 0 ] || exit 0

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "plan-reviewer / implementation-reviewer が作業ツリーを検証中です(分類: subagent-control。pr-391 #18 で同じ形が CI を落としています)。ミューテーション実測の途中でコミットすると、その瞬間の書き換えが取り込まれます。サブエージェントの完了を待ってから git add / commit / push を実行してください。"
  }
}
JSON
