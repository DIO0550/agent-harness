#!/usr/bin/env bash
#
# `block-git-add-all.sh` の判定表。Bash の PreToolUse の入力をフックへ流し、一括ステージングの拒否と
# 素通りが期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/git-add-all-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 表の書き方は `case-table.sh` の `run_labeled_case_table`、期待の種類は同じファイルの冒頭。
# フックがコマンドを jq で取り出すので、jq が無いと deny の行が NG になる
# (`harness/githooks/pre-push` は jq がある環境でだけ走らせる)。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
. "$lib_dir/case-table.sh"

hook="$lib_dir/../block-git-add-all.sh"

cases_before=$cases_reported
run_labeled_case_table "$hook" <<'CASES'
deny|git add -A を止める|git add -A
deny|git add --all を止める|git add --all
deny|git add . を止める|git add .
deny|git add -a を止める（取り込み元のまま）|git add -a
deny|git add -- . を止める|git add -- .
deny|-A が最初の引数でない git add -v -A を止める|git add -v -A
deny|-A を束ねた git add -fA を止める|git add -fA
deny|パスの後ろに . を並べた git add src/a.ts . を止める|git add src/a.ts .
deny|パスを付けた git add -A src/ も止める（取り込み元のまま）|git add -A src/
deny|前置きの env を付けた git add -A を止める|env FOO=1 git add -A
deny|; の直前の git add . を止める|git add .; git status
deny|&& の後ろの git add -A を止める|git add src/a.ts && git add -A
deny|改行の後ろの git add -A を止める|git status@@git add -A
deny|"$(…)" の後ろに並べた git add -A を止める|git commit -m "$(date)" && git add -A && git commit -m "x"
deny|語の途中のアポストロフィの後ろの git add -A を止める|echo "don't" && git add -A
deny|"$(…)" の中の git add -A を止める|out="$(git add -A 2>&1)"
deny|"`…`" の中の git add -A を止める|out="`git add -A 2>&1`"
deny|<<-EOF のタブで字下げした閉じの後ろの git add -A を止める|git commit -F - <<-EOF@@⇥subject@@⇥EOF@@git add -A
deny|here-string（<<<）の次の行の git add -A を止める|cat <<<x@@git add -A
deny|引用符で囲んだ here-string（<<<"…"）の次の行の git add -A を止める|grep foo <<<"bar"@@git add -A
deny|サブシェルの閉じ括弧の直前の git add . を止める|(cd sub && git add .)
deny|&& の直前に空白を挟まない git add . を止める|git add .&& git commit -m x
deny|パイプの直前に空白を挟まない git add . を止める|git add .|cat
deny|. の後ろに空白を挟んで && を並べた git add . を止める|git add . && git commit -m x
deny|. の後ろに空白を挟んでパスを並べた git add . src/a.ts を止める|git add . src/a.ts
deny|語の途中のアポストロフィの後ろの git add -A を、後ろにシングルクォートがあっても止める|echo "don't" && git add -A && git commit -m 'x'
deny|1 つ目のヒアドキュメントの後ろの、2 つ目のヒアドキュメントを閉じた後の git add -A を止める|cat <<'A' >/dev/null@@x@@A@@cat <<'B'@@y@@B@@git add -A
deny|パイプの後ろに並べた git add -A を止める|echo x | cat && git add -A
deny|エスケープした \" に挟まれた git add -A を止める|echo \"x && git add -A && echo \"
pass|個別のパスの git add は通す|git add src/a.ts
pass|git add -u は通す|git add -u
pass|git add -p は通す|git add -p src/a.ts
pass|git add -N は通す|git add -N src/app/probe.ts
pass|-- の後ろが個別のパスなら通す|git add -- src/a.ts
pass|./ で始まるパスは通す|git add ./src
pass|ドットで始まるパスは通す|git add .claude/hooks/x.sh
pass|git commit -am は通す（追跡済みだけを載せる git add -u と同じ）|git commit -am "x"
pass|&& の後ろの ls -A は通す|git add src/a.ts && ls -A
pass|ダブルクォートの中の git add -A は通す|git commit -m "git add -A は使わない"
pass|シングルクォートの中の git add -A は通す|git commit -m 'git add -A は使わない'
pass|grep の引数の git add -A は通す|grep -rn "git add -A" .
pass|README の動作確認の JSON の中の git add -A は通す|echo '{"session_id":"probe","tool_input":{"command":"git add -A"}}' | bash .claude/hooks/block-git-during-verification-agent.sh
pass|<<'EOF' のヒアドキュメントの本文は通す|git commit -m "$(cat <<'EOF'@@subject@@@@git add -A は使わない@@EOF@@)"
pass|<<EOF のヒアドキュメントの本文は通す|git commit -F - <<EOF@@subject@@@@git add -A は使わない@@EOF
pass|<<"EOF" のヒアドキュメントの本文は通す|git commit -F - <<"EOF"@@subject@@@@git add -A は使わない@@EOF
pass|<< 'EOF'（空白あり）のヒアドキュメントの本文は通す|git commit -F - << 'EOF'@@subject@@@@git add -A は使わない@@EOF
pass|<<-EOF のヒアドキュメントの本文は通す|git commit -F - <<-EOF@@⇥subject@@@@⇥git add -A は使わない@@⇥EOF
pass|<<\EOF のヒアドキュメントの本文は通す|git commit -F - <<\EOF@@subject@@@@git add -A は使わない@@EOF
pass|= の直後のダブルクォートの中の git add -A は通す|gh api repos/o/r/issues/1/comments -f body="git add -A は使わない"
pass|= の直後のシングルクォートの中の git add -A は通す|gh api repos/o/r/issues/1/comments -f body='git add -A は使わない'
pass|行の継続の後ろの行頭のダブルクォートの中の git add -A は通す|grep -rn \@@"git add -A" .
pass|行の継続の後ろの行頭のシングルクォートの中の git add -A は通す|grep -rn \@@'git add -A' .
pass|複数行にまたがる -m の中の git add -A は通す|git commit -m "subject@@@@git add -A は使わない"
pass|改行の後ろの ls -A は通す|git add src/a.ts@@ls -A
pass|空白で字下げした EOF ではヒアドキュメントを閉じない|git commit -F - <<'EOF'@@subject@@  EOF@@git add -A は使わない@@EOF
miss|git -C <パス> add -A は見ない|git -C src add -A
miss|git -c <設定> add -A は見ない|git -c core.autocrlf=false add -A
miss|git add ./ は見ない|git add ./
miss|git add :/ は見ない|git add :/
miss|git add * は見ない|git add *
miss|引用符で囲んだ git add "." は見ない|git add "."
miss|git stage -A は見ない|git stage -A
miss|bash -c の中の git add -A は見ない|bash -c "git add -A"
miss|引用符の中の <<EOF という字面をヒアドキュメントの開きと読み、次の行の git add -A は見ない|echo "書き方は <<EOF で渡す"@@git add -A
miss|引用符で囲まない <<EOF の本文の中のコマンド置換 $(git add -A) は見ない|cat <<EOF@@$(git add -A)@@EOF
CASES
report_cases_ran CASES "$cases_before"
exit "$cases_failed"
