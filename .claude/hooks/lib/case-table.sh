#!/usr/bin/env bash
#
# 判定表の走行部。フックへ JSON を流し、期待どおりの判定になるかを 1 行ずつ報告する。
# `canary-cases.sh` と `run-without-install-cases.sh` が source する。
#
# 使い方: source したうえで次のどちらかを呼ぶ。
#   run_case_table <フックのパス>          # 標準入力から `期待|コマンド` の表を読む
#   hook_judge <フックのパス> <コマンド>   # 1 件だけ判定する
#
# 期待は 4 つ。`miss` / `overdeny` の綴りを `pass` / `deny` と分けてあるのは、並べると
# 次に読む人がバグ・意図した挙動と読み違えてフック側の Why not ごと消しにいくため。
#
# | 期待 | 意味 |
# | --- | --- |
# | `deny` | 止まってほしい |
# | `pass` | 止まってはいけない(誤検知したら信用を失う側) |
# | `miss` | **意図した取りこぼし。** 止められれば理想だが、誤検知を避けるために諦めた形 |
# | `overdeny` | **受け入れた誤検知。** 止まってほしくないが、避けるコストが釣り合わない形 |
#
# **判定表は共有してよいが、フック本体は共有しない。** 表は `source` が失敗すれば
# その場で落ちて分かるが、フックは PreToolUse のフェイルオープンに吸われて黙って
# 素通りする(.claude/hooks/README.md「強制力の序列」)。この非対称が、フック側で
# 入力の取り出しを各自持っている理由。
#
# JSON の組み立てと読み取りに python3 を使う。フック本体が外部コマンドへ依存しないのは
# フックが素通りしても気づけないからで、手で走らせるこの表は落ちれば分かる。
# 標準入力から渡すのは、長さの上限を固定するケースが argv では
# `Argument list too long` でフックまで届かないため(実測)。

# フックへ 1 件流し、判定を標準出力へ書く。
#
# @param $1 フックのパス
# @param $2 フックへ渡すコマンド本文
# @param $3 フックを走らせるときの PATH(既定は呼び出し側のまま)。フックが外部コマンドの
#           有無で経路を変える場合に、無い側の経路を狙って踏むために渡す
# @returns `deny` / `pass`、または期待に無い結果だったことを示す `error(...)`
#
# **`deny` は「出力が空でない」では見ない。** permissionDecision を `allow` に変えても、
# hookEventName を変えても、JSON を壊しても、末尾に `exit 1` を足しても出力は空でないので、
# それだけ見る表は全件通ってしまう(実測)。JSON として読んで決定の中身を確かめ、
# フックが 0 で終わることまで見る(PreToolUse は exit 2 以外の異常終了を素通りさせる)。
hook_judge() {
  local hook="$1" command_text="$2" hook_env_path="${3:-$PATH}" payload output status
  payload="$(printf '%s' "$command_text" |
    python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')"
  output="$(printf '%s' "$payload" | PATH="$hook_env_path" bash "$hook")"
  status=$?
  if [ "$status" -ne 0 ]; then
    printf 'error(exit=%s)' "$status"
    return 0
  fi
  if [ -z "$output" ]; then
    printf 'pass'
    return 0
  fi
  printf '%s' "$output" | python3 -c '
import json, sys

try:
    output = json.load(sys.stdin)["hookSpecificOutput"]
except Exception as error:
    print("error(json: %s)" % type(error).__name__)
    raise SystemExit(0)

event = output.get("hookEventName")
decision = output.get("permissionDecision")
if event != "PreToolUse":
    print("error(event=%s)" % event)
elif decision == "deny":
    print("deny")
else:
    print("error(decision=%s)" % decision)
'
}

# 標準入力の表を 1 行ずつ走らせ、`ok` / `NG` を報告する。
#
# @param $1 フックのパス
# @param $2 フックを走らせるときの PATH(既定は呼び出し側のまま。`hook_judge` と同じ)
# @param $3 報告する行に付ける見出し(既定は無し)。同じフックを条件を変えて 2 回走らせる
#           ときに、どちらの表の行かを読み分けるために渡す
# @returns 表の形は `期待|コマンド`。コマンド中の `@@` は改行に置き換わる
#          (1 行に収めるため。改行区切りで連ねた形も 1 ケースとして書ける)
#          食い違いが 1 件でもあれば 1、すべて期待どおりなら 0 で返る
run_case_table() {
  local hook="$1" hook_env_path="${2:-$PATH}" label_prefix="${3:-}"
  local expected case_command decision failed=0
  while IFS='|' read -r expected case_command; do
    [ -n "$case_command" ] || continue
    case_command="${case_command//@@/$'\n'}"
    decision="$(hook_judge "$hook" "$case_command" "$hook_env_path")"
    [ "$expected" = "miss" ] && [ "$decision" = "pass" ] && decision="miss"
    [ "$expected" = "overdeny" ] && [ "$decision" = "deny" ] && decision="overdeny"
    if [ "$decision" = "$expected" ]; then
      printf 'ok   %-8s %s%s\n' "$expected" "$label_prefix" "$case_command"
      continue
    fi
    printf 'NG   expected=%s got=%s  %s%s\n' "$expected" "$decision" "$label_prefix" "$case_command"
    failed=1
  done
  return "$failed"
}
