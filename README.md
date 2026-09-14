# agent-harness

AI エージェントに実装させるための**ハーネス**（規約・進め方・検証の観点・強制する仕組み）。

[design-composer](https://github.com/DIO0550/design-composer) で育てたハーネスから、
**言語・スタックに依らない仕組みだけ**を取り出したもの。

**このリポジトリ自身は `AGENTS.md` / `CLAUDE.md` を持たない。** 他のリポジトリと合わせて
使う前提で、常時ロードの入口は**取り込む側**が持つ。ここが配るのは `rules/` 以下の規範と、
それを強制する装置だけ。

## 使い方

このリポジトリをクローンし、取り込む側の `AGENTS.md` / `CLAUDE.md` から `rules/` を
`@` import する。

```markdown
## 規約一覧(常時ロード)

- @agent-harness/rules/process.md — 規範と判例の分け方・実装の進め方・タスクの分割・Issue の閉じ方・規約の更新
- @agent-harness/rules/coding.md — イミュータブル・関数のシグネチャ・コメント(doc と Why / Why not)・規約の適用範囲
- @agent-harness/rules/naming.md — 命名(名前と実体の一致・汎用語の禁止・ファイル名)
- @agent-harness/rules/testing.md — テスト配置・テストの書き方(ネスト禁止)
```

`@` import のパスは、クローンした場所に合わせて読み替える（上の例は取り込む側の
リポジトリ直下へ `agent-harness/` として置いた場合）。

`.claude/` `harness/` `.github/` の中身は**このリポジトリのルート基準の相対パス**で互いを
参照している。クローンした位置をルートとして扱うこと。

```bash
bash harness/githooks/set-hooks-path.sh   # push 前検査を配線する（クローン後に 1 度）
bash harness/githooks/pre-push            # 検査をその場で走らせる
echo hook-canary                          # フックが発火する環境かを確かめる（deny されれば発火）
```

## 何が入っているか

| 置き場所 | 中身 |
| --- | --- |
| [`rules/`](rules/) | 規範。取り込む側が常時ロードする（合計 900 行が上限） |
| [`harness/case-law/`](harness/case-law/) | 判例。常時ロードしない。迷ったとき・指摘を受けたときだけ読む |
| [`harness/records/`](harness/records/) | マージ後の評価記録。`count.sh` が分類ごとの再発数を数える |
| [`harness/githooks/`](harness/githooks/) | 実行環境に依存しない push 前検査（層 2） |
| [`.claude/skills/`](.claude/skills/) | 進め方（`implementation-flow` / `harness-record` / `harness-growth` / `claim-verification`） |
| [`.claude/agents/`](.claude/agents/) | 検証の観点（`plan-reviewer` / `implementation-reviewer` / `harness-counter`） |
| [`.claude/hooks/`](.claude/hooks/) | セッション中に効くフック（層 3） |
| [`.github/`](.github/) | 無条件に効く検査（層 1） |

## 仕組み

**指摘を数えて、効く層へ上げる。**

1. 実装は `implementation-flow` の 8 フェーズで進む（計画 → `plan-reviewer` → 実装 →
   `implementation-reviewer` → PR）
2. マージのたびに `harness-record` が指摘・CI 失敗・手戻りを分類タグ付きで
   `harness/records/` に 1 ファイル残す
3. `harness-growth` が `count.sh` で「**最後の介入以降の再発数**」を数え、再発していれば
   強制力の強い層（CI → git hooks → スキル → 観点 → `rules/`）へ介入する。
   同じ層で再発したら層を 1 つ上げる

強制力の序列と、CI でも git でも代替できないものの一覧は
[`.claude/hooks/README.md`](.claude/hooks/README.md)「強制力の序列」。

## よく使うコマンド

```bash
bash harness/records/count.sh             # 分類ごとの再発数を数える
bash harness/records/count.sh --shrink    # 縮める候補を出す（harness-growth の Step 3）
wc -l rules/*.md                          # 常時ロードの行数（上限 900）
bash .claude/hooks/lib/canary-cases.sh    # カナリアの判定表
bash .github/scripts/check-pr-closing-issue-cases.sh  # 閉じる Issue の検査の判定表
```

## 移植元から持ってこなかったもの

このリポジトリにはまだ対象が無いため、次は入っていない。使う側のスタックが決まったら足す。

- `rules/architecture.md`（フォルダ構成・依存方向）/ `rules/hooks.md`・`rules/components.md`（React）/
  `rules/ui-verification.md`（Storybook・Playwright）
- TypeScript / pnpm 前提の検査フック（lint・typecheck・doc コメント・テスト規約・import 規約）と、
  それを走らせる CI
- design-composer の評価記録 117 本（判例だけを持ってきている。再発数はこのリポジトリの
  最初のマージから数え直す）
