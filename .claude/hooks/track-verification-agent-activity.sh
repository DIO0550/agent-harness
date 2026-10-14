#!/usr/bin/env bash
#
# 作業ツリーを書き換えるサブエージェント(対象は下の case)が実行中かどうかを、セッション別の
# マーカーで記録する PreToolUse + PostToolUse フック(matcher: Task|Agent)。
# `run_in_background: true` を明示した起動は拒否する。block-git-during-verification-agent.sh が
# このマーカーを読む。
#
# 対応する規約: implementation-flow「サブエージェントの使い方」/ 分類 `subagent-control`。
# 実行中の git 操作を止める理由と止める相手は block-git-during-verification-agent.sh の冒頭。
#
# 呼び出し単位では相関を取らない。Task/Agent の PreToolUse と PostToolUse には同じ `tool_use_id` が
# 載る(実測)が、「現在何件実行中か」はマーカーファイルの数だけで答えられるので使っていない
# (FIFO: 開始で1つ作り、終了で同じ種類の最も古い1つを消す。どれを消すかを問わなくても
# 種類ごとの総数は合う)。ファイル名に種類を入れるのは、印の有効期間を種類で変えるため
# (block-git-during-verification-agent.sh)。
#
# 「終了」は Task/Agent の PostToolUse で、エージェントの完了ではない。前面で起動すると完了時に来る
# (背景へ移された場合は、移された時点で来ると読める)が、背景で起動すると起動の直後に来るので、
# 実行中でも印は残らない。そのため対象のエージェントは `run_in_background: true` を明示した起動を
# PreToolUse で拒否し、印も作らない。塞いでいないのは、前面で起動したあと背景へ移された場合
# (実測した実行環境では、120 秒を超えた起動は約 120 秒で移された)。移されるかは PreToolUse の入力には
# 現れない。`run_in_background` を省いて同じメッセージに並べて起動した場合は未測。実測の回数と
# 未測の範囲は harness/case-law/process.md。
#
# planner や harness-counter など、道具か定義で作業ツリーを書き換えないエージェントは対象外。
# 対象にすると背景で起動できなくなり、定義に反した書き換えは返った後の `git status` で見つかる
# (implementation-flow「サブエージェントの使い方」)。
set -uo pipefail

input="$(cat)"
extract() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$input" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

tool_name="$(extract tool_name)"
event_name="$(extract hook_event_name)"
case "$tool_name" in
  Task | Agent) ;;
  *) exit 0 ;;
esac

subagent_type="$(extract subagent_type)"
# 作業ツリーを書き換えるサブエージェント。plan-reviewer / implementation-reviewer は実測のために
# 一時的に書き換えうる。implementer は実装を書く。
case "$subagent_type" in
  plan-reviewer | implementation-reviewer | implementer) ;;
  *) exit 0 ;;
esac

# 真偽値は引用符で囲まれないので extract() では読めない。prompt 本文に同じ綴りがあっても、
# JSON 文字列の中では引用符が \" にエスケープされるのでこの形には当たらない。
# 拒否を返してよいのは PreToolUse だけ(PostToolUse の時点ではもう起動している)。
background_pattern='"run_in_background"[[:space:]]*:[[:space:]]*true'
if [ "$event_name" = "PreToolUse" ] && [[ "$input" =~ $background_pattern ]]; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "作業ツリーを書き換えるサブエージェントは背景で起動できません(分類: subagent-control)。背景で起動すると実行中の印が起動の直後に消え、作業ツリーを書き換えている途中の git add / commit / push を止められません。run_in_background を付けずに前面で起動し直してください。"
  }
}
JSON
  exit 0
fi

session_id="$(extract session_id)"
lock_dir="${TMPDIR:-/tmp}/agent-harness-verification-agents-${session_id:-unknown}"
mkdir -p "$lock_dir" 2>/dev/null || exit 0

case "$event_name" in
  PreToolUse)
    mktemp "$lock_dir/active.$subagent_type.XXXXXX" >/dev/null 2>&1 || true
    ;;
  PostToolUse)
    oldest="$(ls -1t "$lock_dir"/active."$subagent_type".* 2>/dev/null | tail -1)"
    [ -n "$oldest" ] && rm -f "$oldest" 2>/dev/null
    ;;
esac
exit 0
