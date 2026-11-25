#!/usr/bin/env bash
#
# 一括ステージングの禁止: `git add -A` / `git add --all` / `git add .` / `git add -a` を拒否する PreToolUse フック。
# 由来: d-market-git / git-workflow-plugin の no-git-add-all.sh（1135a0d）
#
# 方針: ステージするファイルはパスで指定する。
#
# 入力: stdin に { "tool_input": { "command": "..." } } を含む JSON (Bash ツール呼び出し)
# 出力: 違反時に permissionDecision=deny の JSON を返す。問題なければ exit 0。
set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
. "$hook_dir/lib/command-literals.sh" || exit 0

command="$(jq -r '.tool_input.command // empty')" || exit 0
[ -n "$command" ] || exit 0

bulk_add_pattern='\bgit\s+add\b[^;&|]*(\s-[a-zA-Z]*A[a-zA-Z]*\b|\s--all\b|\s\.(\s|[;&|)]|$)|\s-a\b)'
command_line_outside_literals "$command" | grep -qE "$bulk_add_pattern" || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "`git add -A` / `git add --all` / `git add .` の使用は禁止されています。\n\n理由:\n- 一括ステージングは意図しないファイル（.env, credentials, 大容量バイナリ等）をコミットに含めるリスクがあります\n- セキュリティ上の問題やリポジトリの肥大化を防ぐため、ファイルは個別に指定してください\n\n推奨手順:\n1. `git status` で変更ファイルを確認\n2. `git add <ファイル名>` で必要なファイルのみを個別にステージング\n3. 複数ファイルの場合: `git add file1.txt file2.txt` またはディレクトリ指定 `git add src/`"
  }
}'
exit 0
