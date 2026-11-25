#!/usr/bin/env bash
#
# Issue の作業の種類の検査(`issue-flow-kind-violations.py` と、それを呼ぶ `block-issue-without-flow-kind.sh`)の
# 判定表。作成の呼び出しを流し、deny / pass / miss が期待どおりかを 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/issue-flow-kind-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# **字句への分け方がこの検査の中心なので、表を置く。** 検出器を呼ぶ層はこのフックしか無く、分け方が退行しても
# 何も落ちない。
#
# 表は 5 つ。
#
# - 検出器の表は `期待|分類|形|ケース名|入力`。分類は deny のときの種別の末尾(`missing` など)で、他は `-`。
#   形は `bash`(入力 `cwd` に作業ディレクトリを載せ、別のディレクトリから走らせる)・`bash-nocwd`(`cwd` を
#   載せず、作業ディレクトリから走らせる)・`mcp`(入力は `mcp__github__issue_write` の `tool_input` の JSON)。
#   入力の `⏎` は改行、`⇥` はタブ、`¦` は `|`、`@W` は作業ディレクトリに置き換える
# - origin の表は `期待|origin の URL|ケース名|入力`。自リポジトリの決め方を見る
# - フックの表は `期待|検出器|python3|jq|ケース名|入力`。フックを一時ディレクトリへ写して走らせる
#   (検出器を落とす・python3 や jq を起動できなくする差し替え口を、本番のフックに残さないため)
# - 拒否文の表は `期待|ケース名|含むはずの文`。拒否文の並びと文面を見る
# - CLI の表は `期待する終了コード|ケース名|標準入力`。検出器を CLI として走らせ、終了コードを見る
#
# **どの表も、列の数が違う行があれば NG にする。** ケース名や入力に `|` を書くと、`read` は黙って後ろの列へ
# 寄せ、別の入力のまま判定が合ってしまうことがある。入力の `|` は `¦` と書く。
#
# **検出器の表と origin の表は、python3 を 1 回だけ起動して検出器を import し、ケースごとに判定の関数を
# 呼ぶ**(ケースごとに python3 を起動すると、移植元の実測で 1.4 秒が 8.0 秒になった)。CLI の経路(`--origin-url` と標準入力の
# JSON)は、フックの表と CLI の表が検出器を CLI として走らせて見る。
#
# | 期待 | 意味 |
# | --- | --- |
# | `deny` | 違反として報告してほしい(フックなら deny) |
# | `pass` | 報告してはいけない |
# | `miss` | **意図した取りこぼし。** `.claude/hooks/README.md`「カバー範囲と残る穴」の「取りこぼす」に当たる形 |
#
# **止めすぎも deny で固定する**(`export GH_REPO` を先に実行する形など)。直したときに表を書き換えることになり、
# 黙って広がることがない。`case-table.sh` の `overdeny` は使わない(検出器の表は検出器を import して判定するので、
# フックへ流す `run_case_table` を通らない)。
#
# 検出器と JSON の組み立てに python3 を使う(jq は使わない)。python3 が無いと表が 1 件も走らず NG になる。
set -uo pipefail

# 外側のリポジトリを指す git の環境変数を落とす(立ったまま、フックの写しで `git init` すると本物の
# リポジトリを触る)。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

lib_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$lib_dir/../../.." && pwd)"
detector="$lib_dir/issue-flow-kind-violations.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

source "$lib_dir/case-table.sh"
source "$lib_dir/issue-flow-kind-fixtures.sh"

# 起動するとすぐ落ちる検出器のスタブを置く。どれも報告の行を出さない。
#
# $1 落ち方(`crash` は traceback、`summary-exit1` は要約の行だけを出して exit 1、
#    `usage` は使い方を出して exit 2)
# $2 スタブを書くパス
place_failing_detector() {
  local failure="$1" target="$2"
  case "$failure" in
    crash) printf 'raise RuntimeError("判定表: 検出器が途中で落ちる")\n' >"$target" ;;
    summary-exit1) printf 'import sys\nprint("違反は 0 件")\nsys.exit(1)\n' >"$target" ;;
    usage) printf 'import sys\nprint("使い方: 検査する対象を渡す")\nsys.exit(2)\n' >"$target" ;;
  esac
}

# 起動すると 127 で落ちるコマンドを置き、PATH の先頭に足す値を返す。`broken` 以外なら空。
#
# 起動できない python3 を `command -v` で見ると見つかってしまうので、フックが起動して確かめているかを
# この形で踏む。
#
# $1 コマンド名(`python3` / `jq`)
# $2 `broken` なら置く
# $3 置き場のディレクトリ(その下の `broken-bin/` に置く。後ろのケースへ残さないよう呼び出し側が消す)
broken_command_path_prefix() {
  [ "$2" = "broken" ] || return 0
  mkdir -p "$3/broken-bin"
  printf '#!/usr/bin/env bash\nexit 127\n' >"$3/broken-bin/$1"
  chmod +x "$3/broken-bin/$1"
  printf '%s:' "$3/broken-bin"
}

# リポジトリのファイルを、リポジトリと同じ相対位置で写し先へ写す(フックを一時ディレクトリで走らせるため)。
#
# $1 写し先のディレクトリ
# $2 以降 リポジトリのルートからの相対パス
copy_repo_files() {
  local dest="$1" path
  shift
  for path in "$@"; do
    mkdir -p "$dest/$(dirname "$path")"
    cp "$repo_dir/$path" "$dest/$path"
  done
}

# 検出器が報告する種別を、実装に書いた順に 1 行 1 つ出す(行頭の `KINDS = (...)` から読む)。
#
# $1 検出器のパス
reported_kinds() {
  sed -nE 's/^KINDS = \((.*)\)$/\1/p' "$1" | grep -oE '"[^"]+"' | tr -d '"'
}

# 検出器の docstring が「報告する違反は次のとおり」に続けて並べた種別を、上から 1 行 1 つ出す。
# 箇条書き(`- `<種別>` — `)の字下げ 2 の継続行は読み飛ばし、箇条書きの外の行で終わる。
#
# $1 検出器のパス
documented_kinds() {
  sed -nE -e '/^報告する違反は次のとおり/{' -e ':blank' -e 'n' -e '/^$/bblank' \
    -e ':item' -e 's/^- `([^`]+)` — .*$/\1/p' -e ':rest' -e 'n' -e '/^  /brest' -e '/^- /bitem' -e '}' "$1"
}

