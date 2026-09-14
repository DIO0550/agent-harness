#!/usr/bin/env bash
#
# セッション URL の提示: セッションの開始時に、そのセッションの URL と
# 「Issue に紐づく作業ならその Issue へコメントする」ことを AI へ渡す SessionStart フック。
#
# 対応する規約: AGENTS.md「Issue に紐づいて起動したら、セッションの URL を Issue に残す」
#
# **URL はセッションの中からしか作れない。** 規約だけに置いていた頃は、止まった経緯が
# セッションの中にしか無いのに Issue から辿れない状態が実際に起きた
# (ある Issue の 3 コメントはいずれも URL が無く、調査を書いたセッションを特定できなかった)。
# 規約(層 4)は読まれたときにしか効かないので、開始時に必ず渡る層 3 へ上げる。
#
# **対象の Issue 番号までは決められない。** ブランチ名が `claude/issue-<N>-...` の形なら
# そこから引けるが、`claude/epic-fermi-8egj5r` のような自動生成名で起動するセッションも
# あり、そちらは痕跡が残らない。番号を引けたときだけ添え、引けなければ「紐づく Issue が
# あれば」の形で渡して、対象の特定は自分のプロンプトを読める AI 側に委ねる。
#
# フックから直接コメントを投げない。投げるには対象の Issue 番号が要るが、
# 上のとおりフックからは確実に決められない。宛先を間違えたコメントは消しても通知が残る。
#
# **外部コマンドに依存しない。** SessionStart の失敗はフェイルオープンかつサイレントで、
# 「渡されなかった」ことに誰も気づけない(hook-canary.sh と同じ理由)。jq が無い環境で
# 黙って落ちると、まさに防ぎたい「URL が残らない」状態に戻るため、判定も出力も
# bash の組み込みだけで完結させる。
set -uo pipefail

# 標準入力の SessionStart ペイロードは読み捨てる。使う値(URL の素とブランチ)は
# どちらもペイロードに無く、環境変数と git から採るため。
# 読まないままだと、書き込み側が SIGPIPE で落ちることがある。
cat >/dev/null

# `cse_<id>` から `https://claude.ai/code/session_<id>` を作る(実測した対応)。
# ローカルの CLI セッションにはこの変数が無い = URL が存在しないので、その場合は黙って何も渡さない。
remote_session_id="${CLAUDE_CODE_REMOTE_SESSION_ID:-}"
session_id_pattern='^cse_[A-Za-z0-9]+$'
[[ "$remote_session_id" =~ $session_id_pattern ]] || exit 0

session_url="https://claude.ai/code/session_${remote_session_id#cse_}"

# ブランチ名から Issue 番号を引く。引けなければ空のままにする。
branch=""
if command -v git >/dev/null 2>&1; then
  branch="$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

issue_number=""
issue_branch_pattern='^claude/issue-([0-9]+)-'
if [[ "$branch" =~ $issue_branch_pattern ]]; then
  issue_number="${BASH_REMATCH[1]}"
fi

if [ -n "$issue_number" ]; then
  target="ブランチ ${branch} から、対象は #${issue_number} と読める。"
else
  target="紐づく Issue があれば(自分が受け取った依頼を読んで判断すること)、"
fi

# 出力は JSON。message には二重引用符・バックスラッシュ・生の改行を入れない
# (jq を使わずに組み立てるため。改行は \n のまま JSON のエスケープとして渡す)。
message="このセッションの URL は ${session_url}。${target}着手した時点でその Issue へこの URL をコメントすること(AGENTS.md「Issue に紐づいて起動したら、セッションの URL を Issue に残す」)。\\n同じ URL のコメントが既にあれば足さない。判断待ちで止まるときは、選択肢と根拠を書いたコメントに改めて併記する。"

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${message}"
  }
}
JSON
