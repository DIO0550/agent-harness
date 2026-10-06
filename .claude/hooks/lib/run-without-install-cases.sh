#!/usr/bin/env bash
#
# `block-run-without-install.sh` の判定表。代表的なコマンドを実物のフックへ流し、
# deny / pass / miss / overdeny が期待どおりかを 1 コマンドで確かめる。
# あわせて jq の無い経路と `settings.json` への配線も検算する。
#
# 使い方: bash .claude/hooks/lib/run-without-install-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 表の形・期待の意味・走らせ方は `lib/case-table.sh` が持つ。
#
# **ケースをこのファイルに置くのは、Bash コマンドへ直接書くとフック自身に止められるため。**
# `deny|npx foo` のような行は、`|` で切った断片がコマンド位置の `npx foo` になるので
# 表を書いたコマンドがそのまま deny される(実測)。ファイルの中身はコマンド本文ではないので
# 切り出されない。編集するときも Write で置くこと。
#
# **jq が無い環境では、下の `jq_absent_cases` に挙げた 2 件が pass へ反転して NG になり、
# この表全体が exit 1 で落ちる**(フック本体は生の JSON から読み、最初の `"` で値が切れ、
# 改行は `\n` の 2 文字のまま残る)。判定が変わったと読み違えないこと。
# `harness/githooks/pre-push` が走らせるのは python3 と jq が両方ある枝だけなので、
# そちらでは起きない。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
source "$lib_dir/case-table.sh"
hook_path="$lib_dir/../block-run-without-install.sh"

failed=0
run_case_table "$hook_path" <<'CASES' || failed=1
deny|npx create-vite
deny|bunx vite
deny|uvx ruff check
deny|pnpm dlx shadcn init
deny|yarn dlx foo
deny|pipx run black .
deny|npm exec vite
deny|npm create vite@latest
deny|pnpm create vite
deny|yarn create react-app x
deny|cd /tmp && npx create-vite
deny|true; npx foo
deny|echo x | npx bar
deny|echo a &npx foo
deny|bash harness/records/count.sh@@npx foo
deny|  npx   foo
deny|go run github.com/foo/bar@latest
deny|go run example.com/x/y
deny|go run -race github.com/foo/bar@v1
deny|deno run https://example.com/y.ts
deny|deno run npm:cowsay
deny|deno run --allow-net jsr:@std/http
pass|npm install
pass|npm run build
pass|npm init -y
pass|pnpm add -D vite
pass|pnpm install
pass|yarn add foo
pass|pipx install black
pass|go run ./cmd/app
pass|go run .
pass|go run main.go
pass|go run ./pkg/v1.2/x
pass|go run ./cmd/app -to=user@example.com
pass|go run . && curl https://example.com
pass|go run ./cmd/app; curl https://example.com/x
pass|go build ./...
pass|deno run server.ts
pass|deno run server.ts --url=https://api.example.com
pass|npxfoo bar
pass|bunxyz foo
pass|uvxtool
pass|pnpm dlxfoo
pass|my-npx foo
pass|grep -rn npx .
pass|grep -rn "npx" .
pass|echo "npx foo"
pass|git commit -m "feat: npx を止める"
pass|git commit -m "feat(npx): 止める"
pass|git commit -m "fix: カナリア(npx 系)の取りこぼし"
pass|bash .claude/hooks/lib/run-without-install-cases.sh
miss|sudo npx foo
miss|env FOO=1 npx foo
miss|bash -c "npx foo"
miss|(npx foo)
overdeny|git commit -m "a; npx foo"
overdeny|git commit -m 'a; npx foo'
overdeny|echo "pipe | npx foo"
overdeny|git commit -m "feat: npx / bunx; uvx を止める"
overdeny|cat > /tmp/x.md <<EOF@@npx create-vite@@EOF
CASES

# 長さの上限を置いていないことを固定する(カナリアは 1 文字ずつ進む走査なので 2048 字で
# 打ち切るが、こちらは 3 本とも 1 パスなので上限が要らない)。表の 1 行には収まらない。
printf -v padding '%*s' 131072 ''
long_command="${padding// /x} && npx foo"
if [ "$(hook_judge "$hook_path" "$long_command")" = "deny" ]; then
  printf 'ok   %-8s %s\n' "deny" "131KB のコマンドに連ねた形(長さの上限を置いていない)"
else
  printf 'NG   expected=%s got=%s  %s\n' "deny" "pass" "131KB のコマンドに連ねた形"
  failed=1
fi

# jq の無い経路。jq がある環境ではこの経路をどのケースからも踏めないので、PATH を絞って
# 狙って踏む。絞った PATH にはフックが使うものだけを置く(bash・cat)。`command -v jq` が
# 外れるのが狙いなので jq は置かない。
#
# **1 件目が deny なのが要点。** 反転する 2 件(引用符・改行)だけを並べると、生 JSON を
# 読む枝を丸ごと壊しても取りこぼし側で通ってしまう。引用符を含まない形は jq 無しでも
# 止まるので、この 1 件がその枝を守る。
jq_absent_path="$(mktemp -d)"
ln -s "$(command -v bash)" "$jq_absent_path/bash"
ln -s "$(command -v cat)" "$jq_absent_path/cat"

run_case_table "$hook_path" "$jq_absent_path" "jq 無し: " <<'JQ_ABSENT_CASES' || failed=1
deny|npx create-vite
miss|bash harness/records/count.sh@@npx foo
miss|git commit -m "a; npx foo"
JQ_ABSENT_CASES

rm -rf "$jq_absent_path"

# 配線の検算。判定表は JSON を実物のフックへ直接流すので、配線が切れていても表だけは
# 全件通る。しかも綴りがあるかを grep で見るだけでは、`PostToolUse` や `Task|Agent` へ
# 移してあっても通ってしまう(実測)。Bash の実行前に呼ばれる枝に入っていることまで見る。
settings_path="$lib_dir/../../settings.json"
if python3 - "$settings_path" <<'PY'
import json, sys

HOOK = "block-run-without-install"
settings = json.load(open(sys.argv[1], encoding="utf-8"))
for entry in settings.get("hooks", {}).get("PreToolUse", []):
    matchers = entry.get("matcher", "").split("|")
    if "Bash" not in matchers:
        continue
    if any(HOOK in hook.get("command", "") for hook in entry.get("hooks", [])):
        raise SystemExit(0)
raise SystemExit(1)
PY
then
  printf 'ok   %-8s %s\n' "wired" "PreToolUse / Bash の枝から呼ばれている"
else
  printf 'NG   %-8s %s\n' "wired" "PreToolUse / Bash の枝から呼ばれていない(配線漏れ)"
  failed=1
fi

exit "$failed"