# 検出器の種別が、docstring の一覧と並びまで一致するかを 1 行で報告する。食い違ったら `cases_failed` を立てる。
#
# 種別の一覧は検出器の docstring にだけ書き、README・rules へは写さない。写した一覧は照合されないまま
# 片方だけ古くなる。どちらも 0 件なら取り出しが壊れているので別の NG にする(0 件どうしの一致を
# 照合が通ったと読まないため)。
#
# $1 検出器のパス
report_documented_kinds() {
  local reported documented
  reported="$(reported_kinds "$1")"
  documented="$(documented_kinds "$1")"
  if [ -z "$reported$documented" ]; then
    echo 'NG   検出器の種別を実装と docstring のどちらからも取り出せなかった'
    cases_failed=1
    return 0
  fi
  if [ "$reported" != "$documented" ]; then
    printf 'NG   検出器の種別が docstring の一覧と食い違う(実装: %s / docstring: %s)\n' \
      "$(printf '%s' "${reported:-空}" | paste -sd ' ' -)" "$(printf '%s' "${documented:-空}" | paste -sd ' ' -)"
    cases_failed=1
    return 0
  fi
  echo 'ok   検出器の種別が docstring の一覧と一致する'
}

# 表の分類の欄(`|` 区切りの 2 列目)に出た分類を、接頭辞を付けた種別の綴りで 1 行 1 つ出す。
# 分類の無いケース(`-`)は落とす。
#
# $1 判定表(1 行 1 ケース)
# $2 分類を種別の綴りにする接頭辞
kinds_in_categories() {
  printf '%s\n' "$1" | cut -d '|' -f 2 | grep -vx -- '-' | sed "s/^/$2/"
}

# 検出器が報告する種別ごとに、表の期待に出てくるかを 1 行で報告する。出てこない種別があれば
# `cases_failed` を立てる。種別を足したときに表が追随しないと、その種別は誰にも守られないまま緑になる。
#
# $1 検出器のパス
# $2 表の期待に出た種別(1 行 1 つ)
report_covered_kinds() {
  local covered="$2" kind
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    if printf '%s\n' "$covered" | grep -qxF -- "$kind"; then
      printf 'ok   %s を期待するケースがある\n' "$kind"
    else
      printf 'NG   %s を期待するケースが表に無い\n' "$kind"
      cases_failed=1
    fi
  done <<<"$(reported_kinds "$1")"
}

# 形と入力から、PreToolUse の JSON を組む。
#
# $1 形(`bash` / `bash-nocwd` / `mcp`)
# $2 置き換え済みの入力
payload() {
  case "$1" in
    bash) printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s}' "$(json_string "$2")" "$(json_string "$work")" ;;
    bash-nocwd) printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(json_string "$2")" ;;
    mcp) printf '{"tool_name":"mcp__github__issue_write","tool_input":%s}' "$2" ;;
  esac
}

# 検出器を 1 回だけ import し、標準入力の 1 行 1 ケース(`表|期待|分類|形|origin の URL|ケース名|入力`)を
# 判定して `表|期待|判定|ケース名` を出す。判定は pass / deny / broken(判定の関数が例外で落ちた)で、
# deny の報告に分類と違う種別が混じれば `deny-other` にする。
#
# 引数は検出器のパスと作業ディレクトリ。
detector_runner="$(cat <<'PY'
import importlib.util
import json
import os
import sys
import traceback

sys.dont_write_bytecode = True
detector_path, work = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("issue_flow_kind_violations", detector_path)
detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detector)


def hook_input(form, text):
    if form == "mcp":
        return {"tool_name": "mcp__github__issue_write", "tool_input": json.loads(text)}
    command = {"tool_name": "Bash", "tool_input": {"command": text}}
    return {**command, "cwd": work} if form == "bash" else command


def verdict(form, origin, category, text):
    os.chdir(work if form == "bash-nocwd" else os.path.join(work, "elsewhere"))
    expanded = text.replace("⏎", "\n").replace("⇥", "\t").replace("¦", "|").replace("@W", work)
    try:
        data = hook_input(form, expanded)
        findings = detector.findings_for(data, detector.context_for(data, origin))
    except Exception:
        traceback.print_exc()
        return "broken"
    if not findings:
        return "pass"
    other = [f for f in findings if category != "-" and f.kind != f"issue-flow-kind-{category}"]
    return "deny-other" if other else "deny"


for line in sys.stdin:
    table, expected, category, form, origin, label, text = line.rstrip("\n").split("|", 6)
    print(f"{table}|{expected}|{verdict(form, origin, category, text)}|{label}")
PY
)"

# 表の中で列の数が違う行を 1 行で報告する。違う行があれば `cases_failed` を立てる。
#
# $1 表の名前
# $2 列の数
# $3 表(1 行 1 ケース)
report_column_count() {
  local misaligned
  misaligned="$(printf '%s\n' "$3" | awk -F '|' -v columns="$2" 'NF && NF != columns')"
  if [ -z "$misaligned" ]; then
    printf 'ok   %s の行はすべて %s 列\n' "$1" "$2"
    return 0
  fi
  printf 'NG   %s に %s 列でない行がある: %s\n' "$1" "$2" "$(printf '%s' "$misaligned" | paste -sd ' ' -)"
  cases_failed=1
}

place_files

