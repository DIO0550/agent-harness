# AGENTS.md — 実装規約

このリポジトリで実装を行うAIエージェントは、以下の規約に**必ず**従うこと。
各規約は `rules/` 配下にあり、以下の `@` import で常にコンテキストへ読み込まれる。

## プロジェクト構成

このリポジトリは**ハーネスそのもの**を持つ。アプリケーションのソースはまだ無い。

```
AGENTS.md        # ここ。常時ロードされる規範の入口(CLAUDE.md はこれへのシンボリックリンク)
rules/           # 規範。常時ロードされる
harness/
  case-law/      # 判例。常時ロードしない
  records/       # マージ後の評価記録。harness-record スキルが 1 マージ 1 ファイル足す
  githooks/      # 実行環境に依存しない push 前検査(層 2)
.claude/
  skills/        # 進め方(implementation-flow / harness-record / harness-growth / claim-verification)
  agents/        # 検証の観点(plan-reviewer / implementation-reviewer / harness-counter)
  hooks/         # セッション中に効く検査・提示(層 3)
.github/
  workflows/     # 無条件に効く検査(層 1)
  scripts/       # ワークフローが呼ぶ検査と、その判定表
```

**言語・パッケージマネージャはまだ決まっていない。** 決めたら、その言語の規範を `rules/` へ、
検査を `harness/githooks/pre-push` と `.github/workflows/` へ足す
(`rules/coding.md`「規約の適用範囲」)。

## 規約一覧(常時ロード)

- @rules/coding.md — イミュータブル・関数のシグネチャ・コメント(doc と Why / Why not)・外部の挙動の確かめ方・規約の適用範囲
- @rules/naming.md — 命名(名前と実体の一致・汎用語の禁止・ファイル名)
- @rules/testing.md — テスト配置・テストの書き方(ネスト禁止)

**移植元(design-composer)の `architecture.md` / `hooks.md` / `components.md` /
`ui-verification.md` は持ってきていない。** それぞれフォルダ構成・React・Storybook を
前提にしていて、このリポジトリでは意味が通らないため(判断軸は次節)。判例の側には
残してあるので、対応するものが必要になったらそこを下敷きにする。

## 規範と判例を分ける

`rules/` に置くのは**規範**(こうする)だけ。**判例**(この回こうだった / NG・OK の実例 /
このリポジトリ固有のシンボル名)は `harness/case-law/` に置き、**常時ロードしない**。

- 判断軸は「**別のリポジトリへ持っていって意味が通るか**」。通るなら `rules/`、通らないなら判例
- 判例を読むのは、**その分類で実際に迷ったとき・指摘を受けたとき**と、検証エージェント
- 判例を書けるのは `harness-growth` だけ(`harness/case-law/README.md`)

**理由: 判例は毎回増え、規範は増えない。** 同じファイルに置くと常時ロードが単調増加する。

## 常時ロードには上限がある

**`AGENTS.md` + `rules/` の合計を 900 行以内に保つ。** これを超えたら、足す前に同量を削る
(削り先が出せないなら、その追加は `rules/` ではなく判例・観点・フックのどれかに置く)。

- 数え方: `wc -l AGENTS.md rules/*.md`
- 閾値に達してから棚卸しするのではなく、**追加のたびに払う**。閾値方式は「超えるまで増え続ける」
  ことを許すので、超えた時点で必ず大きな棚卸しが要る
- 上限そのものの見直しは `harness-growth` の Step 3

## 実装の進め方

実装は `implementation-flow` スキルの手順で進める(`.claude/skills/implementation-flow/`)。
ゴールの確定 → タスクの分割 → 計画 → **計画の検証(`plan-reviewer`)** → 実装 →
**実装の検証(`implementation-reviewer`)** → PR → マージ後の追記、までが1セット。

検証の観点は `.claude/agents/` のサブエージェントが持つ。ここにも `rules/` にも置かないのは、
**検証のときにしか要らないものを常時ロードへ入れないため**。

**計画・却下した案・その理由は、すべて Issue に追記する。** PR 本文は差分の説明、
Issue は判断の履歴、という分担にする。採用した案だけを残すと、後で同じ案が再浮上した
ときに前回やめた理由が失われる。

マージ後は `harness-record` スキルでその回の評価を記録する
(`.claude/skills/harness-record/`)。記録を数えて規約やフックへ手を入れるのは
`harness-growth` スキル(`.claude/skills/harness-growth/`)で、別の機会に行う。

## タスクの分割

**タスクが大きくなりそうな場合は、Issue を分離して新たに登録する。** 1つの Issue に
抱え込むと、計画が「やることの列挙」になって判断の記録が残らず、レビューも差分が
まとまって届くため一度に読めなくなる。

