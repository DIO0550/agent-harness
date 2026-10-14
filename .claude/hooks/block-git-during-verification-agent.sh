#!/usr/bin/env bash
#
# 作業ツリーを書き換えるサブエージェントの実行中に、git add / commit / push を拒否する
# PreToolUse フック(matcher: Bash)。分類 `subagent-control`。マーカーは
# track-verification-agent-activity.sh が置き、どのエージェントが対象かもそちらが持つ。
#
# pr-391 #18: 実装検証のエージェントがミューテーションを当てている最中に git add が
# 走り、その瞬間の書き換えをコミットへ取り込んで CI が 4 ファイル 19 件落ちた
# (design-composer の pr-391)。implementer が実装を書いている最中も同じ形になる。
# implementation-flow「サブエージェントの使い方」の「返ってきたら git status を見る」は
# 戻ってきた**後**の話で、**実行中**にコミットするなとは書かれていなかった穴を塞ぐ。
# 印がある間は、呼び出し元(親かサブエージェントか)を問わず止める。
#
# CI / git hooks(層1・2)では代替できない。この競合はセッションの実行タイミングだけが原因で、
# コミット後のリポジトリの状態には痕跡が残らない。block-run-without-install.sh と同じ
# 「セッション中の行為の禁止」であり、push の時点では代替できない
# (.claude/hooks/README.md「カバー範囲と残る穴」)。層3(ここ)止まりで、発火しない
# 実行環境では効かないことを許容する(こちらも同じ扱い)。
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
# 一定時間より古いマーカーは無視する(フェイルオープン側へ倒す)。implementer だけ長いのは
# 長い実装を想定した値で(実測ではない)、1800 秒では実装の途中で git add が通りうるため。全体を
# 長くしないのは、中断で PostToolUse が来なかった検証エージェントの印まで長く git を止めるから。
#
# @param $1 マーカーのパス(`active.<subagent_type>.XXXXXX`)
# @returns そのマーカーの種類の有効期間(秒)を標準出力へ書く
stale_seconds_of() {
  local name="${1##*/}"
  local rest="${name#active.}"
  case "${rest%%.*}" in
    implementer) echo 7200 ;;
    *) echo 1800 ;;
  esac
}

now="$(date +%s)"
active=0
for marker in "$lock_dir"/active.*; do
  [ -e "$marker" ] || continue
  mtime="$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || printf '0')"
  if [ $(( now - mtime )) -le "$(stale_seconds_of "$marker")" ]; then
    active=$(( active + 1 ))
  fi
done

[ "$active" -gt 0 ] || exit 0

# 中断で残った印を利用者が探せるよう、拒否文に印の場所を出す。session_id は extract() が `"` の
# 手前で切るが `\` は残りうり、TMPDIR は制約されないので、JSON の文字列として `\` と `"` をエスケープする。
lock_dir_json="${lock_dir//\\/\\\\}"
lock_dir_json="${lock_dir_json//\"/\\\"}"
reason="作業ツリーを書き換えるサブエージェントが実行中です(分類: subagent-control。pr-391 #18 で同じ形が CI を落としています)。ミューテーション実測や実装の途中でコミットすると、その瞬間の書き換えが取り込まれます。サブエージェントの完了を待ってから git add / commit / push を実行してください。実行中の印は ${lock_dir_json}/active.* にあります。該当するサブエージェントが動いていないなら、中断で残った印です。消すかどうかは利用者に確認してください。"
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "deny",\n    "permissionDecisionReason": "%s"\n  }\n}\n' "$reason"
