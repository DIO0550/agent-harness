#!/usr/bin/env bash
#
# カナリアの判定表。`hook-canary.sh` に代表的なコマンドを流し、deny / pass / miss が
# 期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/canary-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 表の形・期待の意味・走らせ方は `lib/case-table.sh` が持つ。
#
# **ケースをこのファイルに置くのは、Bash コマンドへ直接書くとカナリア自身に
# 止められるため。** `cd /tmp && echo hook-canary` のような行は本物の呼び出しとして
# 切り出されるので、表を書いたコマンドがそのまま deny される(実測)。ファイルの
# 中身はコマンド本文ではないので切り出されない。
#
# **jq が無い環境では deny 側が全件 NG になる**(`case-table.sh` が JSON の組み立てに
# python3 を使い、`hook-canary.sh` は jq が無いと生 JSON から読んで引用符で値が切れる)。
# 判定が変わったと読み違えないこと。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
source "$lib_dir/case-table.sh"
hook_path="$lib_dir/../hook-canary.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "注意: jq が無いので生 JSON へのフォールバック経路で走る。引用符を含むケースと"
  echo "      改行で連ねたケースは値が取り出せず pass になる(hook-canary.sh の doc 参照)。"
fi

failed=0
run_case_table "$hook_path" <<'CASES' || failed=1
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
if [ "$(hook_judge "$hook_path" "$long_command")" = "pass" ]; then
  printf 'ok   %-8s %s\n' "miss" "2100 字のコマンドに連ねた形(走査の上限を超える)"
else
  printf 'NG   expected=%s got=%s  %s\n' "miss" "deny" "2100 字のコマンドに連ねた形"
  failed=1
fi

exit "$failed"
