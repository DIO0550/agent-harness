#!/usr/bin/env bash
#
# 保護ブランチの編集の禁止: 作業ディレクトリのブランチが保護ブランチ（一覧は下の `protected_branches`）のとき、
# ファイルの編集を拒否する PreToolUse フック。
# 由来: d-market-git / git-workflow-plugin の branch-protection.sh（1135a0d）
#
# 方針: 編集は作業ブランチで行う。
#
# 入力: stdin の JSON は見ない（どのツールで呼ぶかは settings.json の matcher が決める）
# 出力: 違反時に permissionDecision=deny の JSON を返す。問題なければ exit 0。
#
# ツール名を見ないのは、編集ツールの一覧を matcher の 1 か所で持つため。入力を読まないので jq も使わない。
# 出力の JSON は jq ではなく printf で組むので、拒否文に `"` と `\` を入れない（改行は `\\n` と書く）。
#
# detached HEAD では `git describe --contains --all` の名前が保護ブランチと一致するときだけ止める。`main~1` の
# ような祖先まで止めると、bisect や過去のコミットを見るための checkout の最中の編集まで止まる。
set -uo pipefail

cat >/dev/null

protected_branches=(main master production release develop staging)

branch="$(git branch --show-current 2>/dev/null)" || exit 0
[ -n "$branch" ] || branch="$(git describe --contains --all HEAD 2>/dev/null)"

for protected_branch in "${protected_branches[@]}"; do
  [ "$branch" = "$protected_branch" ] || continue
  printf -v protected_list '%s, ' "${protected_branches[@]}"
  reason="保護されたブランチ'${branch}'での編集は禁止されています。\\n\\n実装ルール:\\n- 保護されたブランチ（${protected_list%, }）への直接的な変更は禁止です\\n- 機能開発や修正は必ず別ブランチで行ってください\\n- 作業完了後、プルリクエスト経由でマージしてください\\n\\n推奨手順:\\n1. 新しいブランチを作成: git checkout -b feature/your-feature-name\\n2. 変更を実装\\n3. プルリクエストを作成してレビューを受ける"
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "PreToolUse",\n    "permissionDecision": "deny",\n    "permissionDecisionReason": "%s"\n  }\n}\n' "$reason"
  exit 0
done
exit 0