cases="$(cat <<'CASES'
deny|missing|bash|1 ラベルも行もない作成は止める|gh issue create -t x -b 本文
pass|-|bash|2 --label flow:feature で通す|gh issue create -t x --label flow:feature
pass|-|bash|3 -l bug,flow:bugfix で通す|gh issue create -t x -l bug,flow:bugfix
pass|-|bash|4 --label=flow:refactor で通す|gh issue create -t x --label=flow:refactor
pass|-|bash|5 -lflow:feature で通す|gh issue create -t x -lflow:feature
deny|missing|bash|6 flow: で始まらないラベルだけなら止める|gh issue create -t x --label bug --label noflow:x
deny|missing|bash|7 空の flow: だけなら止める|gh issue create -t x --label flow:
deny|multiple|bash|8 異なる flow:* が 2 つなら止める|gh issue create -t x --label flow:feature --label flow:bugfix
deny|multiple|bash|8 異なる flow:* が 2 つなら提案の行があっても止める|gh issue create -t x --label flow:feature --label flow:bugfix -b '種類の提案: flow:feature（根拠）'
pass|-|bash|9 同じ flow:* が 2 回なら通す|gh issue create -t x --label flow:feature -l flow:feature
pass|-|bash|10 区切りが 'EOF' のヒアドキュメントに提案の行があれば通す|gh issue create -t x --body-file - <<'EOF'⏎前置き⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|11 区切りが 'EOF' のヒアドキュメントに通さない行があれば通す|gh issue create -t x --body-file - <<'EOF'⏎前置き⏎種類: implementation-flow に通さない（棚卸し）⏎EOF
pass|-|bash|12 ラベルと行の両方があれば通す|gh issue create -t x --label flow:feature --body-file - <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|13 提案の行が 2 つあっても通す|gh issue create -t x --body-file - <<'EOF'⏎種類の提案: flow:feature（根拠）⏎種類の提案: flow:bugfix（別の根拠）⏎EOF
deny|missing|bash|14 根拠が空の行は満たさない|gh issue create -t x --body-file - <<'EOF'⏎種類の提案: flow:feature（）⏎EOF
deny|missing|bash|15 全角コロンの行も半角括弧の行も満たさない|gh issue create -t x --body-file - <<'EOF'⏎種類の提案：flow:feature（根拠）⏎種類の提案: flow:feature(根拠)⏎EOF
deny|missing|bash|16 行頭にない行は満たさない|gh issue create -t x --body-file - <<'EOF'⏎  種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|17 ダブルクォートの中の \ は確定できないとして止める|gh issue create -t x --body "前置き⏎種類の提案: flow:feature（根拠 \"引用\"）"
pass|-|bash|18 --body-file の絶対パスで通す|gh issue create -t x --body-file @W/prop.md
pass|-|bash|19 -F の絶対パスで通す|gh issue create -t x -F @W/prop.md
pass|-|bash|20 相対パスは入力の cwd を起点に読んで通す|gh issue create -t x --body-file prop.md
pass|-|bash-nocwd|21 cwd が無ければカレントディレクトリから読んで通す|gh issue create -t x --body-file prop.md
deny|unreadable|bash|22 ファイルが無く、ラベルも無ければ止める|gh issue create -t x --body-file @W/none.md
pass|-|bash|23 ファイルが無くても、ラベルがあれば通す|gh issue create -t x --body-file @W/none.md --label flow:feature
deny|unreadable|bash|24 1 MiB を超えるファイルは止める|gh issue create -t x --body-file @W/big.md
deny|unreadable|bash|25 /dev/zero は止める|gh issue create -t x --body-file /dev/zero
pass|-|bash|26 -F - <<'EOF' で通す|gh issue create -t x -F - <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|27 パイプで渡したら止める|printf '%s\n' '種類の提案: flow:feature（根拠）' ¦ gh issue create -t x --body-file -
pass|-|bash|28 前の断片でヒアドキュメントを書いたファイルを --body-file で渡す形は通す|cat > @W/written.md <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF⏎gh issue create -t x --body-file @W/written.md
deny|unreadable|bash|29 閉じない引用符は止める|gh issue create -t x --body '種類の提案: flow:feature（根拠）
pass|-|bash|30 --body "$(cat <<'EOF'…)" で通す|gh issue create -t x --body "$(cat <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF⏎)"
deny|unreadable|bash|31 --body "$(cat f)" は止める|gh issue create -t x --body "$(cat @W/prop.md)"
deny|unreadable|bash|32 --body "$BODY" は止める|gh issue create -t x --body "$BODY"
pass|-|bash|33 バックスラッシュ改行で続けた --label flow:feature で通す|gh issue create \⏎  -t x \⏎  --label flow:feature
deny|missing|bash|34 プラグインの形(URL=$(gh issue create … --label "type:plan"))は止める|URL=$(gh issue create \⏎  --title "plan" \⏎  --body-file @W/plain.md \⏎  --label "type:plan")
deny|missing|bash|35 cd x && gh issue create も止める|cd @W && gh issue create -t x
deny|missing|bash|36 url=$(gh issue create -t x) も止める|url=$(gh issue create -t x)
deny|missing|bash|37 作成が 2 つあり、2 つ目だけ欠けていれば止める|gh issue create -t a --label flow:feature && gh issue create -t b
pass|-|bash|38 --web は通す|gh issue create --web
pass|-|bash|39 -R other/repo は通す|gh issue create -t x -R other/repo
deny|missing|bash|40 -R が大文字小文字違いの自リポジトリなら止める|gh issue create -t x -R ACME/Widgets
pass|-|bash|41 gh issue -R other/repo create は通す|gh issue -R other/repo create -t x
deny|missing|bash|42 gh issue -R <自> create は止める|gh issue -R acme/widgets create -t x
pass|-|bash|43 -R github.com/other/repo は通す|gh issue create -t x -R github.com/other/repo
pass|-|bash|44 GH_REPO=other/repo gh issue create は通す|GH_REPO=other/repo gh issue create -t x
pass|-|bash|45 gh issue list は止めない|gh issue list --label flow:feature
pass|-|bash|45 gh issue edit は止めない|gh issue edit 1 --add-label x
pass|-|bash|45 echo の中の文字列は止めない|echo 'gh issue create -t x'
pass|-|bash|45 git commit -m の中の文字列は止めない|git commit -m "gh issue create を止める"
pass|-|bash|45 grep は止めない|grep -rn "gh issue create" .
pass|-|bash|46 gh pr create のヒアドキュメント本文にある gh issue create の行は止めない|gh pr create -t x --body-file - <<'EOF'⏎gh issue create -t y⏎EOF
pass|-|bash|47 gh pr create --body の引用の中(改行入り)にある gh issue create は止めない|gh pr create -t x --body "前⏎gh issue create -t y⏎後"
miss|-|bash|48 bash -c の中は読まない|bash -c 'gh issue create -t x'
miss|-|bash|48 sh -c の中は読まない|sh -c 'gh issue create -t x'
miss|-|bash|48 eval の中は読まない|eval 'gh issue create -t x'
miss|-|bash|48 xargs の後ろは読まない|echo x ¦ xargs gh issue create -t
miss|-|bash|48 スクリプトの中は読まない|bash @W/make-issue.sh
miss|-|bash|48 gh alias は読まない|gh mkissue -t x
miss|-|bash|165 time -p の後ろは読まない|time -p gh issue create -t x
miss|-|bash|165 command -p の後ろは読まない|command -p gh issue create -t x
miss|-|bash|165 exec -a NAME の後ろは読まない|exec -a NAME gh issue create -t x
miss|-|bash|165 env -i の後ろは読まない|env -i gh issue create -t x
miss|-|bash|165 名前付きの coproc NAME { … } の中は読まない|coproc NAME { gh issue create -t x; }
deny|missing|bash|49 止めすぎを固定: export GH_REPO=other/r を先に実行しても止める|export GH_REPO=other/r; gh issue create -t x
deny|missing|bash|50 止めすぎを固定: cd ../other の後でも止める|cd ../other && gh issue create -t x
deny|unreadable|bash|51 読む位置の誤りを固定: cd sub の後の相対パスは cwd から読む|cd sub && gh issue create -t x --body-file rel.md
deny|missing|bash|52 -f title=x(暗黙の POST)は止める|gh api repos/acme/widgets/issues -f title=x
pass|-|bash|53 -f 'labels[]=flow:feature' で通す|gh api repos/acme/widgets/issues -f title=x -f 'labels[]=flow:feature'
pass|-|bash|54 -F 'labels[]=flow:feature' で通す|gh api repos/acme/widgets/issues -f title=x -F 'labels[]=flow:feature'
pass|-|bash|55 --raw-field 'labels[]=flow:feature' で通す|gh api repos/acme/widgets/issues --raw-field title=x --raw-field 'labels[]=flow:feature'
deny|missing|bash|56 --field title=x は止める|gh api repos/acme/widgets/issues --field title=x
deny|missing|bash|57 --method POST は止める|gh api --method POST repos/acme/widgets/issues
deny|missing|bash|58 -XPOST は止める|gh api -XPOST repos/acme/widgets/issues
deny|missing|bash|59 --method=post は止める|gh api --method=post repos/acme/widgets/issues
deny|missing|bash|60 --input のファイルにラベルも行もなければ止める|gh api repos/acme/widgets/issues --input @W/in-plain.json
pass|-|bash|61 --input - <<'EOF' の labels で通す|gh api repos/acme/widgets/issues --input - <<'EOF'⏎{"title":"x","labels":["flow:feature"]}⏎EOF
pass|-|bash|62 --input の body の行で通す|gh api repos/acme/widgets/issues --input @W/in-body.json
deny|unreadable|bash|63 --input が JSON でなければ止める|gh api repos/acme/widgets/issues --input @W/bad.json
pass|-|bash|64 -F body=@file で通す|gh api repos/acme/widgets/issues -f title=x -F body=@@W/prop.md
pass|-|bash|65 GET は止めない|gh api 'repos/acme/widgets/issues?state=open'
pass|-|bash|66 --method GET -f は止めない|gh api --method GET repos/acme/widgets/issues -f state=open
pass|-|bash|67 issues/12/labels への POST は止めない|gh api repos/acme/widgets/issues/12/labels -f 'labels[]=bug'
pass|-|bash|67 issues/12/comments への POST は止めない|gh api repos/acme/widgets/issues/12/comments -f body=x
deny|missing|bash|68 /repos/<自>/issues は止める|gh api /repos/acme/widgets/issues -f title=x
deny|missing|bash|69 repos/{owner}/{repo}/issues は止める|gh api 'repos/{owner}/{repo}/issues' -f title=x
pass|-|bash|70 他リポジトリは通す|gh api repos/other/repo/issues -f title=x
miss|-|bash|71 graphql の createIssue は読まない|gh api graphql -f query='mutation { createIssue(input: {repositoryId: "x", title: "y"}) { issue { id } } }'
miss|-|bash|72 curl は読まない|curl -X POST https://api.github.com/repos/acme/widgets/issues -d '{"title":"x"}'
deny|missing|mcp|73 MCP でラベルも行もなければ止める|{"method":"create","owner":"acme","repo":"widgets","title":"x","body":"本文"}
pass|-|mcp|74 MCP の flow:* ラベルで通す|{"method":"create","owner":"acme","repo":"widgets","title":"x","labels":["flow:feature"]}
deny|multiple|mcp|75 MCP で異なる flow:* が 2 つなら止める|{"method":"create","owner":"acme","repo":"widgets","title":"x","labels":["flow:feature","flow:bugfix"]}
pass|-|mcp|76 MCP で同じ flow:* が 2 つなら通す|{"method":"create","owner":"acme","repo":"widgets","title":"x","labels":["flow:feature","flow:feature"]}
pass|-|mcp|77 MCP の body の提案の行で通す|{"method":"create","owner":"acme","repo":"widgets","title":"x","body":"前置き\n種類の提案: flow:feature（根拠）"}
pass|-|mcp|78 MCP の body の通さない行で通す|{"method":"create","owner":"acme","repo":"widgets","title":"x","body":"種類: implementation-flow に通さない（棚卸し）"}
pass|-|mcp|79 MCP の update は止めない|{"method":"update","owner":"acme","repo":"widgets","issue_number":1,"title":"x"}
pass|-|mcp|80 MCP で他リポジトリは通す|{"method":"create","owner":"other","repo":"repo","title":"x"}
deny|missing|mcp|81 MCP で大文字小文字違いの自リポジトリは止める|{"method":"create","owner":"ACME","repo":"Widgets","title":"x"}
pass|-|bash|100 ダブルクォートの --body に $ も ` も \ も無ければ字面で読んで通す|gh issue create -t x --body "前置き⏎種類の提案: flow:feature（根拠）"
deny|unreadable|bash|100 ダブルクォートの --body の本文に ` があれば止める|gh issue create -t x --body "前置き `code`⏎種類の提案: flow:feature（根拠）"
pass|-|bash|101 <<EOF の本文に $ も ` も \ も無ければ字面で読んで通す|gh issue create -t x --body-file - <<EOF⏎前置き⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|101 <<EOF の本文に ` があれば止める|gh issue create -t x --body-file - <<EOF⏎前置き `code`⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|102 <<EOF の本文に \ があれば止める|gh issue create -t x --body-file - <<EOF⏎前置き \\⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|103 $(cat <<EOF) の本文に ` があれば止める|gh issue create -t x --body "$(cat <<EOF⏎前置き `code`⏎種類の提案: flow:feature（根拠）⏎EOF⏎)"
pass|-|bash|104 $(cat <<EOF) の本文に $ も ` も \ も無ければ通す|gh issue create -t x --body "$(cat <<EOF⏎前置き⏎種類の提案: flow:feature（根拠）⏎EOF⏎)"
pass|-|bash|105 <<'EOF' の本文の $ ` \ は字面のまま読んで通す|gh issue create -t x --body-file - <<'EOF'⏎前置き $X `code` \z⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|106 シングルクォートの本文の $ ` \ は字面のまま読んで通す|gh issue create -t x --body '前置き $X `code` \z⏎種類の提案: flow:feature（根拠）'
pass|-|bash|107 区切りが "EOF" なら本文の $ と ` を字面のまま読んで通す|gh issue create -t x --body-file - <<"EOF"⏎前置き $X `code`⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|107 区切りが \EOF なら本文の $ と ` を字面のまま読んで通す|gh issue create -t x --body-file - <<\EOF⏎前置き $X `code`⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|107 区切りが E'OF' なら本文の $ と ` を字面のまま読んで通す|gh issue create -t x --body-file - <<E'OF'⏎前置き $X `code`⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|108 ダブルクォートの中の $(…) は止める|gh issue create -t x --body "種類の提案: flow:feature（$(echo 根拠)）"
deny|unreadable|bash|109 ダブルクォートの中の \$ も止める|gh issue create -t x --body "種類の提案: flow:feature（\$5）"
pass|-|bash|110 <<-EOF で行頭のタブを除くと合う行は通す|gh issue create -t x --body-file - <<-EOF⏎⇥種類の提案: flow:feature（根拠）⏎⇥EOF
deny|missing|bash|111 -f body=@file は字面のまま送るので止める|gh api repos/acme/widgets/issues -f title=x -f body=@@W/prop.md
pass|-|bash|112 -Fbody=@file で通す|gh api repos/acme/widgets/issues -f title=x -Fbody=@@W/prop.md
deny|missing|bash|113 --raw-field body=@file は止める|gh api repos/acme/widgets/issues -f title=x --raw-field body=@@W/prop.md
pass|-|bash|114 -F body=@- <<'EOF' で通す|gh api repos/acme/widgets/issues -f title=x -F body=@- <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|115 -F body=@- にパイプで渡したら止める|printf '%s' '種類の提案: flow:feature（根拠）' ¦ gh api repos/acme/widgets/issues -f title=x -F body=@-
deny|unreadable|bash|116 <<< の後に続く行は本文として読まない|gh issue create -t x --body-file - <<<EOF⏎種類の提案: flow:feature（根拠）⏎EOF
deny|missing|bash|117 issues?x=1 は止める|gh api 'repos/acme/widgets/issues?x=1' -f title=x
pass|-|bash|118 issues/12/comments?x=1 は止めない|gh api 'repos/acme/widgets/issues/12/comments?x=1' -f body=x
deny|missing|bash|119 -X POST は止める|gh api -X POST repos/acme/widgets/issues
pass|-|bash|120 -X GET -f は止めない|gh api -X GET repos/acme/widgets/issues -f state=open
pass|-|bash|121 --repo other/repo は通す|gh issue create -t x --repo other/repo
deny|missing|bash|122 --repo が大文字小文字違いの自リポジトリなら止める|gh issue create -t x --repo Acme/WIDGETS
pass|-|bash|123 -b に行があれば通す|gh issue create -t x -b '種類の提案: flow:feature（根拠）'
deny|missing|bash|124 -b に行がなければ止める|gh issue create -t x -b '本文だけ'
deny|unreadable|bash|125 ダブルクォートの中で ` の範囲が提案の行をまたぐなら止める|gh issue create -t x --body "前 `echo⏎種類の提案: flow:feature（根拠）⏎` 後"
deny|unreadable|bash|126 <<EOF の中で $(… の範囲が提案の行をまたぐなら止める|gh issue create -t x --body-file - <<EOF⏎説明 $(true⏎種類の提案: flow:feature（根拠）⏎)⏎EOF
pass|-|bash|127 シングルクォートの本文に cat <<EOF と提案の行があれば通す|gh issue create -t x --body '前⏎cat <<EOF⏎種類の提案: flow:feature（根拠）⏎EOF⏎後'
pass|-|bash|128 ダブルクォートの本文に cat <<EOF と提案の行があれば通す|gh issue create -t x --body "前⏎cat <<EOF⏎種類の提案: flow:feature（根拠）⏎EOF⏎後"
deny|unreadable|bash|168 "$(cat <<'EOF' …)" の区切りの行と閉じ括弧の間にパイプが続けば止める|gh issue create -t x --body "$(cat <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF⏎¦ tr a b)"
pass|-|bash|129 $(cat <<'EOF') の本文に " と ) を含む行があっても通す|gh issue create -t x --body "$(cat <<'EOF'⏎" ) を含む行⏎種類の提案: flow:feature（根拠）⏎EOF⏎)"
deny|unreadable|bash|130 止めすぎを固定: $(sed … <<'EOF' …) は止める|gh issue create -t x --body "$(sed s/a/b/ <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF⏎)"
deny|missing|bash|131 --label "flow:$K" だけなら止める|gh issue create -t x --label "flow:$K"
pass|-|bash|132 --label "flow:$K" と --label flow:feature なら通す|gh issue create -t x --label "flow:$K" --label flow:feature
deny|missing|bash|133 -R "$REPO" は自リポジトリとして止める|gh issue create -t x -R "$REPO"
deny|missing|bash|133 --repo "$REPO" は自リポジトリとして止める|gh issue create -t x --repo "$REPO"
deny|missing|bash|134 GH_REPO=$R gh issue create は止める|GH_REPO=$R gh issue create -t x
pass|-|bash|135 --field body=@file で通す|gh api repos/acme/widgets/issues -f title=x --field body=@@W/prop.md
deny|unreadable|bash|136 <<EOF の提案の行に $(echo 根拠) を含むなら止める|gh issue create -t x --body-file - <<EOF⏎種類の提案: flow:feature（$(echo 根拠)）⏎EOF
deny|unreadable|bash|137 <<EOF の提案の行に $R を含むなら止める|gh issue create -t x --body-file - <<EOF⏎種類の提案: flow:feature（$R）⏎EOF
deny|unreadable|bash|138 止めすぎを固定: <<EOF の本文の \$ も確定できないとして止める|gh issue create -t x --body-file - <<EOF⏎種類の提案: flow:feature（根拠 \$5）⏎EOF
deny|unreadable|bash|139 残る穴を固定: $'a\'b…' は止める|gh issue create -t x --body $'a\'b⏎種類の提案: flow:feature（根拠）'
pass|-|bash|141 URL=$(gh issue create --body-file - <<'EOF' …) で通す|URL=$(gh issue create --body-file - <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF⏎)
pass|-|bash|142 gh を含まず字句に分けられないコマンドは通す|echo 'issue の話
deny|missing|bash|143 for … do の後ろの作成も止める|for i in 1; do gh issue create -t x; done
deny|missing|bash|144 if … then の後ろの作成も止める|if true; then gh issue create -t x; fi
deny|missing|bash|145 else の後ろの作成も止める|if false; then :; else gh issue create -t x; fi
deny|missing|bash|146 { … } の中の作成も止める|{ gh issue create -t x; }
deny|missing|bash|147 ! の後ろの作成も止める|! gh issue create -t x
deny|missing|bash|148 time の後ろの作成も止める|time gh issue create -t x
deny|missing|bash|149 command の後ろの作成も止める|command gh issue create -t x
deny|missing|bash|150 env VAR=val の後ろの作成も止める|env FOO=1 gh issue create -t x
pass|-|bash|151 env GH_REPO=other/repo の後ろの作成は通す|env GH_REPO=other/repo gh issue create -t x
deny|missing|bash|164 if の直後の作成も止める|if gh issue create -t x; then :; fi
deny|missing|bash|164 elif の直後の作成も止める|if false; then :; elif gh issue create -t x; then :; fi
deny|missing|bash|164 while の直後の作成も止める|while gh issue create -t x; do break; done
deny|missing|bash|164 until の直後の作成も止める|until gh issue create -t x; do :; done
deny|missing|bash|164 if ! の後ろの作成も止める|if ! gh issue create -t x; then :; fi
deny|missing|bash|164 coproc の後ろの作成も止める|coproc gh issue create -t x
deny|missing|bash|164 exec の後ろの作成も止める|exec gh issue create -t x
deny|missing|bash|152 ダブルクォートの中の $(gh issue create …) も止める|url="$(gh issue create -t x)"
deny|missing|bash|153 ダブルクォートの中の `gh issue create …` も止める|url="`gh issue create -t x`"
deny|missing|bash|154 クォートの外の `gh issue create …` も止める|x=`gh issue create -t x`
deny|missing|bash|155 echo の引数の `gh issue create …` も止める|echo `gh issue create -t x`
deny|missing|bash|156 <<EOF の本文の $(gh issue create …) も止める|cat <<EOF⏎$(gh issue create -t x)⏎EOF
pass|-|bash|157 シングルクォートの中の $(gh issue create …) は止めない|echo '$(gh issue create -t x)'
pass|-|bash|166 区切りが 'EOF' のヒアドキュメントの本文の $(gh issue create …) は止めない|gh pr create -t x --body-file - <<'EOF'⏎$(gh issue create -t y)⏎EOF
deny|missing|bash|167 "$(cat <<EOF …)" の本文の $(gh issue create …) も止める|gh pr create -t x --body "$(cat <<EOF⏎$(gh issue create -t y)⏎EOF⏎)"
deny|missing|bash|158 repos/:owner/:repo/issues は自リポジトリとして止める|gh api repos/:owner/:repo/issues -f title=x
deny|missing|bash|159 作成先が展開の "repos/$R/issues" は自リポジトリとして止める|gh api "repos/$R/issues" -f title=x
deny|unreadable|bash|160 閉じない ` の後ろの gh を含むなら止める|x=`gh issue create -t x
deny|unreadable|bash|161 閉じない " の後ろの gh を含むなら止める|echo "gh issue create -t x
deny|unreadable|bash|162 閉じない ' の後ろの gh を含むなら止める|echo 'gh issue create -t x
deny|unreadable|bash|163 止めすぎを固定: 算術の ((…<<…)) の後ろの作成はラベルがあっても止める|(( x = 1<<2 )); gh issue create -t x --label flow:feature
pass|-|bash|163 $((…<<…)) は中身を別に読むので、ラベルのある作成は通す|gh issue create -t $((1<<2)) --label flow:feature
deny|missing|bash|169 --input があれば -f 'labels[]=flow:*' はクエリに回るので止める|gh api repos/acme/widgets/issues --input @W/in-plain.json -f 'labels[]=flow:feature'
deny|missing|bash|169 --input があれば -f body= の提案の行はクエリに回るので止める|gh api repos/acme/widgets/issues --input @W/in-plain.json -f body='種類の提案: flow:feature（根拠）'
deny|missing|bash|169 --input を 2 つ書けば最後のものを読む|gh api repos/acme/widgets/issues --input @W/in-body.json --input @W/in-plain.json
pass|-|bash|169 --input を 2 つ書き、最後のものに提案の行があれば通す|gh api repos/acme/widgets/issues --input @W/in-plain.json --input @W/in-body.json
deny|unreadable|bash|170 ヒアドキュメントの後の < file が標準入力になるなら止める|gh issue create -t x --body-file - <<'EOF' < @W/plain.md⏎種類の提案: flow:feature（根拠）⏎EOF
deny|unreadable|bash|170 ヒアドキュメントの後の <<< が標準入力になるなら止める|gh issue create -t x --body-file - <<'EOF' <<< x⏎種類の提案: flow:feature（根拠）⏎EOF
pass|-|bash|170 < file の後のヒアドキュメントが標準入力になるなら通す|gh issue create -t x --body-file - < @W/plain.md <<'EOF'⏎種類の提案: flow:feature（根拠）⏎EOF
deny|missing|bash|171 根拠が空白だけの行は満たさない|gh issue create -t x -b '種類の提案: flow:feature（ 　 ）'
pass|-|bash|171 根拠の前後に空白があっても通す|gh issue create -t x -b '種類の提案: flow:feature（ 根拠 ）  '
deny|missing|bash|172 --body-file があれば --body の提案の行は送られないので止める|gh issue create -t x -b '種類の提案: flow:feature（根拠）' --body-file @W/plain.md
deny|missing|bash|172 --body-file を後に書いても前に書いても --body-file を読む|gh issue create -t x --body-file @W/plain.md -b '種類の提案: flow:feature（根拠）'
deny|missing|bash|172 --body を 2 つ書けば最後のものを読む|gh issue create -t x -b '種類の提案: flow:feature（根拠）' -b '本文だけ'
pass|-|bash|172 --body を 2 つ書き、最後のものに提案の行があれば通す|gh issue create -t x -b '本文だけ' -b '種類の提案: flow:feature（根拠）'
deny|missing|bash|172 --body-file を 2 つ書けば最後のものを読む|gh issue create -t x --body-file @W/prop.md --body-file @W/plain.md
pass|-|bash|173 クォートした () は区切りでないので、ラベルのある作成は通す|gh issue create --title '()' -l flow:feature
pass|-|bash|173 ダブルクォートした ; は区切りでないので、ラベルのある作成は通す|gh issue create --title ";" -l flow:feature
pass|-|bash|173 \¦ は区切りでないので、ラベルのある作成は通す|gh issue create --title \¦ -l flow:feature
deny|missing|bash|174 --web=false は作成するので止める|gh issue create -t x --web=false
deny|missing|bash|174 -w=false は作成するので止める|gh issue create -t x -w=false
deny|missing|bash|174 --web の後の --web=0 は作成するので止める|gh issue create -t x --web --web=0
pass|-|bash|174 --web=true は通す|gh issue create -t x --web=true
pass|-|bash|174 -l=flow:feature は gh が値として読むので通す|gh issue create -t x -l=flow:feature
CASES
)"

# 82 は、自リポジトリを `-R` で明示したものを止め、他のリポジトリを通すことの対で見る(片方だけだと、
# 読めずに空とみなした場合か、読み違えた場合のどちらかを通してしまう)。
origin_cases="$(cat <<'CASES'
deny|https://github.com/acme/widgets|82 https の origin から自リポジトリを読む|gh issue create -t x -R acme/widgets
pass|https://github.com/acme/widgets|82 https の origin で他リポジトリは通す|gh issue create -t x -R other/repo
deny|https://github.com/acme/widgets.git|82 .git 付きの origin から自リポジトリを読む|gh issue create -t x -R acme/widgets
pass|https://github.com/acme/widgets.git|82 .git 付きの origin で他リポジトリは通す|gh issue create -t x -R other/repo
deny|git@github.com:acme/widgets.git|82 ssh の origin から自リポジトリを読む|gh issue create -t x -R acme/widgets
pass|git@github.com:acme/widgets.git|82 ssh の origin で他リポジトリは通す|gh issue create -t x -R other/repo
deny|http://proxy@127.0.0.1:8080/git/acme/widgets|82 パス付きの origin から自リポジトリを読む|gh issue create -t x -R acme/widgets
pass|http://proxy@127.0.0.1:8080/git/acme/widgets|82 パス付きの origin で他リポジトリは通す|gh issue create -t x -R other/repo
deny||83 origin の URL が空なら -R other も止める|gh issue create -t x -R other/repo
CASES
)"

