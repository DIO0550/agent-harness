#!/usr/bin/env bash
#
# 分類ごとの「最後の介入以降の再発数」を数える。
# harness-growth スキル（.claude/skills/harness-growth/SKILL.md）の Step 1 / Step 3 の入力。
#
# 読むのは記録の次の 4 種類の行:
#   - 分類: `<分類>`                       … 指摘 1 件
#   - 出どころ: `<出どころ>`               … 直前の「分類」の指摘を誰が見つけたか
#   - 対策済: `<分類>` 層=<層> at pr-<番号> … その回に介入したこと
#   - 見送り: `<分類>` at pr-<番号>        … 縮める候補を見送ったこと（--shrink が数える）
#
# 使い方:
#   count.sh            分類ごとの再発数・すり抜け・通算・以降・最終介入を出す（増やす側）
#   count.sh --shrink   縮める側の条件を数字で出す（Step 3 の棚卸し。--unused を含む）
#   count.sh --unused   語彙表にあるが記録に 1 件も出ていない分類だけを出す
#
# 出力の列:
#   再発      最後の介入より後の記録に出た件数。2a / 2b / 2c の判断はこれで行う
#   すり抜け  再発のうち出どころが人・bot だった件数。plan-reviewer も
#             implementation-reviewer も捕まえられなかった＝ハーネスが効かなかった証拠。
#             サブエージェントが捕まえた分は逆に効いた証拠なので、混ぜて数えない
#   通算      全記録での件数。語彙が飽和していないかを目視するときの参考
#   以降      最後の介入より後の記録の本数（「介入後 N 本再発ゼロ」の N）
#   最終介入  最後に置いた層と、その回の PR 番号。無ければ「未介入」
set -euo pipefail

cd "$(dirname "$0")"

vocabulary="../../.claude/skills/harness-record/templates/record.md"

# 記録が 1 本も無いうちに数えると、`pr-*.md` が展開されないまま grep へ渡って
# 「そんなファイルは無い」とだけ出る。数えるものが無いことと、数え方が壊れていることを
# 読み分けられないので、先に分けて返す。
shopt -s nullglob
existing_records=(pr-*.md)
shopt -u nullglob
if [ "${#existing_records[@]}" -eq 0 ]; then
  printf '%s\n' "記録がまだ 1 本も無い。マージのたびに harness-record スキルが 1 ファイル足す。"
  exit 0
fi

# 語彙表にあるのに記録へ 1 件も出ていない分類を 1 行 1 件で返す。
# 「効いているから 0」と「読まれていないから 0」は記録では区別できないので、
# 強制の有無での切り分けは harness-growth の Step 3 が行う。
unused_tags() {
  used="$(grep -h '^- 分類: `' pr-*.md | sed 's/^- 分類: `\([^`]*\)`.*/\1/' | sort -u)"
  # 「分類の語彙」の表だけを読む（同じ書式の「層の語彙」の表を拾わないため）
  awk '/^## 分類の語彙/{inside=1; next} /^## /{inside=0} inside' "$vocabulary" \
    | sed -n 's/^| `\([a-z-]*\)` | .*/\1/p' | sort -u | while read -r tag; do
    printf '%s\n' "$used" | grep -qx "$tag" || printf '%s\n' "$tag"
  done
}

