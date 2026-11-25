#!/usr/bin/env bash
#
# Issue を作る呼び出し(`gh issue create` / `gh api` の issues への POST / `mcp__github__issue_write` の create)が、
# 作業の種類を決めていなければ拒否する PreToolUse フック(`implementation-flow` フェーズ 1「種類の確定」の手順 4)。
#
# 何を満たせば通すか・どの形を作成とみなすか・行の書式は、検出器 lib/issue-flow-kind-violations.py の
# docstring と定数だけが持つ。ここは入力を渡して、報告を deny の JSON にするだけ。
#
# python3 が使えなければ通し、検出器が異常終了したら止める。使えないのは環境の側で、止めても直す手が無い。
# 異常終了は検出器の側で、通すと検査していない作成が黙って通る。
#
# 他のフックと部品を共有しない(`.claude/hooks/README.md`「配線」の `lib/case-table.sh` の行)。
set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$hook_dir/lib/issue-flow-kind-violations.py"

# python3 が実際に起動できるか。`command -v` は、PATH に居るが起動すると落ちる python3 も見つけてしまう。
# 起動できないときは `print_deny` も JSON を組めずに通るので、この確かめを消しても判定は変わらない
# (判定表の 91 はどちらでも通る)。消さないのは、通す理由を「検査できなかった」の deny と取り違えないため。
python3_usable() {
  python3 -c '' >/dev/null 2>&1
}

# 検出器を走らせ、最後まで走ったなら標準出力をそのまま書く。
#
# 検出器は違反を見つけたときだけ `[` で始まる報告の行を出して exit 1 で終わる。Python は捕まえていない例外
# (traceback)でも exit 1 で終わるので、報告の行を出さずに 1 で終わったもの・0 と 1 以外で終わったものを
# 「走り切れなかった」とする。
#
# @param $@ 検出器へ渡す引数
# @returns 0 で終わった・報告の行を出して 1 で終わったなら 0、それ以外は 1
detector_report() {
  local output status=0 ran_through=0
  output="$(python3 "$detector" "$@")" || status=$?
  [ "$status" -eq 0 ] && ran_through=1
  [ "$status" -eq 1 ] && grep -q '^\[' <<<"$output" && ran_through=1
  [ "$ran_through" -eq 1 ] || return 1
  printf '%s' "$output"
}

# deny の JSON を標準出力へ書く。jq の無い環境では exit 127 で素通りになるので、python3 で組む。
#
# $1 deny の理由
print_deny() {
  printf '%s' "$1" | python3 -c '
import json, sys
reason = sys.stdin.read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}, ensure_ascii=False))
'
}

input="$(cat)"

# 作成の入力は、どの形でも `issue` を含む(ツール名・サブコマンド・エンドポイント)。検出器より広く絞り、
# 無関係な呼び出しで python3 を起動しない。
[[ "$input" == *issue* ]] || exit 0

python3_usable || exit 0

origin_url="$(git -C "$hook_dir/../.." remote get-url origin 2>/dev/null || true)"

if ! report="$(printf '%s' "$input" | detector_report --origin-url "$origin_url" 2>/dev/null)"; then
  print_deny "Issue の作業の種類の検査(${detector})が異常終了したため、検査できませんでした。検査していない作成を通さないよう止めました。

標準入力にこの呼び出しの PreToolUse の JSON を渡して \`python3 ${detector} --origin-url <origin の URL>\` を走らせ、検出器が落ちた原因を直してください。"
  exit 0
fi
grep -q '^\[' <<<"$report" || exit 0

print_deny "Issue を作る呼び出しが作業の種類を決めていないため、止めました。

${report}"