# 2 つの表を、検出器に渡す 1 行 1 ケースの形にそろえる(origin の表は分類 missing・形 bash)。
detector_rows() {
  local expected category form label input origin
  while IFS='|' read -r expected category form label input; do
    [ -n "$label" ] && printf 'cases|%s|%s|%s|%s|%s|%s\n' "$expected" "$category" "$form" "$own_origin" "$label" "$input"
  done <<<"$cases"
  while IFS='|' read -r expected origin label input; do
    [ -n "$label" ] && printf 'origin_cases|%s|missing|bash|%s|%s|%s\n' "$expected" "$origin" "$label" "$input"
  done <<<"$origin_cases"
}

verdicts="$(detector_rows | python3 -c "$detector_runner" "$detector" "$work")"

# 判定を表ごとに報告する。
#
# $1 表の名前
report_verdicts() {
  local table expected decision label
  while IFS='|' read -r table expected decision label; do
    [ "$table" = "$1" ] || continue
    report_case "$expected" "$(expected_decision "$expected" "$decision")" "$label"
  done <<<"$verdicts"
}

report_column_count cases 5 "$cases"
report_column_count origin_cases 4 "$origin_cases"

cases_before=$cases_reported
report_verdicts cases
report_cases_ran cases "$cases_before"

cases_before=$cases_reported
report_verdicts origin_cases
report_cases_ran origin_cases "$cases_before"