- 判断軸は「**独立してマージできるか**」。片方だけ入っても壊れない単位が2つ以上見えたら分ける
- 分けたら、元の Issue に**分割した理由**とリンクを残す。分けた側にも「何をスコープ外に
  したか」を書く
- 分けないと決めた場合も、**その理由を Issue に書く**。分けないこと自体が判断なので、記録の対象になる

## 着手した Issue は、その回で閉じる

**着手したら自分をアサインし、PR 本文の `Closes #<番号>` で閉じる。** 手では閉じない
(検査は `.github/workflows/pr-closing-issue.yml`。例外は `harness-record` の記録 PR だけ)。

- 続きが要るものは**新しい Issue を立てて元からリンクする**。閉じた Issue は開け直さない
  (その回に変わった判断は、閉じたままコメントで残す → `implementation-flow` フェーズ 8)
- PR を出さずに止まったものと、子へ分割した親 Issue は open のままでよい(閉じる起点が来ない)

## 実装を始める前に

自己チェックの観点は `rules/` にある。**同じ内容をここに写さない**(2 箇所に置くと片方だけ
古くなる)。実装前・PR 前に読む順は次の通り。

1. `rules/coding.md`「コメントは doc と Why / Why not に絞る」「外部の挙動は動かして確かめる」「規約の適用範囲」
2. `rules/naming.md`「名前と実体を一致させる」「その名前が既に別の意味を持っていないか確認する」
3. `rules/testing.md`「assert は『落ちうるか』と『1つの仕様か』で見る」

迷ったら `harness/case-law/` の同名ファイルを開く(移植元で同じ形で指摘された実例がある)。

## 規約の更新

レビューで新しい判断基準が示されたら、その場の修正で終わらせず反映する。**ルールに書かれて
いない指摘が2回以上出たら、規約の抜けとして扱う。**

回数を数える材料は `harness/records/` に溜まる(マージのたびに `harness-record`
スキルが記録を1ファイル追加する)。数えるのは `harness/records/count.sh`。
**通算ではなく「最後の介入以降の再発数」で見る**(通算は単調増加するので、介入が効いたかを
表さない)。同じ層で再発したら層を1つ上げる。手順は
`.claude/skills/harness-growth/SKILL.md`「Step 1」「Step 2」。

**記録はまだ 0 本。** 移植元の記録は持ってきていないので、数え始めるのはこのリポジトリで
最初のマージから。移植元で何が起きたかは `harness/case-law/` が持つ。

**規約に足すときは、同じファイルが既に持っている記述・例と突き合わせる**
(`分類: rules-consistency`。判定文が規約自身の例で逆の答えを出した / 前の節と矛盾した /
表の行が網羅していなかった、が実際に起きている)。手順は `harness-growth` の Step 2。

## 設計判断の確認

層をまたぐ移動や既存モジュールの再配置など、**他の規約と衝突しうる変更**は、実装前に選択肢と根拠を示して確認する(勝手に進めず、判断だけを仰ぐ)。

## Issue に紐づいて起動したら、セッションの URL を Issue に残す

Issue に紐づく作業でセッションが始まったら、**着手した時点で**その Issue へ
Claude Code セッションの URL をコメントする(`https://claude.ai/code/session_<id>`)。
判断待ちで止まるときは、**選択肢と根拠を書いたコメントに改めて併記する**。

**理由: 経緯はそのセッションの中にしか無い。** どこまで読んだか・何を確かめて選択肢を絞ったかは
Issue のコメントに書ききれず、Issue だけを見ている人と、あとから引き継ぐ**別のセッション**が
辿れなくなる。**止まってから残すのでは遅い**(止まるかどうかは着手時には決まっていない)。
通知(Discord 等)にだけ載せるのでは足りない — 通知は流れるが Issue は残る。

層 3 まで上げてある(`session-url-notice.sh` / SessionStart)。**なぜ層 2・層 1 へ上げられないか**は
[`harness/case-law/process.md`](harness/case-law/process.md)。

## Common Commands

リポジトリルートで実行する：

```bash
bash harness/githooks/set-hooks-path.sh   # push 前検査を配線する(クローン後に 1 度)
bash harness/githooks/pre-push            # push 前検査をその場で走らせる
bash harness/records/count.sh             # 分類ごとの再発数を数える
bash harness/records/count.sh --shrink    # 縮める候補を出す(harness-growth の Step 3)
wc -l AGENTS.md rules/*.md                # 常時ロードの行数(上限 900)
echo hook-canary                          # フックが発火しているかを確かめる(deny されれば発火)
bash .claude/hooks/lib/canary-cases.sh    # カナリアの判定表
bash .github/scripts/check-pr-closing-issue-cases.sh  # 閉じる Issue の検査の判定表
```
