# .claude/hooks — セッション中に効くフック

Claude Code のセッション中に走るフックスクリプトの置き場。移植元（design-composer）から、
**言語・スタックに依らないものだけ**を持ってきている。

## 何を置いているか

| スクリプト | イベント | 内容 |
| --- | --- | --- |
| `hook-canary.sh` | `PreToolUse` (Bash) | **カナリア**。`echo hook-canary` を必ず deny する。フックが発火する環境かを確かめるためだけのもの |
| `session-url-notice.sh` | `SessionStart` | **セッション URL の提示**。Issue へ残すよう促す(AGENTS.md「Issue に紐づいて起動したら、セッションの URL を Issue に残す」) |
| `record-firings.sh` | `SessionStart` / `PostToolUse` (Skill/Task/Agent) | **スキル・サブエージェントの発火ログ**。`harness-record` の「発火」欄の材料 |
| `post-merge-review.sh` | `PostToolUse` (Bash / merge) | **マージ後の 3 つ**を提示する(Issue への追記 / 続きの Issue / `harness-record`) |
| `track-verification-agent-activity.sh` | `PreToolUse` + `PostToolUse` (Task/Agent) | `plan-reviewer` / `implementation-reviewer` が実行中かをマーカーで記録する |
| `block-git-during-verification-agent.sh` | `PreToolUse` (Bash) | 上のマーカーがある間、`git add` / `commit` / `push` を拒否する |

**移植元の検査フック（lint / typecheck / doc コメント / テスト規約 / import 規約 / 判別子の
直読み / lint 抑制の禁止）は持ってきていない。** どれも TypeScript のソースと pnpm を
前提にしていて、このリポジトリには対象が無い。ソースが入ったら、その言語の検査を
**まず層 1・層 2 へ**置き（下の「強制力の序列」）、ここにはその共有版を足す。

## 配線

[`.claude/settings.json`](../settings.json) の `hooks` から参照。パスは `$CLAUDE_PROJECT_DIR` 基準。

`lib/` はフック本体から読む共有部品と、フックの判定を手で確かめるための表の置き場。
`settings.json` からは参照しない。

| ファイル | 使う側 | 内容 |
| --- | --- | --- |
| `lib/canary-cases.sh` | 手で実行する（「動作確認」） | `hook-canary.sh` へ判定表を流し、deny / pass / miss が期待どおりかを報告する。食い違いがあれば exit 1 |

## 強制力の序列 — フックが発火しない実行環境がある

リモート実行環境（Claude Code on the web など）では `.claude/settings.json` の配線が
読み込まれないことがある。**フェイルオープンかつサイレント**なので、通ったのか
検査されなかったのかを区別できない。したがって **Claude Code のフックを enforcement の
最上位として数えることはできない**。序列は次のとおり。

| # | 層 | 効く範囲 | タイミング | 置き場所 |
| --- | --- | --- | --- | --- |
| 1 | CI | 無条件 | push の後 | `.github/workflows/` |
| 2 | git hooks | クライアント非依存 | push の前 | [`harness/githooks/`](../../harness/githooks/README.md) |
| 3 | Claude Code hooks | CLI 起動セッションのみ | 編集・コマンドの直前 | ここ |
| 4 | skill / rules | お願いベース | 読まれたとき | `.claude/skills/` / `rules/` |

**push 前検査の enforcement は git hooks が担う。** `harness-growth` が「層 1(`hook`)に置く」と
判断したときは、`harness/githooks/` か CI のどちらかに置き、Claude Code 側はその共有版として足す。

### カバー範囲と残る穴

git hooks へ移せるのは **push 前に痕跡が残る検査だけ**。いまここにあるものは、どれも
git のイベントに対応物が無い。

| 効かなくなるもの | CI の代替 |
| --- | --- |
| `block-git-during-verification-agent.sh`(セッション中の行為の禁止) | **無し**。この競合はセッションの実行タイミングだけが原因で、コミット後のリポジトリの状態には痕跡が残らない |
| `session-url-notice.sh`(セッション URL の提示) | **無し**。URL はセッションの中にしか無く、残す先も GitHub のコメントなので、push の時点で痕跡が残らない。落ちても穴は開かない(規約が AGENTS.md に残り、失っても情報が 1 つ足りないだけでガードは破れない) |
| `record-firings.sh`(発火ログ) | **無し**。ただし失敗しても穴は開かない(セッション見出しが無いログは `harness-record` が「計測対象外」と書く設計で、誤ったゼロにはならない)。カナリアと同じ「失敗してもガードが破れない」検出系 |
| `post-merge-review.sh`(マージ後の提示) | **無し**。提示するだけでブロックしないので、落ちても穴は開かない |

### 「代替不能」が実際に不発だったとき、手動で肩代わりする

`block-git-during-verification-agent.sh` は上の表のとおり CI の代替が**無し**。
カナリア(次項)で不発が確定したら、「記録のみ」で終わらせず、そのフックが止めるはずだった
操作を手動で確認する(`分類: hook-environment-guard-miss`)。

| 不発したフック | 手動で確認すること |
| --- | --- |
| `block-git-during-verification-agent.sh` | 検証エージェント実行中に作られたコミットの diff を、そのエージェントが直したはずの内容とだけ照合する(意図しない変更が紛れていないか) |

