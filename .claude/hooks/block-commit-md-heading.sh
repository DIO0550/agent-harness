#!/usr/bin/env bash
#
# コミット本文の行頭 `#` の禁止: `git commit` を含むコマンドで、本文の行頭（桁 0）が `#` の行を拒否する PreToolUse フック。
# 由来: d-market-git / git-workflow-plugin の no-commit-md-heading.sh（1135a0d）
#
# 方針: 本文の見出しは `<見出し>:` を単独行に置く。
#
# 入力: stdin に { "tool_input": { "command": "..." } } を含む JSON (Bash ツール呼び出し)
# 出力: 違反時に permissionDecision=deny の JSON を返す。問題なければ exit 0。
set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
. "$hook_dir/lib/command-literals.sh" || exit 0

command="$(jq -r '.tool_input.command // empty')" || exit 0
[ -n "$command" ] || exit 0

command_line_outside_literals "$command" | grep -qE '\bgit[[:space:]]+commit\b' || exit 0

scanned_text="$(heredoc_bodies "$command")"
[ -n "$scanned_text" ] || scanned_text="$command"
offending="$(printf '%s\n' "$scanned_text" | grep -n '^#' | head -3)"
[ -n "$offending" ] || exit 0

jq -n --arg lines "$offending" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("コミットメッセージ本文に行頭 `#` の行が含まれています。\n\n検出された行:\n" + $lines + "\n\n理由:\n- git は core.commentChar（既定 `#`）で始まる行をコメントとして除去します\n- `git commit -m` の時点では残りますが、後で `git commit --amend` や `git rebase --reword` をエディタ経由で行うと、その時点で該当行が黙って消えます\n- 意思決定をコミット本文に残す運用では、この欠落は記録の喪失になります\n\n対処:\n- 見出しは `<見出し>:` を単独行に置いてください（例: `背景:` `採用理由:`）\n- 見出し文字列は commit テンプレートの `decision_record.sections[].title` に揃えてください\n- どうしても行頭 `#` が必要な場合は、その行を1文字以上インデントしてください（桁0でなければ除去されません）")
  }
}'
exit 0
