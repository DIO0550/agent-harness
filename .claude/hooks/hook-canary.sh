#!/usr/bin/env bash
#
# フックのカナリア: `echo hook-canary` を必ず deny する PreToolUse フック。
#
# Claude Code のフックは発火しない実行環境があり、しかも**フェイルオープンかつ
# サイレント**なので、「通った」のか「検査されなかった」のかが区別できない
# (.claude/hooks/README.md「強制力の序列」)。意図的に必ず止まるコマンドを 1 つ置く
# ことで、silent を detected に変える。
#
# **外部コマンドに依存しない。** PreToolUse は exit 2 以外の異常終了を「非ブロックの
# エラー」として素通りさせるので、jq の無い環境ではフックが exit 127 で終わって
# 配線が読まれていない場合とまったく同じ見え方になる。カナリア自身がそれで落ちると
# 「フックは動いていたのに不発と報告する」ことになり、検出の意味が消える。
# そのため判定・分割・出力は bash の組み込みだけで完結させ、jq は在れば使う程度に留める。
#
# 使い方: push の前に `echo hook-canary` を実行する。deny されれば発火している。
# 通ってしまったときの読み方は .claude/hooks/README.md「発火しているかを確かめる
# (カナリア)」にある(通った = 不発、ではない)。
set -uo pipefail

input="$(cat)"

# `.tool_input.command` を取り出す。jq が無い / 失敗した場合は生の JSON から読む。
# 後者は最初の `"` までを値と見るうえ、JSON のエスケープを戻さない。そのため
# 引用符を含むコマンドは値が途中で切れ、改行は `\n` の 2 文字のままなので改行区切りは
# 効かない。取りこぼす側へ倒して誤検知を避ける。
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

# 走査する前に 2 つ落とす。下の走査は 1 文字ずつ進むのでコマンド長の二乗で伸び、
# 31KB で 5 秒・127KB で 90 秒かかる(実測)。このフックは全 Bash 実行に乗るので、
# フックのタイムアウトを超えれば素通りし、長いコマンドほど効かなくなる。
#
# 1 つ目は綴りの有無。一致する断片は必ずこの綴りを含むので判定は変わらない。
# 2 つ目は長さの上限で、こちらは**意図した取りこぼし**。記録ファイルをヒアドキュメントで
# 書く形は数十 KB あり、しかも記録は `hook-canary` に言及するので 1 つ目を通り抜ける。
# 上限の 2048 字は走査 100ms 相当で、カナリアを連ねた形(長くても数百字)には届く。
[[ "$command_text" == *hook-canary* ]] || exit 0
scan_limit=2048
[ "${#command_text}" -le "$scan_limit" ] || exit 0

# 対象は「カナリアを実行する断片」だけに絞る。`hook-canary` を含むだけで止めると、
# この名前に言及するコミットメッセージや grep まで deny される
# (README「誤検知で止まるフックは、エスケープハッチを足す運用を招いて全体が信用されなくなる」)。
canary_pattern="^[[:space:]]*echo[[:space:]]+(hook-canary|\"hook-canary\"|'hook-canary')[[:space:]]*$"

matched=0
segment=""
in_single=0
in_double=0
index=0

# 区切りで切り終えた断片をカナリアと照合し、次の断片へ移る。
match_segment() {
  if [[ "$segment" =~ $canary_pattern ]]; then
    matched=1
  fi
  segment=""
}

# 引用符の外にある区切りでコマンドを切る。コマンド全体の完全一致で見ていた頃は
# `echo hook-canary && echo done` を取りこぼし、フックが発火しているセッションを
# 不発として報告していた(実測)。
#
# 区切りに入れるのは `&&` `||` `;` 改行だけ。基準は**その綴りでカナリアを連ねる形が
# 実在するか**で、`|` `&` や部分シェルは利得が無いまま誤検知だけが増える
# (`| echo hook-canary |` という表の行で止まる)。改行は実在する側なので残すが、
# 代わりに `echo hook-canary` だけの行をヒアドキュメントで書き出すと止まる。
# 既存の `block-npx.sh` / `pre-push-lint.sh` は境界文字クラスで拾うので `|` `&` の扱いが
# 逆になる。断片の完全一致が要るのはカナリアだけなので寄せていない。
#
# 引用符は開閉を状態として追う。個数の偶奇で内側かを決めると
# `echo "don't" && echo hook-canary` の `'` を開き引用符と読んでカナリアを取りこぼし、
# `git commit -m "don't && echo hook-canary && ok"` を誤って deny する(どちらも実測)。
while [ "$index" -lt "${#command_text}" ]; do
  character="${command_text:index:1}"
  lookahead="${command_text:index:2}"
  index=$(( index + 1 ))

  # バックスラッシュは次の 1 文字を引用符ではなくす。解釈しないと
  # `git commit -m "a\" && echo hook-canary && b"` を誤って deny する(実測)。
  if [ "$character" = "\\" ]; then
    segment+="$lookahead"
    index=$(( index + 1 ))
    continue
  fi

  if [ "$character" = "'" ] && [ "$in_double" -eq 0 ]; then
    in_single=$(( 1 - in_single ))
    segment+="$character"
    continue
  fi
  if [ "$character" = '"' ] && [ "$in_single" -eq 0 ]; then
    in_double=$(( 1 - in_double ))
    segment+="$character"
    continue
  fi

  inside_quotes=$(( in_single + in_double ))
  if [ "$inside_quotes" -ne 0 ]; then
    segment+="$character"
    continue
  fi

  if [ "$lookahead" = "&&" ] || [ "$lookahead" = "||" ]; then
    index=$(( index + 1 ))
    match_segment
    continue
  fi
  if [ "$character" = ";" ] || [ "$character" = $'\n' ]; then
    match_segment
    continue
  fi

  segment+="$character"
done
match_segment

[ "$matched" -eq 1 ] || exit 0

# 他のフックは jq / python3 を使う。カナリアが通っても、それらが無ければ同じ
# フェイルオープンで黙って素通りするので、欠けているものをここで名指しする。
missing=""
command -v jq >/dev/null 2>&1 || missing="${missing} jq"
command -v python3 >/dev/null 2>&1 || missing="${missing} python3"

reason="カナリアです。このセッションでは Claude Code のフックが発火しています（PreToolUse / PostToolUse とも配線どおりに動く前提で進めてよい）。カナリア自体を実行し直す必要はありません。同じコマンドに他の検査を連ねていた場合、それらは 1 つも走っていないので、カナリアを外して実行し直すこと。"
if [ -n "$missing" ]; then
  reason="${reason} なお、他のフックが使う次のコマンドがこの環境にありません:${missing}。これらを使うフックは異常終了して素通りするため、push 前の検査は git hooks / CI に頼ること。"
fi

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
