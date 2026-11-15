#!/usr/bin/env bash
#
# `block-parent-session-edit.sh` の判定表。発火ログを本物の `record-firings.sh` に書かせてから
# Edit / Write の PreToolUse を流し、親の編集の拒否と素通りが期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/parent-session-edit-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# ログを手で書かずに `record-firings.sh` へ SessionStart と Skill / Agent の PostToolUse を流すのは、守りたいのが
# 「書く側の綴りを読む側が読める」という 2 本の間の約束だから(2 本はログのパスを各自で組み立てる)。
# 区切りを書くケースはそれぞれ新しいセッションにして、前のケースのログを持ち越さない。TMPDIR もこの表の間
# だけ一時ディレクトリへ向け、実際のセッションのログと混ぜない。フックは置き場所のまま走らせ、file_path は
# 本物のリポジトリのルートの下に組む(ファイルは作らない)。判定は `lib/case-table.sh` の `judge_payload`。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
source "$lib_dir/case-table.sh"

hook="$lib_dir/../block-parent-session-edit.sh"
record_hook="$lib_dir/../record-firings.sh"
repo_root="$(cd "$lib_dir/../../.." && pwd)"

TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

failed=0

# セッションの見出しを発火ログに書かせ、続けて起動したものを順に書かせる。
#
# @param $1 セッション
# @param $2 以降 起動したもの(起動した順。`agent:<subagent_type>` はサブエージェント、それ以外はスキル)
write_firings_log() {
  local session="$1" fired
  shift
  printf '{"session_id":"%s","hook_event_name":"SessionStart"}' "$session" | bash "$record_hook"
  for fired in "$@"; do
    if [[ "$fired" == agent:* ]]; then
      printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"x"}}' \
        "$session" "${fired#agent:}" | bash "$record_hook"
      continue
    fi
    printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"%s"}}' \
      "$session" "$fired" | bash "$record_hook"
  done
}

# Edit / Write の PreToolUse の入力を組む。
#
# @param $1 セッション
# @param $2 session_id と tool_input の間に挟むフィールド(`tool_name` を含み、`,` で終わる JSON)
# @param $3 tool_input の中身(`{` `}` を除いた JSON)
# @returns 入力の JSON
edit_payload() {
  printf '{"session_id":"%s",%s"tool_input":{%s}}' "$1" "$2" "$3"
}

# Edit / Write の PreToolUse を 1 回流し、判定を返す。
#
# @param $1 セッション
# @param $2 挟むフィールド(`edit_payload` と同じ)
# @param $3 tool_input の中身(`edit_payload` と同じ)
# @returns `judge_payload` の判定
edit_verdict() {
  judge_payload "$hook" "$(edit_payload "$@")"
}

# 1 件の結果を報告し、食い違いがあれば表全体を落とす。
#
# @param $1 期待
# @param $2 実際の判定
# @param $3 ケースの名前(仕様の文)
expect() {
  report_case "$1" "$2" "$3" || failed=1
}

parent_edit='"hook_event_name":"PreToolUse","tool_name":"Edit",'
parent_write='"hook_event_name":"PreToolUse","tool_name":"Write",'
# サブエージェントの中の呼び出しは、入力に `agent_id` / `agent_type` が載る(harness/case-law/process.md の実測)。
subagent_edit='"agent_id":"ab90e859b438c06a1","agent_type":"implementer","hook_event_name":"PreToolUse","tool_name":"Edit",'
subagent_write='"agent_id":"ab90e859b438c06a1","agent_type":"implementer","hook_event_name":"PreToolUse","tool_name":"Write",'
agent_id_only_edit='"agent_id":"ab90e859b438c06a1","hook_event_name":"PreToolUse","tool_name":"Edit",'

in_repo="$repo_root/rules/parent-session-edit-probe.md"
edit_in_repo="\"file_path\":\"$in_repo\",\"old_string\":\"a\",\"new_string\":\"b\""
write_in_repo="\"file_path\":\"$in_repo\",\"content\":\"x\""

