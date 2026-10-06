# PR #2 feat: design-composer のハーネスを仕組みだけ移植する

- マージ日: 2026-10-06
- 関連 Issue: #1
- 差分規模: 41 ファイル / +4996 -1

## ゴールと結果

ゴールは「このリポジトリで実装を始めたときに、その日からハーネスが回る」こと。3 条件
(implementation-flow の 8 フェーズが回る / `harness-record` と `count.sh` が使える /
層 1〜3 が配線されカナリアで発火を確かめられる)のうち、**1 と 2 は達成。3 は半分。**

層 1(CI)と層 2(git hooks)は実際に走っている(この回の push で `pre-push` が発火した)。
層 3 はこのセッションでは 1 本も発火せず、「書いたら実行前に止まる」は未確認で残った(#3)。

途中でゴールが 1 度変わった。`AGENTS.md` / `CLAUDE.md` を持たない形へ移したため、
常時ロードの入口は取り込む側が持つ設計になった。

## 指摘

### 1. `AGENTS.md` / `CLAUDE.md` を持たない形にする

- 分類: `なし`
- 出どころ: `レビュー（人）`
- 内容: 1 本目の PR が完成した後に「他のリポジトリと合わせて使う想定だから入口ファイルは要らない」と指示を受けた。規範 9 節を `rules/process.md` へ畳み、`AGENTS.md` への参照 30 箇所を書き換えた
- 既存ルール: なし
- 次にどう防ぐか: 今回は記録のみ。「ハーネスを配るリポジトリは入口ファイルを持たない」は 1 例しか無く、規範にするには早い

### 2. 移植元の `block-npx.sh` を移しておらず、除外リストにも挙げていない

- 分類: `plan-file-omission`
- 出どころ: `レビュー（人）`
- 内容: 「npx の禁止もフックを付けているか」と聞かれて露見した。移植の計画(#1)は `.claude/hooks/` を「言語非依存の 6 本」と数えており、`block-npx.sh` はその 6 本にも除外リストにも入っていない。除外理由に書いた「TypeScript のソースと pnpm を前提にしている」もこのフックには当てはまらない
- 既存ルール: `plan-review.md`「変更で壊れる既存の資産を洗い出しているか」
- 次にどう防ぐか: 今回は記録のみ。移植は 1 回しか起きない作業で、同じ形の再発は見込みにくい

### 3. ゴール(実行前に止まる)を確かめる手段が計画に無い

- 分類: `plan-goal-verification`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 判定表は JSON を実物のフックへ直接流すので、`.claude/settings.json` への配線を忘れても全件 ok になる。このリポジトリに `settings.json` を参照する検査は 1 つも無かった
- 既存ルール: `plan-review.md`「ゴールの達成を確かめる手段」
- 次にどう防ぐか: 今回は記録のみ

### 4. jq 無しを前提にした `miss` 行を置くと `pre-push` が落ちる

- 分類: `plan-scope-premise-verification`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: `pre-push` は python3 と jq が両方ある枝でしか判定表を走らせない。jq がある環境では該当行が deny になり NG → exit 1。前提(どの環境で表が走るか)を確かめていなかった
- 既存ルール: implementation-flow フェーズ 3 手順 3
- 次にどう防ぐか: 今回は記録のみ

### 5. 却下の基準を自案に当てていない(`(` 由来の誤検知)

- 分類: `plan-rejection-reasoning`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 案 B を「実測で 2 件の誤検知が出るから」却下しておきながら、自案は `(` を区切りに入れて実測 3 件以上の誤検知を受け入れる形になっていた
- 既存ルール: implementation-flow フェーズ 3 手順 5
- 次にどう防ぐか: 今回は記録のみ

### 6. 案 D の却下理由が実物と食い違っていた

- 分類: `plan-rejection-reasoning`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 「移植元が `lib/` へ出しているのは実体のある検出器だけ」と書いたが、`lib/pre-push-detector.sh` は `jq -r '.tool_input.command'` と deny の JSON ごと共有する sourced ライブラリで、2 本が使っている。「5 本」も移植元ではなくこのリポジトリの数だった。結論(共有しない)は変えず理由を書き直した
- 既存ルール: implementation-flow フェーズ 3 手順 5
- 次にどう防ぐか: 今回は記録のみ

### 7. いちばん近い代替案(`permissions.deny`)が却下案に挙がっていない

- 分類: `plan-rejection-coverage`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: Claude Code の組み込み機構で、しかも移植元の `settings.json` が `permissions.allow` を実際に使っている。grep で届く範囲にあるのに探していなかった
- 既存ルール: implementation-flow フェーズ 3 手順 6
- 次にどう防ぐか: 今回は記録のみ

### 8. ファイル表の漏れ(`harness/githooks/README.md`)

- 分類: `plan-file-omission`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 「何が走るか」の表のセルが判定表を名指しで列挙しているのに、3 本目を足す計画のファイル表に挙がっていなかった
- 既存ルール: `plan-review.md`「ファイル表に挙がっているか」
- 次にどう防ぐか: 今回は記録のみ

### 9. doc コメント内でだけ名指しされている記述がファイル表に無い

- 分類: `plan-comment-reference`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: `pre-push` のコメント「判定表は…**どちらも** python3 / jq を使うので」が 3 本になると嘘になるのに、「判定表を 1 本追加」としか計画に書いていなかった
- 既存ルール: `plan-review.md`「ファイル表に挙がっているか」
- 次にどう防ぐか: 今回は記録のみ

### 10. この差分が載る PR 本文が、同じ差分で古くなる

- 分類: `plan-file-omission`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: PR #2 の本文がフックの列挙・「検査フック 12 本」・判定表の件数を持っており、3 つとも古くなる。成果物として計画に挙げていなかった
- 既存ルール: `plan-review.md`「ファイル表に挙がっているか」
- 次にどう防ぐか: 今回は記録のみ

### 11. pass ケースが、他のケースと同じ壊し方でしか落ちない

- 分類: `test-assert-unfalsifiable`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: ミューテーション実測で、末尾の境界を固有に殺すのは `npxfoo bar` の 1 件だけで、しかも `npx` にしか効かなかった。`bunx` / `uvx` / 2 語形の末尾境界を殺すケースが一覧に無い
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ。指摘どおり `bunxyz foo` / `uvxtool` / `pnpm dlxfoo` を足し、壊すと 3 件 NG になることを実測した

### 12. ゴールに対する対象の列挙漏れ

- 分類: `comment-missing-issue-only`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: `npm exec` / `npm create` / `pnpm create` / `yarn create` / `npm init <パッケージ>` / `deno run <URL>` が全部 pass のままだった。どこで線を引いたかもフック本体に書かれず Issue だけにあった
- 既存ルール: rules/coding.md「コメントは doc と Why / Why not に絞る」
- 次にどう防ぐか: 今回は記録のみ

### 13. deny の文面が未決のまま計画が閉じていた

- 分類: `plan`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: このリポジトリに `package.json` も pnpm も無いので移植元の文面(「pnpm add でインストールしてから」)は使えない。止めた後に何をすればよいか言えないフックになっていた
- 既存ルール: implementation-flow フェーズ 3「未決の判断」
- 次にどう防ぐか: 今回は記録のみ

### 14. 同じ判断根拠を README と SKILL.md の 2 箇所に書こうとしていた

- 分類: `duplication-rationale`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 「セッション中の行為の禁止は層 1・2 で代替できない」が既に `implementation-flow/SKILL.md` にあり、README の表へ同じ根拠を書くと片方だけ古くなる。README は「手動で確認すること」、SKILL.md は根拠、と分担を決めた
- 既存ルール: rules/coding.md「規約の適用範囲」
- 次にどう防ぐか: 今回は記録のみ

### 15. 4 つめの期待 `fp` が既存の語彙と語形で割れる

- 分類: `naming-vocabulary-alignment`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: 既存の `deny` / `pass` / `miss` はいずれも結果を表す 1 語。略語を混ぜると 2 つの表の語彙が割れる。`overdeny` に変えた
- 既存ルール: rules/naming.md「メソッド名を既存のドメインに揃える」
- 次にどう防ぐか: 今回は記録のみ

### 16. Issue に書いた件数が実物と食い違っていた

- 分類: `plan-scope-count-verification`
- 出どころ: `レビュー（plan-reviewer）`
- 内容: `block-npx` への参照を「6 箇所」と書いたが実際は 5 箇所。書いた後に `grep -rn` で数え直して気づき、Issue のコメントを直した(綴りも「5 ファイル中 4 ファイル」と崩れていた)
- 既存ルール: implementation-flow フェーズ 3 手順 2
- 次にどう防ぐか: 今回は記録のみ

### 17. 判定表が「deny かどうか」を見ていない

- 分類: `test-coverage-wiring`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 出力が空でないことしか見ていなかったため、`permissionDecision` を `allow` に変えても、`hookEventName` を変えても、JSON を壊しても、末尾に `exit 1` を足しても全件通った(実測)。ゴールそのものを 1 つも守っていない表だった
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ。JSON として読んで決定とイベントと終了コードまで見る形に直し、壊すと 28 件 NG になることを実測した

### 18. 配線の検算が grep 1 本で、イベントも matcher も見ていない

- 分類: `test-coverage-wiring`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `settings.json` のエントリを `PostToolUse` / `Task|Agent` へ移しても `ok wired` のまま通った(実測)。指摘 3 への対応として足した検算が、それ自体ゴールを確かめていなかった
- 既存ルール: `plan-review.md`「ゴールの達成を確かめる手段」
- 次にどう防ぐか: 今回は記録のみ

### 19. `go run` の `@` 枝が無テストで、しかも誤検知を作る

- 分類: `test-coverage-branch-asymmetry`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `|@` を落としても NG 0 件(deny 3 件はすべてドメイン枝で通る)。そのうえ `go run ./cmd/app -to=user@example.com` が止まった(実測)。リモート指定はドメイン枝に包含されるので冗長かつ有害だった
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ

### 20. `deno run` の `://` が引数のどこでもマッチする

- 分類: `test-coverage-branch`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `deno run server.ts --url=https://api.example.com` が止まった(実測)。ローカルスクリプトに URL をフラグで渡す形は普通なのに、pass にも overdeny にも分類されていなかった
- 既存ルール: rules/testing.md「古典学派のテスト」
- 次にどう防ぐか: 今回は記録のみ

### 21. 引数走査の区切り柵が無テスト

- 分類: `test-coverage-branch`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `[^;&|\n]*` を `.*` に緩めても NG 0 件。Why は書いてあるのに、それを固定するケースが無かった
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ

### 22. `word_end` の `)` が無テストで、事実上到達しない

- 分類: `over-guard`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `)` を落としても NG 0 件。`(` を区切りから外しているので、ランナーが `)` の直前に来るのは実在しない形だけだった。移植元の `\b` を手で展開したときの残りに見える
- 既存ルール: implementation-flow フェーズ 6
- 次にどう防ぐか: 今回は記録のみ

### 23. jq フォールバック経路が、表から一度も踏まれない

- 分類: `test-coverage-branch`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: jq がある環境では生 JSON の枝に到達しないので、新設した分岐をどのテストからも狙って壊せなかった。PATH を絞って踏む枝を足したが、**反転する 2 件だけでは枝を丸ごと壊しても取りこぼし側で通る**ことに自分で気づき、jq 無しでも deny になるケースを 1 件目に置いた
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ

### 24. `overdeny` の列挙が `;` だけで、同じ原因の `|` と改行が無い

- 分類: `test-coverage-branch-asymmetry`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 同じ原因(引用符を追わない)で `echo "pipe | npx foo"` もヒアドキュメントも止まる。**`npx` を列挙する doc をヒアドキュメントで書く形**は、この差分の中身がまさにそれなのでこのリポジトリで最も踏みやすい
- 既存ルール: rules/testing.md「その assert は落ちうるか」
- 次にどう防ぐか: 今回は記録のみ

### 25. 判定表の走行部・抽出部・doc が写しになっていた

- 分類: `duplication-traversal`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 表の走行部(`while IFS='|' read` 以下)が `canary-cases.sh` と 2 本目、JSON からコマンド本文を取り出す処理が `hook-canary.sh` と**コードは完全同一**で 3 本目になっていた。`lib/` は「共有部品と表の置き場」と説明されているのに共有部品が 1 つも無かった
- 既存ルール: rules/coding.md「同じ処理が2箇所に現れたら共通化する」
- 次にどう防ぐか: 今回は記録のみ。走行部は `lib/case-table.sh` へ切り出して共有し、抽出部は共有しないまま「表は落ちれば分かる / フックは黙る」の非対称を Why として両方に書いた

### 26. 表の doc が兄弟ファイルと写しになっていた

- 分類: `duplication-rationale`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 使い方・期待の意味の表・「JSON の組み立てに python3 を使う」理由が `canary-cases.sh` と二重に書かれていた。共通部分は `lib/case-table.sh` へ移した
- 既存ルール: rules/coding.md「規約の適用範囲」
- 次にどう防ぐか: 今回は記録のみ

### 27. 置き換えたコメントで列挙が 1 つ減った

- 分類: `comment-enumeration-drift`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `hook-canary.sh` に「`|` を区切りに入れていて、ここだけ逆」と書いたが、逆なのは `|` と**単独の `&`** の 2 文字。差分前の文は「`|` `&` の扱いが逆になる」と両方挙げていた
- 既存ルール: rules/coding.md「実装を変えたらコメントも同時に直す」
- 次にどう防ぐか: 今回は記録のみ

### 28. 表が 2 行になったのに導入文が単数のまま

- 分類: `comment-enumeration-drift`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `.claude/hooks/README.md`「`block-git-during-verification-agent.sh` は上の表のとおり CI の代替が無し。」の直後の表に行を足したが、導入文を直していなかった
- 既存ルール: rules/coding.md「実装を変えたらコメントも同時に直す」
- 次にどう防ぐか: 今回は記録のみ

### 29. 判例に残った `block-npx.sh` の参照(受け入れなかった指摘)

- 分類: `comment-referent-drift`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 実在しないファイル名を実在するものへ差し替える作業をしたが、`harness/case-law/process.md:71` だけ残した。**受け入れていない** — `harness/case-law/README.md` が「過去の判例を書き換えない」「判例を書けるのは `harness-growth` だけ」を明記しているため。#4 へ回した
- 既存ルール: `harness/case-law/README.md`
- 次にどう防ぐか: 今回は記録のみ。`harness-growth` の回に新しい判例を足す形で扱う

### 30. 注記に帰結が書かれていない

- 分類: `comment-behavior-claim`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 「jq が無いと pass になる…判定が変わったと読み違えないこと」で止めており、**実際には NG 2 行を出して exit 1 する**ことを書いていなかった。兄弟の `canary-cases.sh` は「deny 側が全件 NG になる」と帰結を名指ししている
- 既存ルール: rules/coding.md「コメントは実装と一致させる」
- 次にどう防ぐか: 今回は記録のみ

### 31. 実測値の主張が不正確だった

- 分類: `comment-behavior-claim`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 「ここは正規表現 1 回で済む(131KB で 2ms)」と書いたが、実際は正規表現 3 本。判断(長さの上限を置かない)は正しいが、数が実装と食い違っていた
- 既存ルール: rules/coding.md「コメントは実装と一致させる」
- 次にどう防ぐか: 今回は記録のみ

### 32. 理由が 3 行を超え、例示が表と二重になっていた

- 分類: `comment-excess`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 1 つの理由に 3〜4 行使っている塊が 4 つあり、挙げた具体例 6 つはすべて判定表の行としても書かれていた。判定が変わったときに落ちるのは表なので、コメントは理由 1 文 + 例 1 つに絞った
- 既存ルール: rules/coding.md「コメントは doc と Why / Why not に絞る」
- 次にどう防ぐか: 今回は記録のみ

### 33. doc の付着先と行幅が周囲からずれた

- 分類: `comment-block-placement`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: 裸の `#` 行が残って `judge()` の doc が空行から始まっていた。`judge()` の `@returns`(何を返すか)も欠けていた。改名で `SKILL.md` の 1 行目が伸び、6 文字の孤立行ができていた
- 既存ルール: rules/coding.md「doc に書く項目」
- 次にどう防ぐか: 今回は記録のみ

### 34. 装置だけが増え、`rules/` 側に規範が無い

- 分類: `harness-process-drift`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `grep -rni` で `rules/` にも `.claude/skills/` にも 0 件。`README.md` は「配るのは `rules/` 以下の規範と、それを強制する装置だけ」と書き、`.claude/hooks/README.md` は CI の代替を「無し」と宣言しているのに、層 4 が無い状態だった。`SKILL.md` の「禁止コマンドを実行していないか見直す」も一覧がフックの中にしか無かった
- 既存ルール: rules/coding.md「規約の適用範囲」
- 次にどう防ぐか: 今回は記録のみ。`rules/coding.md` に「インストールせずに取ってきて実行しない」を足した(334 / 900 行)

### 35. 名前の断定が実体より狭かった

- 分類: `naming-vocabulary-alignment`
- 出どころ: `レビュー（implementation-reviewer）`
- 内容: `npx` / `npm exec` はローカルの `node_modules/.bin` に在ればそれを使うので、必ず取りに行くとは限らない。「インストールせずに」は `npx` に関しては実体より狭い断定だった。doc を「取ってきて実行しうる」に緩め、一律で止める理由を添えた
- 既存ルール: rules/naming.md「名前と実体を一致させる」
- 次にどう防ぐか: 今回は記録のみ

### 36. 131KB のコマンドを argv で渡して `Argument list too long`

- 分類: `tool-behavior-unverified`
- 出どころ: `自己修正`
- 内容: 長さの上限を固定するケースを `python3 -c '...' "$長い文字列"` で渡し、ARG_MAX を超えてフックまで届かなかった。判定表が exit 1 になって気づいた。標準入力経由に直した
- 既存ルール: rules/coding.md「外部の挙動は動かして確かめる」
- 次にどう防ぐか: 今回は記録のみ

### 37. 層 3 がこのセッションでは 1 本も発火していない

- 分類: `hook-environment`
- 出どころ: `自己修正`
- 内容: `echo hook-canary` が素通りし、検証エージェントのマーカーも発火ログも無い(README の 3 条件すべて)。原因は作業ディレクトリがリポジトリの外(`/home/user`)で `CLAUDE_PROJECT_DIR` が未設定のため `.claude/settings.json` が読まれていないこと。`block-git-during-verification-agent.sh` の役は手で肩代わりし(検証エージェント実行中はコミットせず、返却後に `git status` / `git diff` を確認)、禁止コマンドの実行も無かったので**素通りした操作は無い**
- 既存ルール: `.claude/hooks/README.md`「強制力の序列」
- 次にどう防ぐか: 今回は記録のみ。実機確認は #3 へ

## 手戻り

3 つ。

- **入口ファイルの設計変更。** 1 本目の PR が完成・CI 緑の後に `AGENTS.md` / `CLAUDE.md` を持たない形へ変えた。`AGENTS.md` への参照 30 箇所(CI のメッセージ・SessionStart の出力・`count.sh` の行数検査を含む)を書き換え、`README.md` を 2 度書き直した
- **計画の書き直し。** `plan-reviewer` の 14 件すべてを受け入れたため、対象の一覧(`npm create` 系・`deno run` の追加)・区切り文字(`(` の除外)・期待の語彙(`fp` → `overdeny`)・成果物(PR 本文・`githooks/README.md` の追加)が変わった
- **判定表の作り直し。** `implementation-reviewer` の指摘で、deny の判定・配線の検算・jq 経路の踏み方・ケースの選び方を入れ替え、走行部を `lib/case-table.sh` へ切り出した。切り出し後にカナリアの判定 30 件が同一であることを比較して確認した

## 発火

- 発火: 計測対象外(フック不発)

## うまくいったこと

- **検出の形をプロトタイプで先に実測したこと。** 計画に書く前に 39 ケースを走らせたので、「移植元と同じ境界だと `grep -rn npx .` で止まる」を実測の裏付き付きで却下案に書けた。`plan-reviewer` もこの却下理由だけは「計画どおり」と確認して終わっている
- **ミューテーションで判定表が落ちることを毎回確かめたこと。** 指摘 17・18 の修正後に 7 通りの壊し方を当て、どれで何件 NG が出るかを数えた。指摘 11 が求めた 3 ケースも、足した後に壊して 3 件 NG を実測している
- **カナリアのリファクタを出力比較で守ったこと。** `canary-cases.sh` を共有の走行部へ寄せる前に出力を保存し、寄せた後に空白を正規化して差分 0 を確認した

## 規約への反映

無し。**この回が記録 1 本目なので、まだ「2 回以上」を数えられない。**
`rules/coding.md` へ 1 節足しているが、これは指摘 34(装置に対応する規範が無い)への
その回の修正で、再発数を根拠にした介入ではない。

分類の再発は次の回から数えられる。この回で複数回出たのは
`plan-file-omission`(3)・`test-coverage-branch`(3)・`test-coverage-wiring`(2)・
`plan-rejection-reasoning`(2)・`comment-enumeration-drift`(2)・
`comment-behavior-claim`(2)・`test-coverage-branch-asymmetry`(2)・
`duplication-rationale`(2)・`naming-vocabulary-alignment`(2)。
**すり抜け(人・bot 由来)は 2 件**で、どちらも移植そのものに関する判断
(指摘 1・2)。検出の中身に関する指摘はすべてサブエージェントが捕まえている。
