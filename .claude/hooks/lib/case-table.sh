#!/usr/bin/env bash
#
# 判定表の走行部。フックへ JSON を流し、期待どおりの判定になるかを 1 行ずつ報告する。
# `.claude/hooks/lib/` の `*-cases.sh` が source する(どれが使うかは `.claude/hooks/README.md`「配線」)。
#
# 使い方: source したうえで次のどれかを呼ぶ。
#   run_case_table <フックのパス>              # 標準入力から `期待|コマンド` の表を読む
#   run_labeled_case_table <フックのパス>      # 標準入力から `期待|ケース名|コマンド` の表を読む
#   hook_judge <フックのパス> <コマンド>       # 1 件だけ判定する
#   judge_payload <フックのパス> <JSON>        # 入力の JSON を組んで 1 件だけ判定する
#   judge_output <出力> <終了コード>           # 走らせ終えたフックの出力から判定する
#   expected_decision <期待> <判定>            # `miss` / `overdeny` を表の綴りへ戻す
#   report_case <期待> <判定> <ケースの名前>   # 1 件の結果を `ok` / `NG` で報告する
#   report_cases_ran <表の名前> <回す前の件数> # 表のケースが 1 件以上走ったかを報告する
#
# 食い違いは `report_case` の戻り値と、変数 `cases_failed`(1 件でもあれば 1)の両方で分かる。
# 表をループで回す判定表は、最後の文を `exit "$cases_failed"` にする。
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

# 食い違ったケースがあれば 1 になる。
cases_failed=0

# `report_case` を呼んだ回数。
cases_reported=0

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
  local hook="$1" command_text="$2" hook_env_path="${3:-$PATH}" payload
  payload="$(printf '%s' "$command_text" |
    python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')"
  judge_payload "$hook" "$payload" "$hook_env_path"
}

# 組んだ入力の JSON をフックへ 1 件流し、判定を標準出力へ書く。`hook_judge` の
# `tool_input.command` だけでは足りない入力(`session_id` やツール名を持つもの)に使う。
#
# @param $1 フックのパス
# @param $2 フックへ渡す入力の JSON
# @param $3 フックを走らせるときの PATH(`hook_judge` と同じ)
# @returns `hook_judge` と同じ
judge_payload() {
  local hook="$1" payload="$2" hook_env_path="${3:-$PATH}" output status
  output="$(printf '%s' "$payload" | PATH="$hook_env_path" bash "$hook")"
  status=$?
  judge_output "$output" "$status"
}

# 走らせ終えたフックの出力と終了コードから判定を標準出力へ書く。フックを走らせる前に PATH や
# 置き場を差し替える判定表が、`judge_payload` を通さずに使う。
#
# @param $1 フックの標準出力
# @param $2 フックの終了コード
# @returns `hook_judge` と同じ
judge_output() {
  local output="$1" status="$2"
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
    report_case "$expected" "$(expected_decision "$expected" "$decision")" "$label_prefix$case_command" || failed=1
  done
  return "$failed"
}

# 標準入力の `期待|ケース名|コマンド` の表を 1 行ずつ走らせ、`ok` / `NG` をケース名で報告する。
# ケース名に止める・通す理由を書きたい表(取り込み元のまま残した形など)に使う。
#
# @param $1 フックのパス
# @returns コマンドは最後の列なので `|` を含んでよい。`@@` は改行に、`⇥` はタブに置き換わる
#          (`<<-` の字下げのようにタブそのものが意味を持つケースを 1 行に書くため)。
#          食い違いが 1 件でもあれば 1、すべて期待どおりなら 0 で返る
run_labeled_case_table() {
  local hook="$1" expected label case_command decision failed=0
  while IFS='|' read -r expected label case_command; do
    [ -n "$case_command" ] || continue
    case_command="${case_command//@@/$'\n'}"
    case_command="${case_command//⇥/$'\t'}"
    decision="$(hook_judge "$hook" "$case_command")"
    report_case "$expected" "$(expected_decision "$expected" "$decision")" "$label" || failed=1
  done
  return "$failed"
}

# 意図した取りこぼし・受け入れた誤検知は、`pass` / `deny` になるのが正解なので表の綴りへ戻す。
#
# @param $1 表に書かれた期待
# @param $2 実際の判定
# @returns 戻した判定(当たらなければ $2 のまま)
expected_decision() {
  local expected="$1" decision="$2"
  [ "$expected" = "miss" ] && [ "$decision" = "pass" ] && decision="miss"
  [ "$expected" = "overdeny" ] && [ "$decision" = "deny" ] && decision="overdeny"
  printf '%s' "$decision"
}

# 1 件の結果を `ok` / `NG` の 1 行で報告し、`cases_reported` を 1 増やす。食い違えば `cases_failed` を立てる。
#
# @param $1 期待
# @param $2 実際の判定
# @param $3 報告する行に出すケースの名前
# @returns 期待どおりなら 0、食い違えば 1
report_case() {
  local expected="$1" decision="$2" label="$3"
  cases_reported=$((cases_reported + 1))
  if [ "$decision" = "$expected" ]; then
    printf 'ok   %-8s %s\n' "$expected" "$label"
    return 0
  fi
  printf 'NG   expected=%s got=%s  %s\n' "$expected" "$decision" "$label"
  cases_failed=1
  return 1
}

# 表のケースが 1 件以上走ったか(表を回す前より `cases_reported` が増えたか)を 1 行で報告する。
#
# 表の行を消す・`read` の列がずれて全行を読み飛ばすと、ループは `report_case` を 1 回も呼ばずに終わり、
# `exit "$cases_failed"` は 0 のまま通る。回す前の件数を先に数値か確かめるのは、空の綴りを 0 と読むと
# 表の前に報告した件数だけで ok になるため。
#
# @param $1 報告に出す表の名前
# @param $2 表を回す前の `cases_reported`
report_cases_ran() {
  local table="$1" before="${2:-}"
  if ! [[ "$before" =~ ^[0-9]+$ ]]; then
    printf 'NG   %s を回す前の件数が数値ではない(%s)\n' "$table" "${before:-空}"
    cases_failed=1
    return 0
  fi
  if [[ "$cases_reported" -gt "$before" ]]; then
    printf 'ok   %s のケースが走った\n' "$table"
    return 0
  fi
  printf 'NG   %s のケースが 1 件も走っていない\n' "$table"
  cases_failed=1
}