# 1 つの記録の中で「分類」行と、その次に現れる「出どころ」行が指摘 1 件の対になる。
# 指定した分類の件数と、そのうち出どころが人・bot だった件数を "<件数> <すり抜け>" で返す。
#
# pr-317 以前は出どころの綴りが割れている（`レビュー` / `レビュー（人間）` /
# `レビュー（human）` / `レビュー（オーナー）` / `レビュー（Copilot）`）。過去の記録は
# 書き換えない規約なので、読む側が古い綴りも人・bot として扱う
# （.claude/skills/harness-record/templates/record.md「出どころの語彙」）。
count_tag() {
  awk -v want="$2" '
    /^- 分類: `/ {
      tag = $0
      sub(/^- 分類: `/, "", tag)
      sub(/`.*/, "", tag)
      pending = (tag == want)
      next
    }
    /^- 出どころ:/ {
      if (pending) {
        found++
        # 括弧なしの `レビュー` は pr-317 以前に人のレビューを指していた綴り。
        byBareReview = ($0 ~ /^- 出どころ: *`?レビュー`? *$/)
        # 語彙表の `レビュー（人）` `レビュー（bot）` と、それ以前の綴り。
        byHumanOrBot = ($0 ~ /^- 出どころ: *`?レビュー（(人間|人|human|オーナー|owner|Copilot|bot)）/)
        if (byBareReview || byHumanOrBot) {
          escaped++
        }
        pending = 0
      }
      next
    }
    END { printf "%d %d\n", found, escaped }
  ' "$1"
}

