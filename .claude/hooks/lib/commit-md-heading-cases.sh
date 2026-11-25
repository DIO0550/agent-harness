#!/usr/bin/env bash
#
# `block-commit-md-heading.sh` の判定表。Bash の PreToolUse の入力をフックへ流し、コミット本文の行頭 `#` の
# 拒否と素通りが期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/commit-md-heading-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 表の書き方は `case-table.sh` の `run_labeled_case_table`、期待の種類は同じファイルの冒頭。
# フックがコマンドを jq で取り出すので、jq が無いと deny の行が NG になる
# (`harness/githooks/pre-push` は jq がある環境でだけ走らせる)。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
. "$lib_dir/case-table.sh"

hook="$lib_dir/../block-commit-md-heading.sh"

cases_before=$cases_reported
run_labeled_case_table "$hook" <<'CASES'
deny|複数行の -m の行頭 # を止める|git commit -m "subject@@@@# 背景"
deny|シングルクォートの複数行の -m の行頭 # を止める|git commit -m 'subject@@@@# 背景'
deny|git commit -am の複数行の行頭 # を止める|git commit -am "subject@@@@# 背景"
deny|<<'EOF' の本文の行頭 # を止める|git commit -m "$(cat <<'EOF'@@subject@@@@# 背景@@EOF@@)"
deny|<<EOF の本文の行頭 # を止める|git commit -m "$(cat <<EOF@@subject@@@@# 背景@@EOF@@)"
deny|<<"EOF" の本文の行頭 # を止める|git commit -m "$(cat <<"EOF"@@subject@@@@# 背景@@EOF@@)"
deny|<< 'EOF'（空白あり）の本文の行頭 # を止める|git commit -m "$(cat << 'EOF'@@subject@@@@# 背景@@EOF@@)"
deny|<<\EOF の本文の行頭 # を止める|git commit -F - <<\EOF@@subject@@@@# 背景@@EOF
deny|<<-EOF の本文の桁 0 の # を止める|git commit -F - <<-EOF@@subject@@@@# 背景@@EOF
deny|-F - に渡すヒアドキュメントの行頭 # を止める|git commit -F - <<'EOF'@@subject@@@@# 背景@@EOF
deny|--amend の本文の行頭 ## を止める|git commit --amend -m "$(cat <<'EOF'@@subject@@@@## 採用理由@@EOF@@)"
deny|行頭が Issue 番号の本文の行を止める|git commit -m "$(cat <<'EOF'@@subject@@@@#123 で決めた@@EOF@@)"
deny|cd の後ろの git commit の本文も止める|cd sub && git commit -m "$(cat <<'EOF'@@subject@@@@# 背景@@EOF@@)"
deny|"$(…)" の後ろに並べた git commit の本文も止める|git tag "$(date +%s)" && git commit -m "subject@@@@# 背景"
deny|2 つ目のヒアドキュメント（git commit の本文）の行頭 # も止める|cat <<'A' >/dev/null@@メモ@@A@@git commit -m "$(cat <<'EOF'@@subject@@@@# 背景@@EOF@@)"
deny|ヒアドキュメントでファイルへ書いてから -F で渡す本文の行頭 # も止める|cat > /tmp/msg <<'EOF'@@subject@@@@# 背景@@EOF@@git commit -F /tmp/msg
deny|here-string（<<<）の次の行の git commit の本文の行頭 # を止める|cat <<<x@@git commit -m "s@@@@# h"
deny|末尾に空白がある EOF ではヒアドキュメントを閉じず、後ろの本文の行頭 # を止める|git commit -F - <<'EOF'@@subject@@EOF @@# 背景@@EOF
overdeny|git commit と同じ入力にある別のヒアドキュメントの行頭 # で止める|gh pr create --body "$(cat <<'B'@@## 概要@@B@@)" && git commit -m "$(cat <<'EOF'@@subject@@@@背景:@@EOF@@)"
overdeny|git commit と同じ入力にあるシェルのコメント行で止める|# 記録をまとめる@@git commit -m "subject"
pass|<見出し>: の形の見出しは通す|git commit -m "$(cat <<'EOF'@@subject@@@@背景:@@理由@@EOF@@)"
pass|字下げした # は通す|git commit -m "$(cat <<'EOF'@@subject@@@@  # 字下げ@@EOF@@)"
pass|件名の途中の #123 は通す|git commit -m "✨ [New Feature]: #123 取り込む"
pass|行の途中の # は通す|git commit -m "x" # 見出しではない
pass|--amend --no-edit は通す|git commit --amend --no-edit
pass|git log --grep の #123 は通す|git log --grep "#123"
pass|gh pr create の本文の ## は通す（本文に git commit とあっても）|gh pr create --title t --body "$(cat <<'EOF'@@## 概要@@git commit の手順を変えた@@EOF@@)"
pass|gh api のコメント本文の ## は通す（本文に git commit とあっても）|gh api repos/o/r/issues/1/comments -f body="$(cat <<'EOF'@@## 計画@@git commit -m で記録する@@EOF@@)"
pass|記録ファイルを書くヒアドキュメントの # は通す（本文に git commit とあっても）|cat > /tmp/pr-1.md <<'EOF'@@# PR 1@@git commit の本文@@EOF
pass|引用符の中の git commit は見ない|echo "git commit" && cat <<'EOF'@@# メモ@@EOF
miss|2 つ目の -m の # は見ない|git commit -m "subject" -m "# 背景"
miss|件名が # で始まる 1 行の -m は見ない|git commit -m "#123 subject"
miss|-F <ファイル> の中身は見ない|git commit -F msg.txt
miss|git -C <パス> commit は見ない|git -C sub commit -m "$(cat <<'EOF'@@subject@@@@# 背景@@EOF@@)"
miss|git -c <設定> commit は見ない|git -c user.name=x commit -m "$(cat <<'EOF'@@subject@@@@# 背景@@EOF@@)"
miss|<<-EOF でタブを除かれて桁 0 になる # は見ない|git commit -F - <<-EOF@@subject@@@@⇥# 背景@@EOF
miss|別のヒアドキュメントと並ぶ複数行の -m の行頭 # は見ない|cat <<'A' >/dev/null@@メモ@@A@@git commit -m "subject@@@@# 背景"
CASES
report_cases_ran CASES "$cases_before"
exit "$cases_failed"
