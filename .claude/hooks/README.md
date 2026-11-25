# .claude/hooks — セッション中に効くフック

Claude Code のセッション中に走るフックスクリプトの置き場。移植元（design-composer）から、
**言語・スタックに依らないものだけ**を持ってきている。git 操作の 3 本（`block-git-add-all.sh` /
`block-commit-md-heading.sh` / `block-protected-branch-edit.sh`）は、移植元が
[d-market-git](https://github.com/DIO0550/d-market-git) の git-workflow-plugin（`1135a0d`）から取り込み、
止めすぎる形を直したもの。

## 何を置いているか

| スクリプト | イベント | 内容 |
| --- | --- | --- |
| `hook-canary.sh` | `PreToolUse` (Bash) | **カナリア**。`echo hook-canary` を必ず deny する。フックが発火する環境かを確かめるためだけのもの |
| `session-url-notice.sh` | `SessionStart` | **セッション URL の提示**。Issue へ残すよう促し、assignee は付けさせない(rules/process.md「Issue に紐づいて起動したら、セッションの URL を Issue に残す」) |
| `record-firings.sh` | `SessionStart` / `PostToolUse` (Skill/Task/Agent) | **スキル・サブエージェントの発火ログ**。`harness-record` の「発火」欄の材料。`block-parent-session-edit.sh` も implementation-flow の中かどうかを決めるために読む |
| `post-merge-review.sh` | `PostToolUse` (Bash / merge) | **マージ後の 3 つ**を提示する(Issue への追記 / 続きの Issue / `harness-record`) |
| `track-verification-agent-activity.sh` | `PreToolUse` + `PostToolUse` (Task/Agent) | **作業ツリーを書き換えるサブエージェントの実行中フラグ**。`plan-reviewer` / `implementation-reviewer` / `implementer` の開始・終了をセッション別・種類別のマーカーで数える。この 3 つの起動のうち、**`run_in_background: true` を明示したものは拒否する**(背景で起動すると印が起動の直後に消えるため。フックの冒頭) |
| `block-git-during-verification-agent.sh` | `PreToolUse` (Bash) | 上のマーカーがある間、`git add` / `commit` / `push` を拒否する。古いマーカーは無視する(種類ごとに有効期間が違う。値と理由はフックの本文)。拒否文に印のディレクトリを出す |
| `block-parent-session-edit.sh` | `PreToolUse` (Edit/Write) | **implementation-flow の中の親セッションの編集を拒否**(`implementation-flow`「役割の分担」)。入力に `agent_id` の無い(親の)Edit / Write で、リポジトリの中のファイルを指し、発火ログの最後の区切りが flow の中なら deny する。区切りになる起動と通す入力はフックの冒頭 |
| `block-run-without-install.sh` | `PreToolUse` (Bash) | **インストールせずに取ってきて実行するコマンドの禁止**。`npx` / `bunx` / `uvx` / `pnpm dlx` / `yarn dlx` / `pipx run` / `npm exec` / `npm create` / `pnpm create` / `yarn create`、および引数がリモートのときの `go run` / `deno run` を拒否する |
| `block-issue-without-flow-kind.sh` | `PreToolUse` (Bash / `mcp__github__issue_write`) | **作業の種類を決めていない Issue の作成を拒否**(`implementation-flow` フェーズ 1「種類の確定」の 4)。作成とみなす形・通す条件・行の書式は `lib/issue-flow-kind-violations.py` の docstring と定数が持つ。python3 が使えなければ通し、検出器が異常終了したら deny する |
| `block-git-add-all.sh` | `PreToolUse` (Bash) | **一括ステージングの禁止**(規範は `commit` スキル「禁止事項」)。`git add -A` / `--all` / `.` / `-a` を拒否する。ヒアドキュメントの本文と引用符の中(コマンド置換を含まないもの)は見ない |
| `block-commit-md-heading.sh` | `PreToolUse` (Bash) | **コミット本文の行頭 `#` の禁止**(規範は `commit` スキルの本文の「書式」)。引用符の外に `git commit` があれば、ヒアドキュメントの本文(無ければコマンド全体)の行頭 `#` を拒否する |
| `block-protected-branch-edit.sh` | `PreToolUse` (Edit/Write/MultiEdit/NotebookEdit) | **保護ブランチでの編集の禁止**。フックの作業ディレクトリのブランチが保護ブランチ(一覧はフックの `protected_branches`)なら拒否する。入力は読まず、どのツールで止めるかは matcher が決める |

**移植元の検査フック（lint / typecheck / doc コメント / テスト規約 / import 規約 / 判別子の
直読み / lint 抑制の禁止）は持ってきていない。** どれも TypeScript のソースと pnpm を
前提にしていて、このリポジトリには対象が無い。ソースが入ったら、その言語の検査を
**まず層 1・層 2 へ**置き（下の「強制力の序列」）、ここにはその共有版を足す。

移植元の `block-npx.sh`（`npx` / `pnpm dlx` の禁止）は上の理由に当てはまらない。止めているのは
パッケージマネージャの選択ではなく**取ってきて即実行すること**で、対象はこのリポジトリにもある。
`block-run-without-install.sh` がその役で、スタックを決めていないぶん対象を広げてある。

## 配線

[`.claude/settings.json`](../settings.json) の `hooks` から参照。パスは `${CLAUDE_PROJECT_DIR:-.}` 基準。

`lib/` はフック本体から読む共有部品と、フックの判定を手で確かめるための表の置き場。
`settings.json` からは参照しない。

| ファイル | 使う側 | 内容 |
| --- | --- | --- |
| `lib/case-table.sh` | 下の `*-cases.sh` がすべて `source` する | 判定表の走行部。フックへ JSON を流し、`permissionDecision` が `deny` か・JSON として妥当か・フックが 0 で終わるかまで見る。**判定表は共有してよいが、フック本体は共有しない**（表は `source` の失敗がその場で落ちて分かるのに対し、フックは PreToolUse のフェイルオープンに吸われて黙って素通りするため） |
| `lib/canary-cases.sh` | 手で実行する（「動作確認」） | `hook-canary.sh` へ判定表を流す |
| `lib/run-without-install-cases.sh` | 手で実行する（「動作確認」） | `block-run-without-install.sh` へ判定表を流す。あわせて jq の無い経路（PATH を絞って狙って踏む）と、`PreToolUse` / `Bash` の枝から呼ばれていることも検算する（表は JSON を実物のフックへ直接流すので、配線が切れていても表だけは全件通る） |
| `lib/verification-agent-cases.sh` | `harness/githooks/pre-push`（「動作確認」でも手で走らせる） | `track-verification-agent-activity.sh` と `block-git-during-verification-agent.sh` へ Task/Agent と git の呼び出しを順に流し、起動の拒否と git 操作の拒否が期待どおりかを報告する。確かめる項目は判定表の冒頭コメントと各ケースの名前が持つ |
| `lib/parent-session-edit-cases.sh` | `harness/githooks/pre-push`(「動作確認」でも手で走らせる) | 本物の `record-firings.sh` に発火ログを書かせてから `block-parent-session-edit.sh` へ Edit / Write の呼び出しを流し、親の編集の拒否と素通りが期待どおりかを報告する。2 本は発火ログのパスを各自で組み立てるので、その綴りが揃っていることもここで守る。確かめる項目は各ケースの名前が持つ |
| `lib/issue-flow-kind-violations.py` | `block-issue-without-flow-kind.sh` | Issue を作る呼び出しが作業の種類を決めているかを見る検出器。Bash は bash と同じ規則で字句に分けてから読む。種別の一覧と意味、行の書式は検出器の docstring と定数が持つ |
| `lib/issue-flow-kind-cases.sh` | `harness/githooks/pre-push`(「動作確認」でも手で走らせる) | 上の検出器とフックの判定表。検出器の表は python3 を 1 回だけ起動して検出器を import し、ケースごとに判定の関数を呼ぶ。フックの表はフックを一時ディレクトリへ写し、検出器を CLI として走らせて deny / pass と拒否文の並びを確かめる。検出器の種別と docstring の一覧の一致も見る |
| `lib/issue-flow-kind-real-gh-cases.sh` | 手で実行する(「動作確認」) | 検出器が通す作成を、実物の bash と gh で走らせる判定表。入力は `issue-flow-kind-cases.sh` の検出器の表(`miss` 以外の `bash` 形)と、送るものを変える指定を 1 つ足した形。gh は手元のダミーのサーバーへ向け、検出器が pass なのに自リポジトリへ `flow:*` も宣言の行も無い作成を送ったら NG。gh と openssl が要り、1 回 14 秒ほどかかる(実測)ので push 前検査には入れない。検出器か `issue-flow-kind-cases.sh` を触ったら走らせる |
| `lib/issue-flow-kind-fixtures.sh` | 上の判定表 2 本 | 2 本が共有する前提(自リポジトリの origin・提案の行・本文のファイルを置く `place_files`) |
| `lib/command-literals.sh` | `block-git-add-all.sh` / `block-commit-md-heading.sh` が `source` する | コマンド文字列から、すべてのヒアドキュメントの本文を出す `heredoc_bodies` と、本文と引用符の中を除いて 1 行にする `command_line_outside_literals`。awk(POSIX の機能だけ)と sed で近似し、字句解析は持たない。**フック本体の部品を共有しない決まりの例外**(理由はファイルの冒頭) |
| `lib/git-add-all-cases.sh` | `harness/githooks/pre-push`(「動作確認」でも手で走らせる) | `block-git-add-all.sh` の判定表(deny / pass / miss) |
| `lib/commit-md-heading-cases.sh` | `harness/githooks/pre-push`(「動作確認」でも手で走らせる) | `block-commit-md-heading.sh` の判定表(deny / pass / miss / overdeny) |
| `lib/protected-branch-edit-cases.sh` | `harness/githooks/pre-push`(「動作確認」でも手で走らせる) | `block-protected-branch-edit.sh` の判定表。一時リポジトリでブランチ・detached HEAD・作業ディレクトリを変えて deny / pass / miss / overdeny を確かめる |

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
| `block-run-without-install.sh`(セッション中の行為の禁止) | **無し**。取ってきて即実行したことはリポジトリに何も残さない(依存ファイルにもロックファイルにも書かれない)ので、push の時点では検査する対象が無い |
| `session-url-notice.sh`(セッション URL の提示) | **無し**。URL はセッションの中にしか無く、残す先も GitHub のコメントなので、push の時点で痕跡が残らない。落ちても穴は開かない(規約が rules/process.md に残り、失っても情報が 1 つ足りないだけでガードは破れない) |
| `record-firings.sh`(発火ログ) | **無し**。`harness-record` の計測は失敗しても穴は開かない(セッション見出しが無いログは `harness-record` が「計測対象外」と書く設計で、フック不発が誤ったゼロにはならない。ただしスキルは、Skill ツールを通らない起動だと見出しがあっても発火行が書かれない → 下の「区切りがログに残らない起動」)。一方、同じログを読む `block-parent-session-edit.sh` は、ログに implementation-flow の区切りが無ければ素通りするので、こちらが落ちると親の編集の拒否も効かなくなる |
| `block-parent-session-edit.sh`(セッション中の行為の禁止) | **無し**。誰が編集したか(親かサブエージェントか)はコミットに残らない。発火する環境でも残る穴は下 |
| `post-merge-review.sh`(マージ後の提示) | **無し**。提示するだけでブロックしないので、落ちても穴は開かない |
| `block-issue-without-flow-kind.sh`(セッション中の行為の禁止) | **無し**。Issue の作成は push と関係なく起き、リポジトリに痕跡が残らない |
| `block-git-add-all.sh`(セッション中の行為の禁止) | **無し**。どのコマンドでステージしたかはコミットに残らない |
| `block-commit-md-heading.sh`(コミット本文の検査) | **無し**。ただし本文はコミットに残るので、push 前・CI へ移せる(まだ移していない) |
| `block-protected-branch-edit.sh`(セッション中の行為の禁止) | **無し**。取り込む側が GitHub のブランチ保護を掛けていれば、push の時点では止まる |

`block-parent-session-edit.sh` が発火する環境でも残る穴は 5 つ。

| 残る穴 | 内容 |
| --- | --- |
| 区切りがログに残らない起動 | Skill ツールを通らない起動は、スキルの起動がログに残らない(`skill` の行が書かれない)。利用者が打ったスラッシュコマンドと、手順を読んで implementation-flow を進める回がこれに当たる。移植元の実測は `/implementation-flow` を打った回だけで、`skill` の行が書かれず、`planner` を起動する前の親の Write は通り、起動した後は deny された([design-composer #1277 の実測](https://github.com/DIO0550/design-composer/issues/1277#issuecomment-6708032746))。他のスラッシュコマンド・手順を読んで進める回は**推論**。その推論では、implementation-flow の区切りの後に `/harness-record` / `/harness-growth` を打った回は、前の区切りが残ったまま拒否が続く(抜け方は「例外」) |
| matcher の外の道具 | `NotebookEdit` / `MultiEdit` は matcher(`Edit\|Write`)に入っていないので見ない。入力のキーが違う(`NotebookEdit` は `notebook_path`) |
| Bash 経由の書き換え | `sed -i` やリダイレクトでの書き換えは見ない。コマンド文字列から書き換え先のパスを確定できず、このフックでは判定できない |
| 正規化しないパス | `..` を挟んだ絶対パスや symlink 越しのパスは、綴りがルートと前方一致しないとリポジトリの外として通る(正規化はしない) |
| 発火しない起動の形 | フックが発火しない起動の形(「発火しているかを確かめる」)では効かない |

`block-issue-without-flow-kind.sh` が発火する環境でも残る穴は次のとおり。取りこぼす形は判定表
`lib/issue-flow-kind-cases.sh` が `miss` で、止めすぎる形・読む位置を誤る形の多くは `deny` で固定している。
検出器が通す形が gh と bash の実際の送信と食い違っていないかは `lib/issue-flow-kind-real-gh-cases.sh` が
実物で見る(止めすぎる向きは見ない)。

| 残る穴 | 内容 |
| --- | --- |
| 取りこぼす | `bash -c` / `sh -c` / `eval` / `xargs` / スクリプトの中 / `gh alias` / GraphQL の `createIssue` / `curl` / GitHub の UI(Issue テンプレートを含む)からの作成は見ない。入れ子のコマンドを解くと字句解析が二重になり、回避を防ぐことは目的にしない。前置きの後ろにオプションや名前が付く形(`time -p` / `command -p` / `exec -a NAME` / `env -i` / 名前付きの `coproc NAME { … }`)の後ろも読まない |
| 止めすぎる | `export GH_REPO` を先に実行する形と `cd <他リポジトリ>` の後の作成は、1 回の入力から作成先が決まらないので自リポジトリとして止める。展開を含むラベル・`-R`・`gh api` の作成先も同じ。展開はまねないので、ダブルクォートの中と区切りをクォートしないヒアドキュメントの本文は `$` `` ` `` `\` を 1 つでも含めば確定できないとして止める(`$(cat <<D …)` の形を除く) |
| 止めすぎる(算術) | 算術の `((…))` の中の `<<` をヒアドキュメントの開始と読むので、`gh` を含むコマンド全体を読めないとして止める |
| 読む位置を誤る | `cd sub && … --body-file rel.md` の相対パスは入力の `cwd` から読む |
| 区別しない | 対話中かどうか、ラベルを人が選んだかどうかは見ない(「種類の確定」の 4 の (a)・(b) の使い分けは拒否文の案内に頼る) |
| MCP の発火 | `mcp__github__issue_write` で PreToolUse が発火するかは、移植元でも本物のセッションで確かめていない |

`block-git-add-all.sh` / `block-commit-md-heading.sh` / `block-protected-branch-edit.sh` が発火する環境でも残る穴は
次のとおり。取りこぼす形は各判定表が `miss` で、止めすぎる形は `overdeny` で固定している。

| 残る穴 | 内容 |
| --- | --- |
| 一括 add・行頭 `#` の取りこぼし | 判定表 `lib/git-add-all-cases.sh` / `lib/commit-md-heading-cases.sh` の `miss` の行。`bash -c` の中は、引用符の中を見ない引き換えに受け入れた |
| 行頭 `#` の止めすぎ | 引用符の外に `git commit` があれば、同じ入力の別のヒアドキュメント(`gh pr create` の本文など)やシェルのコメント行の行頭 `#` でも止める |
| 保護ブランチを見る場所 | 編集先ではなくフックの作業ディレクトリで見る(リポジトリの外を編集しても止める。作業ディレクトリが外なら、リポジトリの中を編集しても見ない) |
| detached HEAD | `git describe --contains --all HEAD` の名前で見る。保護ブランチの先端に作業ブランチも並んでいると、その名前が返って見ない |
| Bash 経由の書き換え | `sed -i` やリダイレクトでの書き換えは、保護ブランチの上でも見ない(matcher が編集ツールだけのため) |
| jq が無い環境 | `block-git-add-all.sh` と `block-commit-md-heading.sh` は jq でコマンドを取り出すので、jq が無いと素通りする |

### 「代替不能」が実際に不発だったとき、手動で肩代わりする

`block-git-during-verification-agent.sh` / `block-run-without-install.sh` / `block-parent-session-edit.sh` /
`block-issue-without-flow-kind.sh` / `block-git-add-all.sh` / `block-commit-md-heading.sh` /
`block-protected-branch-edit.sh` は上の表のとおり CI の代替が**無し**。
カナリア(次項)で不発が確定したら、「記録のみ」で終わらせず、そのフックが止めるはずだった
操作を手動で確認する(`分類: hook-environment-guard-miss`)。

| 不発したフック | 手動で確認すること |
| --- | --- |
| `block-git-during-verification-agent.sh` | 作業ツリーを書き換えるサブエージェントの実行中に作られたコミットの diff を、そのエージェントが返したはずの内容とだけ照合する(意図しない変更が紛れていないか) |
| `block-parent-session-edit.sh` | このセッションの親の Edit / Write の履歴を見直し、implementation-flow の中でリポジトリの中のファイルを編集していないか確認する |
| `block-run-without-install.sh` | **セッションの Bash 実行履歴を遡る。** 実行した跡はリポジトリに残らないので、見られるのは履歴だけ。`npx` 等を実行していたら、それが持ち込んだファイルが作業ツリーに無いかを `git status` で確かめる |
| `block-issue-without-flow-kind.sh` | このセッションで作った Issue に、`flow:*` ラベル 1 つか、本文の提案の行・通さない行があるか確かめる。無ければ `implementation-flow` フェーズ 1「種類の確定」の 4 で決めて付ける |
| `block-git-add-all.sh` | このセッションで作ったコミットを `git show --stat <コミット>` で見て、意図しないファイル(`.env`・生成物など)が入っていないか確かめる |
| `block-commit-md-heading.sh` | `git log origin/main..HEAD --format=%B \| grep -n '^#'` が何も出さないこと |
| `block-protected-branch-edit.sh` | `git branch --show-current` が保護ブランチでなく、`git log origin/main..main` が何も出さないこと |

`session-url-notice.sh` の不発は対応不要(上の表のとおり、失っても情報が 1 つ足りないだけで
ガードは破れない)。

### 発火しているかを確かめる(カナリア)

`hook-canary.sh` は `echo hook-canary` を必ず deny する。push の前にこれを 1 度実行すると、
silent だったフックの不発が detected に変わる。

**通った = 不発、ではない。** カナリアは自分の取りこぼしと本当の不発を区別できないので、
通ったときは PreToolUse の痕跡を見て決める。

| カナリア | 実行中フラグのマーカー | 発火ログの見出し | 読み方 |
| --- | --- | --- | --- |
| deny された | — | — | **発火している** |
| 通った | ある | — | **カナリアの取りこぼし**。Task/Agent のフックは発火している(不発と書かない) |
| 通った | 無い | ある | SessionStart は発火している。PreToolUse は不明 |
| 通った | 無い | 無い | **本当に不発**(`分類: hook-environment`) |

```bash
ls -d "${TMPDIR:-/tmp}/agent-harness-verification-agents-${CLAUDE_CODE_SESSION_ID:-}"
grep -c $'\tsession\t' "${TMPDIR:-/tmp}/agent-harness-firings-${CLAUDE_CODE_SESSION_ID:-}.log"
```

**マーカーは作業ツリーを書き換えるサブエージェントを 1 度でも通した後にしか現れない。**
`track-verification-agent-activity.sh` がその Task/Agent でしか作らないため、着手直後に
カナリアを実行した回は 2 行目に当たらず、マーカー無しの枝へ落ちる。

マーカーが言えるのは **`Task|Agent` の PreToolUse か PostToolUse のどちらかが発火した**まで。
`mkdir -p` が `hook_event_name` の分岐より手前にあるので、PostToolUse だけでも作られる。

見出しのほうは `record-firings.sh` が **SessionStart** で書く。ログファイル自体は PostToolUse の
追記でも作られるので、**ファイルの有無ではなく見出し行を数える**。

`CLAUDE_CODE_SESSION_ID` が無い環境では、`…-*` の glob で出たものが**別セッションの残骸**で
ないかを見出しの時刻で確かめる(tmp はコンテナに残る)。

**同じ「リモート実行環境」でも発火する場合としない場合がある**ので、不発を前提に設計しつつ、
発火する側を捨てない(層 3 に置く価値はある)。起動時の作業ディレクトリ・並べたリポジトリの数で
発火が割れた対照は `harness/case-law/process.md`「起動の形で発火が割れた対照」。

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

- `block-parent-session-edit.sh` が implementation-flow の外の作業でも拒否したら、その Edit / Write を
  `implementer` に渡す。正規の抜け方はこれだけ(残る穴は「カバー範囲と残る穴」)。
  拒否を外すためだけに `harness-record` / `harness-growth` を起動しない
- `post-merge-review.sh` はマージを**ブロックしない**(`additionalContext` を返すだけ)。マージは人の判断で行われるので、記録が無いことを理由に止めても記録の質は上がらないため
  - 検知対象は `mcp__github__merge_pull_request` と `gh pr merge` のみ。素の `git merge` は見ない(ベースブランチの取り込みで日常的に走るため、拾うと誤発火のほうが多くなる)
- `block-git-during-verification-agent.sh` は、種類ごとの有効期間(フックの本文)より古いマーカーを無視する。実行が異常終了してマーカーを消し損ねたときに、恒久的にブロックし続けないため(フェイルオープン側へ倒す)
  - 拒否されたのに該当するサブエージェントが動いていないなら、中断で PostToolUse が来ずに残った印。拒否文に出るディレクトリの `active.<種類>.*` がそれで、有効期間を過ぎれば無視される。**待たずに消すかは利用者に確認してから**、そのファイルを `rm` で消す。本当に実行中の印を消すと、そのサブエージェントが終わる前に git 操作が通る
- `track-verification-agent-activity.sh` が見るのは `plan-reviewer` / `implementation-reviewer` / `implementer` だけ。`planner` など道具か定義で作業ツリーを書き換えないサブエージェントは、対象にすると背景で起動できなくなるうえ、定義に反した書き換えは返った後の `git status` で見つかる。**誤検知で止まるフックは、エスケープハッチを足す運用を招いて全体が信用されなくなる**

## 動作確認

```bash
# カナリアの判定表（deny / pass / miss が期待どおりか）
bash .claude/hooks/lib/canary-cases.sh

# 取ってきて即実行するコマンドの判定表（配線の検算も含む）
bash .claude/hooks/lib/run-without-install-cases.sh

# 実行中フラグの判定表（起動の拒否と、印が残っている間だけ git 操作が止まること）
bash .claude/hooks/lib/verification-agent-cases.sh

# implementation-flow の中の親セッションの編集の判定表(発火ログは本物の record-firings.sh に書かせる)
bash .claude/hooks/lib/parent-session-edit-cases.sh

# Issue の作業の種類の判定表と、検出器が通す作成を実物の gh で走らせる判定表(後者は gh と openssl が要る)
bash .claude/hooks/lib/issue-flow-kind-cases.sh
bash .claude/hooks/lib/issue-flow-kind-real-gh-cases.sh

# git 操作の 3 本の判定表。deny の行を Bash で直接打つと配線したあとのフック自身に止められるので、
# 確かめるときは判定表を走らせる
bash .claude/hooks/lib/git-add-all-cases.sh
bash .claude/hooks/lib/commit-md-heading-cases.sh
bash .claude/hooks/lib/protected-branch-edit-cases.sh

# 個々のフックへ JSON を直接流す
echo '{"tool_input":{"command":"echo hook-canary"}}' | bash .claude/hooks/hook-canary.sh
echo '{"tool_input":{"command":"npx create-vite"}}' | bash .claude/hooks/block-run-without-install.sh
echo '{"hook_event_name":"SessionStart","session_id":"x"}' | bash .claude/hooks/session-url-notice.sh
echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' | bash .claude/hooks/post-merge-review.sh
```

## 関連するスキル

- `.claude/skills/implementation-flow/` — フェーズ 7 で push の前にカナリアを実行する。「役割の分担」の親の編集の禁止を `block-parent-session-edit.sh` が、「種類の確定」の 4 を `block-issue-without-flow-kind.sh` が強制する
- `.claude/skills/commit/` — コミットメッセージの書き方と分割。`block-git-add-all.sh` / `block-commit-md-heading.sh` が対応する規範
- `.claude/skills/pull-request/` — PR 本文の書き方(`.claude/.pr-template.yml` に従う)
- `.claude/skills/harness-record/` — `record-firings.sh` のログを「発火」欄の材料として読む
- `.claude/skills/harness-growth/` — どの層へ置くかを決める(層の序列は上の表)