`session-url-notice.sh` の不発は対応不要(上の表のとおり、失っても情報が 1 つ足りないだけで
ガードは破れない)。

### 発火しているかを確かめる(カナリア)

`hook-canary.sh` は `echo hook-canary` を必ず deny する。push の前にこれを 1 度実行すると、
silent だったフックの不発が detected に変わる。

**通った = 不発、ではない。** カナリアは自分の取りこぼしと本当の不発を区別できないので、
通ったときは PreToolUse の痕跡を見て決める。

| カナリア | 検証エージェントのマーカー | 発火ログの見出し | 読み方 |
| --- | --- | --- | --- |
| deny された | — | — | **発火している** |
| 通った | ある | — | **カナリアの取りこぼし**。Task/Agent のフックは発火している(不発と書かない) |
| 通った | 無い | ある | SessionStart は発火している。PreToolUse は不明 |
| 通った | 無い | 無い | **本当に不発**(`分類: hook-environment`) |

```bash
ls -d "${TMPDIR:-/tmp}/agent-harness-verification-agents-${CLAUDE_CODE_SESSION_ID:-}"
grep -c $'\tsession\t' "${TMPDIR:-/tmp}/agent-harness-firings-${CLAUDE_CODE_SESSION_ID:-}.log"
```

**マーカーは `plan-reviewer` / `implementation-reviewer` を 1 度でも通した後にしか現れない。**
`track-verification-agent-activity.sh` がこの 2 つの Task/Agent でしか作らないため、着手直後に
カナリアを実行した回は 2 行目に当たらず、マーカー無しの枝へ落ちる。

マーカーが言えるのは **`Task|Agent` の PreToolUse か PostToolUse のどちらかが発火した**まで。
`mkdir -p` が `hook_event_name` の分岐より手前にあるので、PostToolUse だけでも作られる。

見出しのほうは `record-firings.sh` が **SessionStart** で書く。ログファイル自体は PostToolUse の
追記でも作られるので、**ファイルの有無ではなく見出し行を数える**。

`CLAUDE_CODE_SESSION_ID` が無い環境では、`…-*` の glob で出たものが**別セッションの残骸**で
ないかを見出しの時刻で確かめる(tmp はコンテナに残る)。

**同じ「リモート実行環境」でも発火する場合としない場合がある**ので、不発を前提に設計しつつ、
発火する側を捨てない(層 3 に置く価値はある)。

**カナリアだけは外部コマンドに依存しない。** PreToolUse は exit 2 以外の異常終了を
「非ブロックのエラー」として素通りさせるので、`jq` の無い環境では他のフックと同様に
カナリアも exit 127 で終わり、**配線が読まれていない場合とまったく同じ見え方**になる。
それでは「フックは動いていたのに不発と報告する」ことになり、検出そのものが信用できない。
判定も出力も bash の組み込みだけで行い、`jq` は在れば使う程度に留めている。

deny のメッセージは、`jq` / `python3` が欠けていればその名前も併せて出す。**カナリアが
通っても、これらを使う他のフックは同じフェイルオープンで黙って素通りする**ため。

検出そのものは指示ベースだが、**失敗しても穴は開かない**。ゲートは git hooks と CI にあり、
カナリアはそれが効いているかを知るためだけのもの。指示ベースに置いてよいのは、
失敗してもガードが破れない検出系だけ。

## 例外(エスケープハッチ)

- `post-merge-review.sh` はマージを**ブロックしない**(`additionalContext` を返すだけ)。マージは人の判断で行われるので、記録が無いことを理由に止めても記録の質は上がらないため
  - 検知対象は `mcp__github__merge_pull_request` と `gh pr merge` のみ。素の `git merge` は見ない(ベースブランチの取り込みで日常的に走るため、拾うと誤発火のほうが多くなる)
- `block-git-during-verification-agent.sh` は、30 分より古いマーカーを無視する。実行が異常終了してマーカーを消し損ねたときに、恒久的にブロックし続けないため(フェイルオープン側へ倒す)
- `track-verification-agent-activity.sh` が見るのは `plan-reviewer` / `implementation-reviewer` だけ。読み取り専用のサブエージェントは作業ツリーを書き換えないので、対象を広げても実害が防げないまま誤検知だけが増える。**誤検知で止まるフックは、エスケープハッチを足す運用を招いて全体が信用されなくなる**

## 動作確認

```bash
# カナリアの判定表（deny / pass / miss が期待どおりか）
bash .claude/hooks/lib/canary-cases.sh

# 個々のフックへ JSON を直接流す
echo '{"tool_input":{"command":"echo hook-canary"}}' | bash .claude/hooks/hook-canary.sh
echo '{"hook_event_name":"SessionStart","session_id":"x"}' | bash .claude/hooks/session-url-notice.sh
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' | bash .claude/hooks/post-merge-review.sh
```

## 関連するスキル

- `.claude/skills/implementation-flow/` — フェーズ 7 で push の前にカナリアを実行する
- `.claude/skills/harness-record/` — `record-firings.sh` のログを「発火」欄の材料として読む
- `.claude/skills/harness-growth/` — どの層へ置くかを決める(層の序列は上の表)
