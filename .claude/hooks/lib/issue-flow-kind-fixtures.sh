#!/usr/bin/env bash
#
# Issue の作業の種類の判定表 2 本(`issue-flow-kind-cases.sh` と `issue-flow-kind-real-gh-cases.sh`)が共有する、
# ケースの前提の置き方。自リポジトリの origin・提案の行・本文のファイルを置く関数を持つ。
#
# 使う側は `work`(作業ディレクトリ)を決めてから source し、`place_files` を呼ぶ。

own_origin="https://github.com/acme/widgets"
proposal_line='種類の提案: flow:feature（根拠）'

# 文字列を JSON の文字列にする(表の入力に出る制御文字は改行とタブだけ)。
#
# $1 文字列
json_string() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\t'/\\t}"
  printf '"%s"' "$text"
}

# 本文のファイルを `$work` に置く。`big.md` は提案の行を持つが 1 MiB を超え、`sub/rel.md` は `cd sub` の後の
# 相対パスで読まれるはずのもの(作業ディレクトリ直下に `rel.md` は置かない)。
place_files() {
  mkdir -p "$work/sub" "$work/elsewhere"
  printf '前置き\n%s\n' "$proposal_line" >"$work/prop.md"
  printf '本文だけ\n' >"$work/plain.md"
  { printf '%s\n' "$proposal_line"; head -c 1100000 /dev/zero | tr '\0' 'a'; } >"$work/big.md"
  printf '%s\n' "$proposal_line" >"$work/sub/rel.md"
  printf '{"title":"x"}\n' >"$work/in-plain.json"
  printf '{"title":"x","body":%s}\n' "$(json_string "前置き"$'\n'"$proposal_line")" >"$work/in-body.json"
  printf 'title: x\n' >"$work/bad.json"
}
