#!/usr/bin/env bash
#
# 取ってきて実行しうるコマンドを拒否する PreToolUse フック(matcher: Bash)。
# 移植元 design-composer の `block-npx.sh` を、スタックを決めていないこのリポジトリに
# 合わせて広げたもの。
#
# 入力: stdin に { "tool_input": { "command": "..." } } を含む JSON (Bash ツール呼び出し)
# 出力: 拒否するときだけ permissionDecision=deny の JSON を標準出力へ書く。
#
# 対象は 3 つに分かれる。
#   1 語        npx / bunx / uvx
#   2 語        pnpm dlx / yarn dlx / pipx run / npm exec / npm create / pnpm create /
#               yarn create
#   引数で判定  go run / deno run (リモートのモジュールパス・URL を渡したときだけ)
#
# `npx` / `npm exec` はローカルの `node_modules/.bin` に在ればそれを使うので、必ず取りに
# 行くとは限らない。どちらになるかは実行するまで分からないので一律で止める。
#
# `npm init <パッケージ>` と `bun create` は入れていない。前者はローカルの雛形作成
# (`npm init -y`)と引数でしか見分けられず、後者は広げる対象として挙がっていない。
#
# CI / git hooks(層 1・2)では代替できない。取ってきて実行したことは依存ファイルにも
# ロックファイルにも書かれないので、push の時点で検査する対象が無い
# (.claude/hooks/README.md「カバー範囲と残る穴」)。層 3 止まりで、フックが発火しない
# 実行環境では効かないことを許容する。
set -uo pipefail

input="$(cat)"

# コマンド本文を取り出す。jq が無い / 失敗した場合は生の JSON から読む。
# 後者は最初の `"` までを値と見るので、ランナーより前に引用符を含む形は取りこぼす。
# 取りこぼす側へ倒して誤検知を避ける。
command_text=""
if command -v jq >/dev/null 2>&1; then
  command_text="$(jq -r '.tool_input.command // empty' <<< "$input" 2>/dev/null || true)"
fi
if [ -z "$command_text" ]; then
  raw_command_pattern='"command"[[:space:]]*:[[:space:]]*"([^"]*)"'
  if [[ "$input" =~ $raw_command_pattern ]]; then
    command_text="${BASH_REMATCH[1]}"
  fi
fi

# 拾うのはコマンド位置(行頭、または `;` `&` `|` 改行の直後)にある綴りだけ。移植元は境界に
# プレーンな空白も入れているが、それだと `grep -rn npx .` で止まる(実測)。
#
# `(` は区切りに入れない。入れると `git commit -m "feat(npx): 止める"` で止まり、
# このリポジトリの文章は括弧を常用するので釣り合わない。代わりに `(npx foo)` を取りこぼす。
#
# 引用符は追わない。そのため引用符の中の区切り文字も区切りとして読み、改行を含む
# ヒアドキュメントで `npx` から始まる行を書き出す形は止まる(判定表の `overdeny`)。
#
# 区切りに `|` と単独の `&` を入れる点が hook-canary.sh と逆。あちらは断片の完全一致で
# 見るため同じ区切りを入れると判定表の行そのもので誤検知するが、こちらは部分一致なので
# `echo x | npx bar` を拾える利得がそのまま残る。
#
# カナリアのような長さの上限は置かない。あちらは 1 文字ずつ進む走査でコマンド長の二乗に
# 伸びるが、ここは 3 本とも 1 パスで済む(131KB のコマンドで 3ms。実測)。
newline=$'\n'
command_position="(^|[;&|]|${newline})[[:space:]]*"
word_end="([[:space:]]|[;&|]|$)"

single_word_runners="npx|bunx|uvx"
two_word_runners="pnpm[[:space:]]+dlx|yarn[[:space:]]+dlx|pipx[[:space:]]+run|npm[[:space:]]+exec|npm[[:space:]]+create|pnpm[[:space:]]+create|yarn[[:space:]]+create"
runner_pattern="${command_position}(${single_word_runners}|${two_word_runners})${word_end}"

# `go run` / `deno run` はローカル実行が正当なので、リモートを指しているときだけ拾う。
# 見るのは**最初の非フラグ引数の先頭**に限る。引数列のどこでもよいことにすると
# `go run ./cmd/app -to=user@example.com` や `deno run server.ts --url=https://x` で
# 止まる(どちらも実測)。
#
# go のリモートはモジュールパスなので先頭セグメントがドメインになる。`[A-Za-z][A-Za-z]+` を
# 要求するので `./pkg/v1.2/x` の `2/` は拾わない。`@<バージョン>` は付かないこともあり、
# 付く形はドメインの側で既に拾えるので条件に入れない。
leading_flags="(-[^[:space:]]*[[:space:]]+)*"
go_remote="${command_position}go[[:space:]]+run[[:space:]]+${leading_flags}[A-Za-z0-9-]+\.[A-Za-z][A-Za-z]+/"
deno_remote="${command_position}deno[[:space:]]+run[[:space:]]+${leading_flags}(https?://|npm:|jsr:)"

matched=0
[[ "$command_text" =~ $runner_pattern ]] && matched=1
[[ "$command_text" =~ $go_remote ]] && matched=1
[[ "$command_text" =~ $deno_remote ]] && matched=1

[ "$matched" -eq 1 ] || exit 0

reason="取ってきて実行しうるコマンド（npx / bunx / uvx / pnpm dlx / yarn dlx / pipx run / npm exec / npm create / pnpm create / yarn create、リモートを指す go run・deno run）は禁止しています。使うツールは、実行する前に環境へインストールするか、リポジトリの依存として追加してください（このリポジトリはまだパッケージマネージャを持たないので、入れる先はあなたの環境です）。1 回しか使わないなら、そのツールが本当に必要かを先に確かめてください。コマンドとして実行していないのに止まった場合は、引用符の中にある区切り文字（セミコロン・アンパサンド・縦棒・改行）をこのフックが区切りと読んでいます（引用符を追わないため）。書き方を変えて実行し直してください。"

# jq -n を使わない(jq の有無で出力できなくなるため)。reason には引用符・改行・
# バックスラッシュを入れないので、この組み立てで JSON として妥当になる。
cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "${reason}"
  }
}
JSON
