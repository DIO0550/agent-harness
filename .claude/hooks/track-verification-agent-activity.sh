#!/usr/bin/env bash
#
# plan-reviewer / implementation-reviewer(ミューテーション実測で作業ツリーを
# 一時的に書き換える検証エージェント)が実行中かどうかを、セッション別のマーカーで
# 記録する PreToolUse + PostToolUse フック(matcher: Task|Agent)。
# block-git-during-verification-agent.sh がこのマーカーを読む。
#
# 対応する規約: implementation-flow「サブエージェントの使い方」/ 分類 `subagent-control`。
# pr-391 #18 は、implementation-reviewer がミューテーションを当てている最中に
# git add が走り、その瞬間の書き換えをコミットへ取り込んで CI を落とした
# (design-composer の pr-391)。呼び出し側が git 操作と Task を並列で呼ぶこと自体は
# 通常のツール利用として推奨されているため、規約だけでは防げない。
#
# 呼び出し単位では相関を取らない。PreToolUse/PostToolUse の JSON に呼び出しを一意に
# 結び付ける ID が無い(record-firings.sh も session_id 単位でしか束ねていない)。
# 個々の呼び出しへ対応付けず、マーカーファイルの数だけで「現在何件実行中か」を見る
# (FIFO: 開始で1つ作り、終了で最も古い1つを消す。どれを消すかを問わなくても総数は合う)。
#
# 全 Task/Agent を常時対象にはしない。Explore や harness-counter のような
# 読み取り専用のサブエージェントは作業ツリーを書き換えないため、対象を広げても
# 実害が防げないまま誤検知だけが増える(README「誤検知で止まるフックは全体が
# 信用されなくなる」)。対象は実際にミューテーションを当てる 2 エージェントに絞る。
set -uo pipefail

input="$(cat)"
extract() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$input" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

tool_name="$(extract tool_name)"
case "$tool_name" in
  Task | Agent) ;;
  *) exit 0 ;;
esac

subagent_type="$(extract subagent_type)"
case "$subagent_type" in
  plan-reviewer | implementation-reviewer) ;;
  *) exit 0 ;;
esac

session_id="$(extract session_id)"
lock_dir="${TMPDIR:-/tmp}/agent-harness-verification-agents-${session_id:-unknown}"
mkdir -p "$lock_dir" 2>/dev/null || exit 0

case "$(extract hook_event_name)" in
  PreToolUse)
    mktemp "$lock_dir/active.XXXXXX" >/dev/null 2>&1 || true
    ;;
  PostToolUse)
    oldest="$(ls -1t "$lock_dir" 2>/dev/null | tail -1)"
    [ -n "$oldest" ] && rm -f "${lock_dir:?}/$oldest" 2>/dev/null
    ;;
esac
exit 0
