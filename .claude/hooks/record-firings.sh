#!/usr/bin/env bash
#
# スキル・サブエージェントの発火をセッション別のログへ書き出す
# (SessionStart / PostToolUse: Skill・Task・Agent 兼用)。
#
# 対応する規約: harness-record スキル Step 1「スキル・サブエージェントの発火」。
# 記録の材料のうち発火だけは記憶(自己申告)からしか取れなかった。「すり抜け」列は
# サブエージェントが見落としたことしか言えず、そもそも起動していなかったのかを
# 区別できない(subagent-control が未介入のまま再発 9 件)。発火の瞬間に機械で
# 書き出せば、harness-record が最後にログを読むだけで済む。
# 同じログを block-parent-session-edit.sh も読み、implementation-flow の中かどうかを決める
# (ログのパスはあちらも同じ綴りで組み立てる。揃っていることは lib/parent-session-edit-cases.sh が守る)。
#
# **SessionStart でセッション見出しを先に書く。** フックはフェイルオープンかつ
# サイレント(.claude/hooks/README.md「強制力の序列」)なので、ログが空のとき
# 「起動しなかった」と「フックが発火しなかった」を区別できない。エージェントは、見出しが
# あって発火行が無いときに「本当に起動していない」と言える。スキルは、Skill ツールを通らない
# 起動だと発火行が書かれないので言い切れない(.claude/hooks/README.md「カバー範囲と残る穴」)。
# 見出しが無いログは計測対象外として扱う(読み方は harness-record スキル)。
#
# **外部コマンドに依存しない。** jq の無い環境で黙って落ちると見出しも消え、
# そのセッションは計測対象外になり、ログを読む block-parent-session-edit.sh も
# 素通りになる。jq があるだけで精度が変わる状態を作らないため、判定は bash の組み込みだけで完結させる
# (session-url-notice.sh と同じ理由)。
#
# リポジトリ内へログを置かないのは、作業ツリーが汚れて git status・pre-push 検査の
# ノイズになる。ログはセッションと同じ寿命でよい(別セッションからの復元は
# harness-record が「不明」と書く既存の扱いのまま)ので tmp に置く。
set -uo pipefail

input="$(cat)"

# 値の取り出しは生の JSON への正規表現で行う(最初の一致を採る)。
# PostToolUse の tool_input は tool_response より前に来るので、応答本文に
# 同名のキー文字列が含まれていても取り違えない。
extract() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$input" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
}

session_id="$(extract session_id)"
log_file="${TMPDIR:-/tmp}/agent-harness-firings-${session_id:-unknown}.log"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

event_name="$(extract hook_event_name)"
if [ "$event_name" = "SessionStart" ]; then
  printf '%s\tsession\t%s\n' "$timestamp" "${session_id:-unknown}" >> "$log_file" 2>/dev/null || true
  exit 0
fi

tool_name="$(extract tool_name)"
case "$tool_name" in
  Skill)
    fired="$(extract skill)"
    kind="skill"
    ;;
  Task | Agent)
    # サブエージェントの起動。ツール名は CLI では Task、リモート実行環境では Agent
    fired="$(extract subagent_type)"
    kind="agent"
    ;;
  *)
    exit 0
    ;;
esac

[ -n "$fired" ] || exit 0
printf '%s\t%s\t%s\n' "$timestamp" "$kind" "$fired" >> "$log_file" 2>/dev/null || true
exit 0