write_firings_log s1 implementation-flow
expect deny "$(edit_verdict s1 "$parent_edit" "$edit_in_repo")" "implementation-flow の中で、親がリポジトリの中のファイルを Edit すると拒否される"
expect deny "$(edit_verdict s1 "$parent_write" "$write_in_repo")" "implementation-flow の中で、親がリポジトリの中のファイルを Write すると拒否される"
expect pass "$(edit_verdict s1 "$subagent_edit" "$edit_in_repo")" "implementation-flow の中でも、サブエージェントの Edit は通る"
expect pass "$(edit_verdict s1 "$subagent_write" "$write_in_repo")" "implementation-flow の中でも、サブエージェントの Write は通る"
expect pass "$(edit_verdict s1 "$agent_id_only_edit" "$edit_in_repo")" "agent_type が無く agent_id だけが載った Edit も、サブエージェントの呼び出しとして通る"
expect pass "$(edit_verdict s1 "$parent_write" "\"file_path\":\"$TMPDIR/outside.md\",\"content\":\"x\"")" "implementation-flow の中でも、親がリポジトリの外のファイルへ Write するのは通る"
expect pass "$(edit_verdict s1 "$parent_write" "\"file_path\":\"$repo_root-other/x.md\",\"content\":\"x\"")" "リポジトリのルートと同じ綴りで始まる別のフォルダへの Write は、リポジトリの外として通る"
expect pass "$(edit_verdict s1 "$parent_write" '"content":"x"')" "file_path の無い入力は通る"
expect pass "$(edit_verdict s1 "$parent_write" '"file_path":"","content":"x"')" "file_path が空の入力は通る"
expect pass "$(edit_verdict s1 "$parent_write" '"file_path":"rules/a.md","content":"x"')" "file_path が相対パスの入力は通る"

# 設定はフックを `${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/` から呼ぶので、CLAUDE_PROJECT_DIR が空なら
# cwd からの相対パスになる。リポジトリルートに cd して `./` から呼び、その綴りでも動くことを確かめる。
relative_verdict="$(
  cd "$repo_root" || exit 1
  judge_payload ./.claude/hooks/block-parent-session-edit.sh "$(edit_payload s1 "$parent_edit" "$edit_in_repo")"
)"
expect deny "$relative_verdict" "リポジトリルートから相対パスでフックを呼んでも、implementation-flow の中の親の Edit は拒否される"

# 上の 1 件はリポジトリルートを cwd にしているので、ルートを cwd から辿る実装でも通る。置き場所から
# 辿っていることは、cwd をリポジトリの外(TMPDIR)にしてフックを絶対パスで呼んで確かめる。
outside_cwd_verdict="$(
  cd "$TMPDIR" || exit 1
  edit_verdict s1 "$parent_edit" "$edit_in_repo"
)"
expect deny "$outside_cwd_verdict" "リポジトリの外を cwd にして絶対パスでフックを呼んでも、implementation-flow の中の親の Edit は拒否される"

write_firings_log s2 implementation-flow harness-record
expect pass "$(edit_verdict s2 "$parent_edit" "$edit_in_repo")" "implementation-flow の後に harness-record を起動したら、親の Edit は通る"

write_firings_log s3 implementation-flow harness-growth
expect pass "$(edit_verdict s3 "$parent_edit" "$edit_in_repo")" "implementation-flow の後に harness-growth を起動したら、親の Edit は通る"

write_firings_log s4 harness-record implementation-flow
expect deny "$(edit_verdict s4 "$parent_edit" "$edit_in_repo")" "harness-record の後に implementation-flow を起動したら、親の Edit は拒否される"

write_firings_log s5 implementation-flow claim-verification
expect deny "$(edit_verdict s5 "$parent_edit" "$edit_in_repo")" "implementation-flow の後に区切りでないスキルを起動しても、親の Edit は拒否され続ける"

write_firings_log s6 implementation-flow harness-record claim-verification
expect pass "$(edit_verdict s6 "$parent_edit" "$edit_in_repo")" "harness-record の後に区切りでないスキルを起動しても、親の Edit は通り続ける"

expect pass "$(edit_verdict s7 "$parent_edit" "$edit_in_repo")" "発火ログが無いセッションでは、親の Edit は通る"

write_firings_log s8
expect pass "$(edit_verdict s8 "$parent_edit" "$edit_in_repo")" "発火ログが見出しだけのセッションでは、親の Edit は通る"

write_firings_log s9 implementation-flow
write_firings_log s10
expect pass "$(edit_verdict s10 "$parent_edit" "$edit_in_repo")" "別のセッションで implementation-flow を起動していても、このセッションの親の Edit は通る"