hook_copy="$work/hook-copy"
hook="$hook_copy/.claude/hooks/block-issue-without-flow-kind.sh"

# フックと、フックが読むものだけを、リポジトリと同じ相対位置で一時ディレクトリへ写す。
copy_hook() {
  copy_repo_files "$hook_copy" .claude/hooks/block-issue-without-flow-kind.sh .claude/hooks/lib/issue-flow-kind-violations.py
}

# 写しの検出器を、実物か落ちるスタブにする。
#
# $1 `real` か、`place_failing_detector` の落ち方
place_hook_detector() {
  local target="$hook_copy/.claude/hooks/lib/issue-flow-kind-violations.py"
  if [ "$1" = "real" ]; then
    cp "$detector" "$target"
    return 0
  fi
  place_failing_detector "$1" "$target"
}

# フックを走らせ、標準出力を返す。終了コードはそのまま返す。
#
# $1 検出器(`place_hook_detector` に渡すもの)
# $2 python3(`ok` / `broken`)
# $3 jq(`ok` / `broken`)
# $4 PreToolUse の JSON
run_hook() {
  local prefix status=0
  place_hook_detector "$1"
  prefix="$(broken_command_path_prefix python3 "$2" "$work")$(broken_command_path_prefix jq "$3" "$work")"
  printf '%s' "$4" | PATH="${prefix}${PATH}" bash "$hook" 2>/dev/null || status=$?
  rm -rf "$work/broken-bin"
  return "$status"
}

