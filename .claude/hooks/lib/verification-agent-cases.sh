#!/usr/bin/env bash
#
# 作業ツリーを書き換えるサブエージェントの実行中フラグの判定表。
# `track-verification-agent-activity.sh` と `block-git-during-verification-agent.sh` へ
# Task/Agent と git の呼び出しを順に流し、起動の拒否と git 操作の拒否(拒否文に載る印の場所を
# 含む)が期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/verification-agent-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 2 本を通しで流すのは、守りたいのが片方の判定ではなく「印が残っている間だけ git 操作が
# 止まる」という 2 本の間の約束だから。ケースごとに session_id を分け、前のケースの印を
# 持ち越さない。TMPDIR もこの表の間だけ一時ディレクトリへ向け、実際のセッションの印と混ぜない。
#
# 判定(JSON として読んで `deny` か・フックが 0 で終わるか)は `lib/case-table.sh` の
# `judge_payload` が持つ。入力の JSON は printf で組む。
#
# **Agent / Task の入力は Agent ツールの引数名に合わせて組んだもので、実物の PreToolUse から写していない。**
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
source "$lib_dir/case-table.sh"
track_hook="$lib_dir/../track-verification-agent-activity.sh"
block_hook="$lib_dir/../block-git-during-verification-agent.sh"

TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

failed=0

# Task/Agent のフックへ 1 回分の呼び出しを流し、判定を返す。ツール名は `TOOL_NAME` で
# 差し替えられる(既定は Agent)。
#
# @param $1 セッション(ケースごとに分ける)
# @param $2 `PreToolUse` / `PostToolUse`
# @param $3 tool_input の中身(`{` `}` を除いた JSON)
# @returns `judge_payload` の判定
agent_verdict() {
  local payload
  payload="$(printf '{"session_id":"%s","hook_event_name":"%s","tool_name":"%s","tool_input":{%s}}' \
    "$1" "$2" "${TOOL_NAME:-Agent}" "$3")"
  judge_payload "$track_hook" "$payload"
}

# git コマンドを書いた Bash の呼び出しの入力を組む(git は実行しない)。
#
# @param $1 セッション
# @param $2 コマンド(省くと `git add .`)
# @returns 入力の JSON
git_payload() {
  printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "$1" "${2:-git add .}"
}

# git コマンドを書いた Bash の呼び出しを流し、判定を返す(git は実行しない)。
#
# @param $1 セッション
# @param $2 コマンド(省くと `git add .`)
# @returns `judge_payload` の判定
git_verdict() {
  judge_payload "$block_hook" "$(git_payload "$@")"
}

# セッションの印をすべて指定した秒数だけ前の時刻へ戻す。印の有効期間(種類ごとに違う)を
# 確かめるため。`date -d @` は GNU、`date -r` は BSD の綴り。
#
# @param $1 セッション
# @param $2 戻す秒数
backdate_markers() {
  local then stamp
  then=$(( $(date +%s) - $2 ))
  stamp="$(date -d "@$then" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$then" +%Y%m%d%H%M.%S)"
  touch -t "$stamp" "$TMPDIR/agent-harness-verification-agents-$1"/active.*
}

# 1 件の結果を報告し、食い違いがあれば表全体を落とす。
#
# @param $1 期待
# @param $2 実際の判定
# @param $3 ケースの名前(仕様の文)
expect() {
  report_case "$1" "$2" "$3" || failed=1
}

foreground_implementation_reviewer='"subagent_type":"implementation-reviewer","prompt":"x"'
foreground_plan_reviewer='"subagent_type":"plan-reviewer","prompt":"x"'
background_implementation_reviewer='"subagent_type":"implementation-reviewer","prompt":"x","run_in_background":true'
background_plan_reviewer='"subagent_type":"plan-reviewer","prompt":"x","run_in_background":true'
foreground_implementer='"subagent_type":"implementer","prompt":"x"'
background_implementer='"subagent_type":"implementer","prompt":"x","run_in_background":true'