# 分類ごとの集計行を返す（列は「出力の列」のとおり・並べ替えは呼び出し側で行う）。
# 既定の表と --shrink の両方が読むので、数え方をここ 1 箇所に持つ。
summary_rows() {
tags="$(grep -h '^- 分類: `' pr-*.md | sed 's/^- 分類: `\([^`]*\)`.*/\1/' | sort -u)"

body=""
for tag in $tags; do
  # 同じ分類の対策済が複数あれば、PR 番号が最大のものが最後の介入
  last="$( { grep -hoE "^- 対策済: \`$tag\` 層=[^ ]+ at pr-[0-9]+" pr-*.md || true; } \
    | sed 's/.*層=\([^ ]*\) at pr-\([0-9]*\)/\2 \1/' | sort -n | tail -1)"
  if [ -n "$last" ]; then
    last_pr="${last%% *}"
    intervention="pr-${last_pr}（層=${last##* }）"
  else
    last_pr=0
    intervention="未介入"
  fi

  recurrence=0
  escape=0
  total=0
  after=0
  for record in pr-*.md; do
    number="${record#pr-}"
    number="${number%.md}"
    read -r count escaped <<EOF
$(count_tag "$record" "$tag")
EOF
    total=$((total + count))
    [ "$number" -gt "$last_pr" ] || continue
    recurrence=$((recurrence + count))
    escape=$((escape + escaped))
    after=$((after + 1))
  done

  body="${body}$(printf '%4d  %8d  %4d  %4d  %-22s %s' \
    "$recurrence" "$escape" "$total" "$after" "$tag" "$intervention")
"
done
printf '%s' "$body"
}

# --unused: 語彙表にあるのに記録へ 1 件も出ていない分類。
if [ "${1:-}" = "--unused" ]; then
  printf '%s\n' "記録に 1 件も出ていない分類（語彙表: ${vocabulary}）"
  unused_tags | sed 's/^/  /'
  exit 0
fi

# --shrink: 縮める側の条件を数字で出す（harness-growth の SKILL.md「Step 3」）。
#
# 増やす側は count.sh が数字を出して 2a / 2b / 2c が分岐するのに対し、縮める側は
# 条件が満たされているかを目で確かめる形だったため、一度も発火していなかった
# （rules/ と AGENTS.md が正味マイナスになったコミットは全履歴で 0 件）。
# 同じように数字で出して、判断の入力を揃える。
if [ "${1:-}" = "--shrink" ]; then
  printf '%s\n\n' "縮める候補（harness-growth の SKILL.md「Step 3」）"

  # 効いている対策は、その層より下に同内容の記述を二重に持つ理由が無い。
  # 層=rules は最下層で「下の層」が無いので、削るのではなく実例・経緯を判例へ落とせるかを見る。
  # 見送り回数は「- 見送り: `<分類>` at pr-<番号>」の行（harness-growth だけが書く）から数える。
  # 見送りを PR 本文にしか書かないと、同じ候補を何回見送ったかが数えられない。
  printf '%s\n' "1. 効いている対策（以降 10 本以上・再発 0）— その対策より下の層の記述を削る"
  printf '%s\n' "   ※ 層=rules は下の層が無い。実例・経緯を判例へ落とせるかを見る"
  proven="$(summary_rows | awk '$1 == 0 && $4 >= 10 {print $5, $4, $6}' \
    | while read -r tag after intervention; do
      deferrals="$( { grep -hoE "^- 見送り: \`$tag\` at pr-[0-9]+" pr-*.md || true; } | wc -l | tr -d ' ')"
      note=""
      [ "$deferrals" -gt 0 ] && note="  見送り=${deferrals}回"
      printf '     %-28s 以降=%-4s 最終介入=%s%s\n' "$tag" "$after" "$intervention" "$note"
    done)"
  printf '%s\n\n' "${proven:-     該当なし}"

  # 足したばかりの語彙は必ずここに出るので、割った回の分を除いてから読む。
  printf '%s\n' "2. 未使用の分類 — 対応する rules/ の節を縮める候補"
  printf '%s\n' "   ※ 2c / 逃し弁で語彙を割った回に足した分は必ずここに出る。除いてから読む"
  unused="$(unused_tags | sed 's/^/     /')"
  printf '%s\n\n' "${unused:-     該当なし}"

  printf '%s\n' "3. 常時ロードの行数"
  loaded="$(cd ../.. && wc -l AGENTS.md rules/*.md | tail -1 | awk '{print $1}')"
  growth="$(wc -l < ../../.claude/skills/harness-growth/SKILL.md)"
  printf '     %-34s %4s / %s 行%s\n' "AGENTS.md + rules/" "$loaded" 900 \
    "$([ "$loaded" -gt 900 ] && printf ' ← 超過' || true)"
  printf '     %-34s %4s / %s 行%s\n\n' "harness-growth/SKILL.md" "$growth" 200 \
    "$([ "$growth" -gt 200 ] && printf ' ← 超過' || true)"

  # 装置(スキル・エージェント)の間引き候補。記録の「## 発火」の行から数える。
  # フックはここでは数えない(予防装置は発火 0 が「効いている」でありうるため。
  # フックの重複は節 1 と層上げの側で削る)。プラグインのスキルは発火した分しか
  # 表に出ない(リポジトリからは一覧を数えられない)。
  printf '%s\n' "4. 装置の間引き候補（発火を計測できた記録 10 本から判断）"
  measured=0
  for record in pr-*.md; do
    grep -qE '^- 発火: (`|無し)' "$record" && measured=$((measured + 1))
  done
  printf '   %s\n' "発火を計測できた記録: ${measured} 本"
  if [ "$measured" -lt 10 ]; then
    printf '   %s\n' "(10 本未満のため候補は出さない)"
    exit 0
  fi
  printf '%s\n' "   計測した記録での発火回数:"
  grep -hoE '^- 発火: `[^`]+` [0-9]+回' pr-*.md \
    | sed 's/^- 発火: `\([^`]*\)` \([0-9]*\)回/\1 \2/' \
    | awk '{sum[$1] += $2} END {for (name in sum) printf "     %-34s %4d 回\n", name, sum[name]}' \
    | sort -k2 -rn
  printf '%s\n' "   計測した記録で発火 0 のリポジトリ内装置 — 退役候補:"
  for device in ../../.claude/skills/*/ ../../.claude/agents/*.md; do
    name="$(basename "$device" .md)"
    grep -qE "^- 発火: \`$name\`" pr-*.md || printf '     %s\n' "$name"
  done
  exit 0
fi

printf '%s\n' "再発  すり抜け  通算  以降  分類                   最終介入"
# 再発が同数なら、すり抜けが出ている分類を上に出す（効いていない側が分かっているため）
summary_rows | sort -k1,1rn -k2,2rn