copy_hook
# フックは origin を自リポジトリとして検出器へ渡す。写しを git リポジトリにしないと origin が空になり、
# 渡し損ねても空どうしで判定が合ってしまう。
git -C "$hook_copy" init -q && git -C "$hook_copy" remote add origin "$own_origin"

hook_cases="$(cat <<'CASES'
deny|real|ok|ok|84 欠けた作成は deny になる|gh issue create -t x
pass|real|ok|ok|88 ラベル付きの MCP 作成は通す|@mcp {"method":"create","owner":"acme","repo":"widgets","title":"x","labels":["flow:feature"]}
deny|crash|ok|ok|89 traceback で落ちる検出器なら deny になる|gh issue create -t x
deny|summary-exit1|ok|ok|89 報告の行を出さずに exit 1 で終わる検出器なら deny になる|gh issue create -t x
deny|usage|ok|ok|89 exit 2 で終わる検出器なら deny になる|gh issue create -t x
pass|crash|ok|ok|90 検出器が落ちても git status は通す|git status
pass|real|broken|ok|91 python3 が起動できなければ通す|gh issue create -t x
deny|real|ok|broken|92 jq が exit 127 で落ちても deny する|gh issue create -t x
deny|real|ok|ok|93 gh と issue の間の空白が 2 つでも deny する|gh  issue create -t x
deny|real|ok|ok|94 gh issue -R <自> create は deny する|gh issue -R acme/widgets create -t x
pass|real|ok|ok|95 -R other/repo の作成は通す|gh issue create -t x -R other/repo
CASES
)"
report_column_count hook_cases 6 "$hook_cases"