agent_verdict s1 PreToolUse "$foreground_implementation_reviewer" >/dev/null
expect deny "$(git_verdict s1)" "前面で起動した implementation-reviewer の実行中は git add が拒否される"
expect deny "$(git_verdict s1 'git commit -m x')" "前面で起動した implementation-reviewer の実行中は git commit が拒否される"
expect deny "$(git_verdict s1 'git push')" "前面で起動した implementation-reviewer の実行中は git push が拒否される"
expect pass "$(git_verdict s1 'git status --porcelain')" "実行中でも git status は止まらない"

agent_verdict s2 PreToolUse "$foreground_plan_reviewer" >/dev/null
expect deny "$(git_verdict s2)" "前面で起動した plan-reviewer の実行中は git add が拒否される"

TOOL_NAME=Task agent_verdict s3 PreToolUse "$foreground_implementation_reviewer" >/dev/null
expect deny "$(git_verdict s3)" "ツール名が Task でも、前面で起動した implementation-reviewer の実行中は git add が拒否される"

agent_verdict s4 PreToolUse "$foreground_implementation_reviewer" >/dev/null
agent_verdict s4 PostToolUse "$foreground_implementation_reviewer" >/dev/null
expect pass "$(git_verdict s4)" "前面で起動した implementation-reviewer が終わると git add が通る"

expect pass "$(git_verdict s0)" "対象のエージェントを起動していないセッションでは git add が通る"

expect deny "$(agent_verdict s5 PreToolUse "$background_implementation_reviewer")" "run_in_background: true を明示した implementation-reviewer は起動が拒否される"
expect deny "$(agent_verdict s6 PreToolUse "$background_plan_reviewer")" "run_in_background: true を明示した plan-reviewer は起動が拒否される"
expect deny "$(TOOL_NAME=Task agent_verdict s7 PreToolUse "$background_implementation_reviewer")" "ツール名が Task でも、run_in_background: true を明示した起動は拒否される"
expect deny "$(agent_verdict s8 PreToolUse '"subagent_type":"plan-reviewer","prompt":"x","run_in_background": true')" "キーと値の間に空白があっても、背景起動は拒否される"

agent_verdict s9 PreToolUse "$background_implementation_reviewer" >/dev/null
expect pass "$(git_verdict s9)" "背景起動が拒否されたときは印が残らず、git add は止まらない"

agent_verdict s10 PreToolUse "$foreground_implementation_reviewer" >/dev/null
agent_verdict s10 PreToolUse "$background_plan_reviewer" >/dev/null
expect deny "$(git_verdict s10)" "前面の実行中に背景の起動が拒否されても、git add は拒否され続ける"

agent_verdict s14 PreToolUse "$foreground_implementation_reviewer" >/dev/null
expect pass "$(agent_verdict s14 PostToolUse "$background_implementation_reviewer")" "PostToolUse では、背景起動の入力でも拒否を返さない"
expect pass "$(git_verdict s14)" "PostToolUse では、背景起動の入力でも印を消す"

agent_verdict s15 PreToolUse "$foreground_implementer" >/dev/null
expect deny "$(git_verdict s15)" "前面で起動した implementer の実行中は git add が拒否される"

agent_verdict s16 PreToolUse "$foreground_implementer" >/dev/null
agent_verdict s16 PostToolUse "$foreground_implementer" >/dev/null
expect pass "$(git_verdict s16)" "前面で起動した implementer が終わると git add が通る"

expect deny "$(agent_verdict s17 PreToolUse "$background_implementer")" "run_in_background: true を明示した implementer は起動が拒否される"

# 残った印の種類は有効期間でしか外から見えないので、最後に印を古くして見分ける。implementer の印を
# 先に古くしておくのは、種類を問わず最も古い印を消す実装だと implementer の印が消えるようにするため。
agent_verdict s18 PreToolUse "$foreground_implementer" >/dev/null
backdate_markers s18 3600
agent_verdict s18 PreToolUse "$foreground_implementation_reviewer" >/dev/null
agent_verdict s18 PostToolUse "$foreground_implementation_reviewer" >/dev/null
backdate_markers s18 3600
expect deny "$(git_verdict s18)" "implementation-reviewer が終わって消えるのはその印で、先に起動した implementer の印は残る"

