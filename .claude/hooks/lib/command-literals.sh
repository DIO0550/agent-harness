#!/usr/bin/env bash
#
# Bash の PreToolUse で渡るコマンド文字列から、ヒアドキュメントの本文と引用符の中身（コマンドとして
# 走らない文字列）を分けて取り出す `heredoc_bodies` と `command_line_outside_literals`。source して呼ぶ。
# 使う側は `.claude/hooks/README.md`「配線」の `lib/command-literals.sh` の行。
#
# シェルの字句解析は持たず、awk（POSIX の機能だけ。mawk でも動かす）と sed の行単位の置換で近似する。
# 見ない形（`bash -c "…"` の中、引用符の中の `<<EOF` という字面より後ろ、引用符で囲まない `<<EOF` の本文の中の
# コマンド置換など）は、使う側の判定表（`git-add-all-cases.sh` / `commit-md-heading-cases.sh`）に miss の行として並ぶ。
#
# `hook-canary.sh` の分割器は共有しない。長さの 2 乗で伸びて打ち切り、ヒアドキュメントも読まない。
# `lib/issue-flow-kind-violations.py` の字句解析も共有しない。検出器から共有モジュールへ切り出す手間があり、
# 移植元でも取り込みとは別の Issue(design-composer #1454)に分けた。
#
# フック本体の部品を共有しない決まり(`.claude/hooks/README.md`「配線」の `lib/case-table.sh` の行)の例外。
# 2 本のフックへ同じ awk を写すと片方だけ直る(`rules/coding.md`「ルール」の共通化)。このファイルが
# 読めないと 2 本とも黙って通るが、2 本の判定表の deny の行が push 前に落とす。

# ヒアドキュメントの区切りを開きの行ごとに読み、本文の行を除く（mode=body のときは本文の行だけを出し、
# mode=command のときは本文の外の行だけを出す）awk。
#
# 区切りを最初の 1 つだけで読むと、2 つ目以降のヒアドキュメントが閉じずに後ろを丸ごと本文と読む。
# 開きは `<<` の直前と直後が `<` でないものだけ。here-string の `<<<` を開きと読むと、閉じが来ずに後ろを丸ごと本文と読む。
# 閉じの行の字下げはタブだけを許す。`<<-` が取り除くのはタブだけで、空白で字下げした区切りでは閉じない。
# 閉じの行の末尾の空白も許さない。bash は `EOF ` のように後ろに空白が残る区切りでは閉じない。
# 閉じを本文の中（`inside`）でだけ探すのは、本文の外の区切りと同じ語だけの行を捨てないため（2 つのフックの判定には差が出ない）。
_command_literals_heredoc_awk='
  function delimiter_of(line,   s) {
    if (!match(line, /(^|[^<])<<-?[[:space:]]*[\\'"'"'"]?[A-Za-z_][A-Za-z_0-9]*/)) return ""
    s = substr(line, RSTART, RLENGTH)
    sub(/^[^<]?<<-?[[:space:]]*[\\'"'"'"]?/, "", s)
    return s
  }
  function closes_heredoc(line) {
    return line ~ ("^\t*" delimiter "$")
  }
  inside && closes_heredoc($0) { inside = 0; next }
  inside { if (mode == "body") print; next }
  {
    delimiter = delimiter_of($0)
    if (delimiter != "") inside = 1
    if (mode == "command") print
  }'

# コマンド文字列の中の、すべてのヒアドキュメントの本文の行を出す。
#
# $1 コマンド文字列
# 出力: 本文の行（開きの行と閉じの行は含まない）。ヒアドキュメントが無ければ何も出さない
heredoc_bodies() {
  printf '%s\n' "$1" | awk -v mode=body "$_command_literals_heredoc_awk"
}

# コマンド文字列から、ヒアドキュメントの本文と閉じの行・引用符の中身を除き、1 行にしたものを出す。
#
# 改行は `;` にして 1 行にする。sed は行ごとに置換するので、複数行にまたがる引用符を消すには 1 行にする必要があり、
# 空白ではなく `;` にするのは改行をコマンドの区切りとして残すため。
# 開きの引用符として扱うのは、行頭・空白・`;`・`=` の直後にあるものだけ。語の途中のアポストロフィ（`don't`）や
# `"$(…)"` の閉じの `"` を開きと読むと、次の引用符までの間にあるコマンドまで消してしまう。
# `$` やバッククォートを含む `"…"` は消さない。コマンド置換は引用符の中でも実行される。
#
# $1 コマンド文字列
# 出力: 引用符の外の部分を `;` でつないだ 1 行
command_line_outside_literals() {
  printf '%s\n' "$1" | awk -v mode=command "$_command_literals_heredoc_awk" | tr '\n' ';' \
    | sed -E "s/(^|[[:space:];=])'[^']*'/\1/g; s/(^|[[:space:];=])\"[^\"\$\`]*\"/\1/g"
}
