#!/usr/bin/env bash
#
# implementation-flow の中で、親セッションがリポジトリの中のファイルを Edit / Write するのを拒否する
# PreToolUse フック(matcher: Edit|Write)。サブエージェントの編集と、リポジトリの外のファイルと、
# implementation-flow の外(Skill ツールで起動した harness-record / harness-growth)での親の編集は止めない。
#
# 対応する規約: implementation-flow「役割の分担」の「親はリポジトリの中のファイルを編集しない」。
#
# 親とサブエージェントは入力の `agent_id` で見分ける。サブエージェントの中の Edit / Write の PreToolUse には
# `agent_id` / `agent_type` が載り、親の呼び出しには無く、`session_id` は共通だった(harness/case-law/process.md
# 「サブエージェントの起動とフックの入力を実測した」)。PostToolUse に `agent_id` が載るかは測っていないので、
# PreToolUse に置く。
#
# implementation-flow の中かどうかは、record-firings.sh が書く発火ログの区切りで決める。中に入る区切りは
# スキル implementation-flow とエージェント planner / implementer の起動、外へ出る区切りはスキル
# harness-record / harness-growth の起動で、最後に当たった区切りが中に入る側なら拒否する。ログが無い・
# 区切りが 1 つも無い・session_id が無いなら外として通す(区切りが見えないまま止めると、フローの外の
# 編集まで止まる)。
#
# planner / implementer を呼ぶのは implementation-flow だけなので、起動されていれば flow の中と言える。
# Skill ツールを通らない起動(手順を読んで進める回・打ったスラッシュコマンド)は、スキルの起動がログに
# 残らない(.claude/hooks/README.md「カバー範囲と残る穴」)。flow の始まりに Skill ツールでの起動を規約で
# 求める案は採らない(指示頼みで、まさにそこが守られない)。
#
# リポジトリのルートは CLAUDE_PROJECT_DIR ではなく、このファイルの置き場所から辿る。セッションの中で
# 見た CLAUDE_PROJECT_DIR は空だった(harness/case-law/process.md「起動の形で発火が割れた対照」)。
#
# 発火ログのパスと値の取り出しは record-firings.sh と同じ綴りをこのファイルにも持つ。共有部品へ切り出さない
# のは、読めなかったときに PreToolUse のフェイルオープンへ黙って吸われるため(lib/case-table.sh
# 「フック本体は共有しない」)。2 本の綴りが揃っていることは、本物の record-firings.sh にログを書かせて
# 流す判定表(lib/parent-session-edit-cases.sh)が守る。
#
# 層 3(ここ)にしか置けない。誰が編集したかはコミットに残らないので、git hooks と CI では代替できない
# (.claude/hooks/README.md「カバー範囲と残る穴」)。
#
# 外部コマンドは grep だけを使う。無くて落ちたときは区切りが見えないので通す側に倒れる。
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 0

input="$(cat)"
extract() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$input" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# 本文(content / new_string / old_string)に同じ綴りがあっても、JSON 文字列の中では引用符が \" に
# エスケープされるのでこの形には当たらない。
in_subagent_pattern='"agent_id"[[:space:]]*:'
[[ "$input" =~ $in_subagent_pattern ]] && exit 0

# repo_root は絶対パスなので、空・相対の file_path もこの前方一致で外れる。
file_path="$(extract file_path)"
[[ "$file_path" == "$repo_root"/* ]] || exit 0

session_id="$(extract session_id)"
[ -n "$session_id" ] || exit 0
log_file="${TMPDIR:-/tmp}/agent-harness-firings-${session_id}.log"
[ -f "$log_file" ] || exit 0

flow_entry_pattern=$'\t(skill\timplementation-flow|agent\t(planner|implementer))$'
flow_exit_pattern=$'\tskill\t(harness-record|harness-growth)$'
last_flow_boundary="$(grep -E -e "$flow_entry_pattern" -e "$flow_exit_pattern" "$log_file" 2>/dev/null | tail -n 1)"
[[ "$last_flow_boundary" =~ $flow_entry_pattern ]] || exit 0

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "implementation-flow の中で、親セッションがリポジトリの中のファイルを編集しようとしています(分類: subagent-control)。implementation-flow では親は指示役で、編集は implementer が担います(implementation-flow「役割の分担」)。この Edit / Write は implementer に渡してください。"
  }
}
JSON
exit 0