# 逆の起動順。種類を問わず最も新しい印を消す実装だと implementer の印が消え、残った
# implementation-reviewer の印が 1 時間たって無視されて git add が通る。先に起動した側の印を
# 古くするのは、どちらが新しいかを作成時刻の細かさに頼らないため。
agent_verdict s22 PreToolUse "$foreground_implementation_reviewer" >/dev/null
backdate_markers s22 3600
agent_verdict s22 PreToolUse "$foreground_implementer" >/dev/null
agent_verdict s22 PostToolUse "$foreground_implementation_reviewer" >/dev/null
backdate_markers s22 3600
expect deny "$(git_verdict s22)" "implementation-reviewer が終わって消えるのはその印で、後から起動した implementer の印は残る"

agent_verdict s23 PreToolUse "$foreground_implementation_reviewer" >/dev/null
agent_verdict s23 PreToolUse "$foreground_implementation_reviewer" >/dev/null
agent_verdict s23 PostToolUse "$foreground_implementation_reviewer" >/dev/null
expect deny "$(git_verdict s23)" "同じ種類を 2 件起動して 1 件だけ終わっても、残る 1 件の実行中は git add が拒否される"

agent_verdict s19 PreToolUse "$foreground_implementer" >/dev/null
backdate_markers s19 3600
expect deny "$(git_verdict s19)" "implementer の印は 1 時間たっても有効で、git add が拒否される"

agent_verdict s20 PreToolUse "$foreground_implementation_reviewer" >/dev/null
backdate_markers s20 3600
expect pass "$(git_verdict s20)" "implementation-reviewer の印は 1 時間たつと古い印として無視され、git add が通る"

agent_verdict s24 PreToolUse "$foreground_implementer" >/dev/null
backdate_markers s24 10800
expect pass "$(git_verdict s24)" "implementer の印は 3 時間たつと古い印として無視され、git add が通る"

# 印の場所は拒否文(JSON の文字列)へ埋まるので、`"` と `\` を含む TMPDIR で綴りを見る。
# JSON として読めることは judge_payload が見る(壊れていれば error になる)。TMPDIR は
# この呼び出しだけ差し替え、他のケースの印と同じ場所に置かない。
quoted_tmpdir="$TMPDIR/q\"x\\y"
mkdir -p "$quoted_tmpdir"
TMPDIR="$quoted_tmpdir" agent_verdict s25 PreToolUse "$foreground_implementation_reviewer" >/dev/null
expect deny "$(TMPDIR="$quoted_tmpdir" judge_payload "$block_hook" "$(git_payload s25)")" "TMPDIR に \" と \\ が入っていても、拒否文は JSON として読める"
marker_location="$(printf '%s' "$(TMPDIR="$quoted_tmpdir" bash "$block_hook" <<<"$(git_payload s25)")" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])' 2>/dev/null)"
marker_location_in_reason=missing
if [[ "$marker_location" == *"$quoted_tmpdir/agent-harness-verification-agents-s25/active.*"* ]]; then
  marker_location_in_reason=present
fi
expect present "$marker_location_in_reason" "拒否文に印の場所が、TMPDIR の綴りのまま載る"

expect pass "$(agent_verdict s21 PreToolUse '"subagent_type":"planner","prompt":"x","run_in_background":true')" "planner は背景で起動しても拒否されない"
expect pass "$(agent_verdict s11 PreToolUse '"subagent_type":"Explore","prompt":"x","run_in_background":true')" "対象外のエージェントは背景で起動しても拒否されない"
expect pass "$(agent_verdict s12 PreToolUse '"subagent_type":"plan-reviewer","prompt":"x","run_in_background":false')" "run_in_background が false なら拒否されない"
expect pass "$(agent_verdict s13 PreToolUse '"subagent_type":"plan-reviewer","prompt":"\"run_in_background\":true と書いてある"')" "prompt の本文に run_in_background: true と書いてあっても、前面起動なら拒否されない"

exit "$failed"