# 表の入力から PreToolUse の JSON を組む。`@mcp ` で始まれば MCP の入力、それ以外は Bash のコマンド。
#
# $1 表に書いた入力
hook_payload() {
  case "$1" in
    "@mcp "*) payload mcp "${1#@mcp }" ;;
    *) payload bash "$1" ;;
  esac
}

cases_before=$cases_reported
while IFS='|' read -r expected stub python3_state jq_state label input; do
  [ -n "$label" ] || continue
  output="$(run_hook "$stub" "$python3_state" "$jq_state" "$(hook_payload "$input")")" && status=0 || status=$?
  report_case "$expected" "$(judge_output "$output" "$status")" "$label"
done <<<"$hook_cases"
report_cases_ran hook_cases "$cases_before"

# 拒否文は、欠けた作成 1 件で一度だけ取り、文面と並びを見る(JSON の文字列から戻して、引用符や `\` を字面で比べる)。
reason="$(run_hook real ok ok "$(payload bash 'gh issue create -t x')" |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])')"

# 拒否文の中で、文が最初に現れる位置を返す。無ければ -1。
#
# $1 探す文
position_in_reason() {
  local head="${reason%%"$1"*}"
  [ "$head" = "$reason" ] && echo -1 && return 0
  echo "${#head}"
}