write_firings_log s11 implementation-flow
expect deny "$(edit_verdict s11 "$parent_write" "\"file_path\":\"$in_repo\",\"content\":\"{\\\"agent_id\\\":\\\"x\\\"}\"")" "Write の content に agent_id の綴りがあっても、親の Write は拒否される"
expect deny "$(edit_verdict s11 "$parent_edit" "\"file_path\":\"$in_repo\",\"old_string\":\"a\",\"new_string\":\"{\\\"agent_id\\\":\\\"x\\\"}\"")" "Edit の new_string に agent_id の綴りがあっても、親の Edit は拒否される"
expect deny "$(edit_verdict s11 "$parent_edit" "\"file_path\":\"$in_repo\",\"old_string\":\"{\\\"agent_id\\\":\\\"x\\\"}\",\"new_string\":\"b\"")" "Edit の old_string に agent_id の綴りがあっても、親の Edit は拒否される"

write_firings_log s12 x-implementation-flow
expect pass "$(edit_verdict s12 "$parent_edit" "$edit_in_repo")" "名前が implementation-flow で終わるだけの別のスキルは区切りにならず、親の Edit は通る"

write_firings_log s13 agent:planner
expect deny "$(edit_verdict s13 "$parent_edit" "$edit_in_repo")" "planner を起動した後は、implementation-flow のスキルの起動が無くても親の Edit は拒否される"

write_firings_log s14 agent:implementer
expect deny "$(edit_verdict s14 "$parent_edit" "$edit_in_repo")" "implementer を起動した後は、implementation-flow のスキルの起動が無くても親の Edit は拒否される"

write_firings_log s15 agent:planner harness-record
expect pass "$(edit_verdict s15 "$parent_edit" "$edit_in_repo")" "planner の後に harness-record を起動したら、親の Edit は通る"

write_firings_log s16 harness-record agent:implementer
expect deny "$(edit_verdict s16 "$parent_edit" "$edit_in_repo")" "harness-record の後に implementer を起動したら、親の Edit は拒否される"

write_firings_log s17 agent:x-planner agent:x-implementer
expect pass "$(edit_verdict s17 "$parent_edit" "$edit_in_repo")" "名前が planner / implementer で終わるだけの別のエージェントは区切りにならず、親の Edit は通る"

# s12 / s17 の対で、後ろに付いた綴りを見る。
write_firings_log s20 implementation-flow-x
expect pass "$(edit_verdict s20 "$parent_edit" "$edit_in_repo")" "名前が implementation-flow で始まるだけの別のスキルは区切りにならず、親の Edit は通る"

write_firings_log s21 agent:planner-x agent:implementer-x
expect pass "$(edit_verdict s21 "$parent_edit" "$edit_in_repo")" "名前が planner / implementer で始まるだけの別のエージェントは区切りにならず、親の Edit は通る"

write_firings_log s22 implementation-flow harness-record-x harness-growth-x
expect deny "$(edit_verdict s22 "$parent_edit" "$edit_in_repo")" "名前が harness-record / harness-growth で始まるだけの別のスキルは外へ出る区切りにならず、親の Edit は拒否され続ける"

write_firings_log s18 agent:plan-reviewer agent:implementation-reviewer agent:Explore
expect pass "$(edit_verdict s18 "$parent_edit" "$edit_in_repo")" "planner / implementer 以外のエージェントを起動しただけでは、親の Edit は通る"

# session_id の無い入力のログは、書く側では `unknown` のパスに落ちる。そこに区切りがあっても読まない。
write_firings_log unknown implementation-flow
expect pass "$(judge_payload "$hook" "$(printf '{%s"tool_input":{%s}}' "$parent_edit" "$edit_in_repo")")" "session_id の無い入力は通る"

# 拒否文は implementer へ渡すことだけを伝え、区切りになるスキルの名前を出さない。
reason_mentions_harness_skill=no
[[ "$(edit_payload s1 "$parent_edit" "$edit_in_repo" | bash "$hook")" == *harness-* ]] && reason_mentions_harness_skill=yes
expect no "$reason_mentions_harness_skill" "拒否文に、区切りになるスキル(harness-)の名前が出ない"

exit "$failed"
