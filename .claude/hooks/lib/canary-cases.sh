#!/usr/bin/env bash
#
# カナリアの判定表。`hook-canary.sh` に代表的なコマンドを流し、deny / pass / miss が
# 期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/canary-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# **ケースをこのファイルに置くのは、Bash コマンドへ直接書くとカナリア自身に
# 止められるため。** `cd /tmp && echo hook-canary` のような行は本物の呼び出しとして
# 切り出されるので、表を書いたコマンドがそのまま deny される(実測)。ファイルの
# 中身はコマンド本文ではないので切り出されない。
#
# 表は `期待|コマンド` の 1 行 1 ケース。コマンド中の `@@` は改行に置き換わる
# (1 行に収めるため。改行区切りで連ねた形も 1 ケースとして書ける)。期待は 3 つ。
#
# | 期待 | 意味 |
# | --- | --- |
# | `deny` | 止まってほしい |
# | `pass` | 止まってはいけない(誤検知したら信用を失う側) |
# | `miss` | **意図した取りこぼし。** 止められれば理想だが、誤検知を避けるために諦めた形。
#            期待の綴りを分けてあるのは、`pass` と並べると次に読む人がバグと読んで
#            `hook-canary.sh` の Why not ごと消しにいくため |
#
# **JSON の組み立てに python3 を使う。** カナリア本体が外部コマンドへ依存しないのは
# フックが素通りしても気づけないからで、手で走らせるこの表は落ちれば分かる。
# python3 が無い環境では deny 側が全件 NG になるので、判定が変わったと読み違えないこと。
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "注意: jq が無いので生 JSON へのフォールバック経路で走る。引用符を含むケースと"
  echo "      改行で連ねたケースは値が取り出せず pass になる(hook-canary.sh の doc 参照)。"
fi

hook_path="$(dirname "$0")/../hook-canary.sh"
failed=0

while IFS='|' read -r expected case_command; do
  [ -n "$case_command" ] || continue
  case_command="${case_command//@@/$'\n'}"
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$case_command")"
  output="$(printf '%s' "$payload" | bash "$hook_path")"
  if [ -n "$output" ]; then
    decision="deny"
  else
    decision="pass"
  fi
  # 意図した取りこぼしは pass になるのが正解。
  if [ "$expected" = "miss" ] && [ "$decision" = "pass" ]; then
    decision="miss"
  fi
  if [ "$decision" = "$expected" ]; then
    printf 'ok   %-4s %s\n' "$expected" "$case_command"
    continue
  fi
  printf 'NG   expected=%s got=%s  %s\n' "$expected" "$decision" "$case_command"
  failed=1
done <<'CASES'
deny|echo hook-canary
deny|echo hook-canary && echo done
deny|cd /tmp && echo hook-canary
deny|true || echo hook-canary
deny|echo hook-canary; bash harness/records/count.sh
deny|bash harness/records/count.sh@@echo hook-canary
deny|echo "hook-canary"
deny|echo 'hook-canary'
deny|  echo   hook-canary
deny|git commit -m "x" && echo hook-canary
deny|echo "don't" && echo hook-canary
deny|git commit -m "a\"b" && echo hook-canary
pass|git commit -m "fix: echo hook-canary の取りこぼしを直す"
pass|git commit -m "a; echo hook-canary; b"
pass|git commit -m "a && echo hook-canary"
pass|git commit -m 'a && echo hook-canary'
pass|git commit -m "don't && echo hook-canary && ok"
pass|git commit -m 'say "x" && echo hook-canary'
deny|echo 'a"b' && echo hook-canary
pass|git commit -m "a\" && echo hook-canary && b"
pass|grep -rn "echo hook-canary" .
pass|git status # echo hook-canary
pass|echo hook-canary-probe
pass|echo hook-canary extra
pass|bash harness/records/count.sh
miss|echo hook-canary | cat
miss|echo hook-canary &
miss|(echo hook-canary)
miss|echo hook-canary >/dev/null
CASES

# 長さの上限を超えると走査しない(意図した取りこぼし)。表の 1 行には収まらないので個別に見る。
printf -v padding '%*s' 2100 ''
long_command="${padding// /x} && echo hook-canary"
long_payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$long_command")"
if [ -z "$(printf '%s' "$long_payload" | bash "$hook_path")" ]; then
  printf 'ok   %-4s %s\n' "miss" "2100 字のコマンドに連ねた形(走査の上限を超える)"
else
  printf 'NG   expected=%s got=%s  %s\n' "miss" "deny" "2100 字のコマンドに連ねた形"
  failed=1
fi

exit "$failed"