reason_cases="$(cat <<'CASES'
85 理由に提案の行の書式が載る|種類の提案: flow:<種類>（<根拠>）
87 理由に「種類の確定」の手順 4 が載る|「種類の確定」の手順 4
140 理由に拒否文の 6 番目が全文のまま載る|本文はシングルクォート、'EOF' のヒアドキュメント、"$(cat <<'EOF' … EOF)" のどれかで渡す（ダブルクォートや、区切りをクォートしないヒアドキュメントの本文は、$ ` \ を含むと確定できないとして止まる）。相対パスで読めなければ絶対パスにする
CASES
)"
report_column_count reason_cases 2 "$reason_cases"

cases_before=$cases_reported
while IFS='|' read -r label text; do
  [ -n "$label" ] || continue
  found="載る"
  [ "$(position_in_reason "$text")" -ge 0 ] || found="載らない"
  report_case "載る" "$found" "$label"
done <<<"$reason_cases"
report_cases_ran reason_cases "$cases_before"

# 86: 人に尋ねる道が、人がいない起動の行と書式より先に出る(拒否文が写せる行を先に出すと、
# 対話中でも人に尋ねない道が最短になる)。
ask_at="$(position_in_reason AskUserQuestion)"
unattended_at="$(position_in_reason 人がいない起動)"
format_at="$(position_in_reason '種類の提案: flow:<種類>')"
asks_before_both=$(( ask_at >= 0 && ask_at < unattended_at && ask_at < format_at ))
asks_first="後"
[ "$asks_before_both" -eq 1 ] && asks_first="先"
report_case "先" "$asks_first" "86 「人に尋ね」が「人がいない起動」と書式より前に出る"

# CLI として、PreToolUse の JSON のオブジェクトでない入力を使い方の誤り(exit 2)として扱うかを見る。
cli_cases="$(cat <<'CASES'
2|96 JSON の配列の入力は exit 2 で終える|[]
2|96 JSON の null の入力は exit 2 で終える|null
CASES
)"
report_column_count cli_cases 3 "$cli_cases"

cases_before=$cases_reported
while IFS='|' read -r expected label input; do
  [ -n "$label" ] || continue
  printf '%s' "$input" | python3 "$detector" --origin-url "$own_origin" >/dev/null 2>&1 && status=0 || status=$?
  report_case "exit=$expected" "exit=$status" "$label"
done <<<"$cli_cases"
report_cases_ran cli_cases "$cases_before"

report_documented_kinds "$detector"
report_covered_kinds "$detector" "$(kinds_in_categories "$cases" issue-flow-kind-)"

exit "$cases_failed"
