#!/usr/bin/env bash
#
# `block-protected-branch-edit.sh` の判定表。一時リポジトリでブランチと作業ディレクトリを変えながら
# 編集ツールの PreToolUse の入力をフックへ流し、保護ブランチの編集の拒否と素通りが期待どおりかを
# 1 コマンドで確かめる。
#
# 使い方: bash .claude/hooks/lib/protected-branch-edit-cases.sh
# 出力が `ok` だけなら期待どおり。`NG` が 1 行でも出たら判定が変わっている。
#
# 期待の種類は `case-table.sh` の冒頭。
#
# ケースを一時リポジトリに置くのは、本物のリポジトリのブランチを切り替えずに保護ブランチの上を作るため。
# 「git の外」は `$work/outside` で、フックを呼ぶたびに `GIT_CEILING_DIRECTORIES=$work` を付けて
# 一時ディレクトリより上のリポジトリを探させない。
#
# 表の 1 行は `期待|リポジトリの形|作業ディレクトリ|入力|ケース名`。リポジトリの形は `prepare_repo`、入力は
# `edit_call_input` の引数。判定は `case-table.sh` の `judge_payload`。
#
# フックは bash と git だけで走る(jq を使わない。判定の読み取りは `case-table.sh` が python3 で行う)。
# コミットには user と `commit.gpgsign=false` をその場で渡す(CI のランナーには user が無く、署名を求める
# 環境もあるため)。
set -uo pipefail

lib_dir="$(cd "$(dirname "$0")" && pwd)"
. "$lib_dir/case-table.sh"

hook="$lib_dir/../block-protected-branch-edit.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/outside"

# 呼び出し元から渡った GIT_DIR などが、一時リポジトリへの git の操作に効かないよう外す。
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# 一時リポジトリで git を走らせる。
#
# $@ git のサブコマンドと引数
repo_git() {
  git -C "$work/repo" -c user.name=cases -c user.email=cases@example.invalid -c commit.gpgsign=false "$@"
}

# main に空コミットを 2 つ積んだ一時リポジトリを作り直す。
repo_with_two_commits() {
  rm -rf "$work/repo"
  git init -q -b main "$work/repo"
  repo_git commit -q --allow-empty -m a
  repo_git commit -q --allow-empty -m b
}

# 一時リポジトリを表の形に作り直す。
#
# $1 リポジトリの形(`unborn` はコミットの無い main、`branch:<名前>` は 2 コミットの main から切ったブランチ
#    (`branch:main` は main のまま)、`detached-tip` は main の先端の detached HEAD、`detached-shared-tip` は
#    作業ブランチも並ぶ main の先端の detached HEAD、`detached-parent` は main~1 の detached HEAD、
#    `detached-orphan` は main の先端で detach してコミットを 1 つ積んだもの)
prepare_repo() {
  case "$1" in
    unborn)
      rm -rf "$work/repo"
      git init -q -b main "$work/repo"
      ;;
    branch:main) repo_with_two_commits ;;
    branch:*) repo_with_two_commits && repo_git checkout -q -b "${1#branch:}" ;;
    detached-tip) repo_with_two_commits && repo_git checkout -q --detach main ;;
    detached-shared-tip) repo_with_two_commits && repo_git branch claude/x && repo_git checkout -q --detach main ;;
    detached-parent) repo_with_two_commits && repo_git checkout -q --detach main~1 ;;
    detached-orphan) repo_with_two_commits && repo_git checkout -q --detach main && repo_git commit -q --allow-empty -m c ;;
  esac
}

# 編集ツールの PreToolUse の入力を書く。
#
# $1 入力の形(`Edit` は一時リポジトリの中の Edit、`Edit-outside` はリポジトリの外の Edit、
#    `NotebookEdit` は一時リポジトリの中の NotebookEdit)
edit_call_input() {
  case "$1" in
    Edit) printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/a.ts"}}' "$work" ;;
    Edit-outside) printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/a.ts"}}' "$work" ;;
    NotebookEdit) printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s/repo/a.ipynb"}}' "$work" ;;
  esac
}

cases_before=$cases_reported
while IFS='|' read -r expected shape cwd tool label; do
  prepare_repo "$shape"
  verdict="$(cd "$work/$cwd" && GIT_CEILING_DIRECTORIES="$work" judge_payload "$hook" "$(edit_call_input "$tool")")"
  report_case "$expected" "$(expected_decision "$expected" "$verdict")" "$label"
done <<'CASES'
deny|branch:main|repo|Edit|main で編集すると止める
deny|unborn|repo|Edit|コミットの無い main（git init 直後）でも止める
deny|branch:master|repo|Edit|master で編集すると止める
deny|branch:production|repo|Edit|production で編集すると止める
deny|branch:release|repo|Edit|release で編集すると止める
deny|branch:develop|repo|Edit|develop で編集すると止める
deny|branch:staging|repo|Edit|staging で編集すると止める
deny|branch:main|repo|NotebookEdit|ツール名で絞らない（NotebookEdit の入力でも main なら止める）
deny|detached-tip|repo|Edit|main の先端の detached HEAD（他の参照が並ばない）でも止める
overdeny|branch:main|repo|Edit-outside|作業ディレクトリが main のリポジトリなら、編集先がリポジトリの外でも止める
pass|branch:claude/x|repo|Edit|claude/x のような作業ブランチは通す
pass|branch:main-fix|repo|Edit|main で始まる別名のブランチ main-fix は通す
pass|branch:mainline|repo|Edit|main で始まる別名のブランチ mainline は通す
pass|branch:feature/main|repo|Edit|main で終わるブランチ feature/main は通す
pass|detached-parent|repo|Edit|main~1 の detached HEAD は通す
pass|detached-orphan|repo|Edit|どのブランチにも含まれない detached HEAD は通す
pass|branch:main|outside|Edit-outside|作業ディレクトリも編集先も git の外なら通す
miss|branch:main|outside|Edit|作業ディレクトリが git の外なら、編集先が main のリポジトリの中でも見ない
miss|detached-shared-tip|repo|Edit|main の先端に作業ブランチも並ぶ detached HEAD は見ない
CASES
report_cases_ran CASES "$cases_before"
exit "$cases_failed"
