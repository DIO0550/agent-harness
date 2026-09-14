#!/usr/bin/env bash
#
# マージ後の振り返り: PR のマージを検知したら、マージ後にやることを AI へ提示する
# PostToolUse フック。
#
# 提示する内容:
#   1. 意思決定が変わっていれば該当 Issue にコメントする(implementation-flow スキル フェーズ 8)
#   2. 続きの作業が要るなら新しい Issue を立てる(同上)
#   3. その回の評価を記録して PR にする(harness-record スキル)
#
# マージ自体はブロックしない。マージは人の判断で行われるので、記録が無いことを理由に
# 止めても実装者が困るだけで、記録の質は上がらないため。
#
# 入力: stdin に { "tool_name": ..., "tool_input": {...}, "tool_response": {...} } を含む JSON
# 出力: マージ検知時に additionalContext を返す。それ以外は exit 0。
set -euo pipefail

input="$(cat)"
tool_name="$(jq -r '.tool_name // empty' <<< "$input")"

# 失敗した呼び出しでは何も出さない(マージされていないため)
if jq -e '.tool_response.isError == true' <<< "$input" >/dev/null 2>&1; then
  exit 0
fi

pr_number=""

case "$tool_name" in
  mcp__github__merge_pull_request)
    pr_number="$(jq -r '.tool_input.pullNumber // empty' <<< "$input")"
    ;;
  Bash)
    # gh pr merge のみを見る。素の git merge は見ない: ベースブランチの取り込み
    # (コンフリクト解消)で日常的に走るため、拾うと誤発火のほうが多くなる。
    command="$(jq -r '.tool_input.command // empty' <<< "$input")"
    echo "$command" \
      | grep -qE '(^|[[:space:]]|[;&|(])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' \
      || exit 0
    # gh pr merge <番号> の形なら番号を拾う(省略時は空のまま)
    pr_number="$(echo "$command" \
      | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+[0-9]+' \
      | grep -oE '[0-9]+$' || true)"
    ;;
  *)
    exit 0
    ;;
esac

if [ -n "$pr_number" ]; then
  target="PR #${pr_number}"
  record_path="harness/records/pr-${pr_number}.md"
else
  target="PR"
  record_path="harness/records/pr-<番号>.md"
fi

message="${target} がマージされました。マージ後の 3 つを行ってください。

1. 意思決定が変わったところを Issue に残す
   実装・レビューを通じて計画から変わった判断(置き場所を移した / 却下していた案を
   採用した / ゴールの範囲が変わった)があれば、該当 Issue にコメントする。
   変わっていなければ書かない。
   手順: .claude/skills/implementation-flow/SKILL.md「フェーズ 8: マージ後の追記」
   Issue は Closes で閉じているが、閉じたままコメントは残せる。開け直さない。

2. 続きの作業が要るものを新しい Issue にする
   スコープ外にしたもの・決定が変わって作り直しになったものがあれば、新しい Issue を
   立てて元の Issue からリンクする。無ければ立てない。
   規範: AGENTS.md「着手した Issue は、その回で閉じる」

3. その回の評価を記録する
   harness-record スキルを実行し、${record_path} に記録を書いて別ブランチで PR を出す。
   指摘が 0 件の回も記録は残す。
   手順: .claude/skills/harness-record/SKILL.md

   記録を残すところまでで、集計(count.sh)と rules/ / .claude/skills/ /
   .claude/hooks/ の改善はここでは行わない。それは harness-growth スキルの管轄で、
   棚卸しの機会にまとめて行う。"

jq -Rn --arg msg "$message" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'

exit 0
