# harness/githooks — 実行環境に依存しない push 前検査

git ネイティブのフック置き場。`core.hooksPath` をここへ向けると、CLI・IDE・素の git の
どれから push しても同じ検査が走る。

## 配線

```bash
bash harness/githooks/set-hooks-path.sh

# 配線されているかの確認
git config --get core.hooksPath   # → harness/githooks
```

**いまは手で 1 度実行する形になっている。** このリポジトリはまだパッケージマネージャを
持たないので、インストールの後処理（npm / pnpm の `prepare` など）から自動で呼ぶ先が無い。

**手で実行する形は穴になる。** クローンのたびに実行が要るが、リモート実行環境
（Claude Code on the web など）は毎回クローンからやり直す。そこは Claude Code のフックが
読まれないことがある環境と同じなので、**層 2 と層 3 が同時に抜けて CI だけが残る**
（design-composer で実際に起きた形）。依存関係のインストール手順がこのリポジトリに
入ったら、その後処理から `set-hooks-path.sh` を呼んで自動配線へ移すこと。

## 何が走るか

| フック | 検査 | 呼んでいるもの |
| --- | --- | --- |
| `pre-push` | シェルスクリプトの構文 / shellcheck / 検出器の判定表 | `bash -n`・`shellcheck`・`.claude/hooks/lib/canary-cases.sh`・`.claude/hooks/lib/run-without-install-cases.sh`・`.github/scripts/check-pr-closing-issue-cases.sh` |

| スクリプト | 呼ばれ方 | 内容 |
| --- | --- | --- |
| `set-hooks-path.sh` | 手で 1 度 | `core.hooksPath` をここへ向ける。git の無い環境・git リポジトリでない場所では黙って飛ばす |

**検査できるのは、いまはハーネス自身のシェルスクリプトだけ。** アプリケーションのソースが
入ったら、その言語の型チェック・lint・テストを `pre-push` へ足す
（`rules/coding.md`「規約の適用範囲」により、ハーネス自身のツールのコードも規約の対象）。

`shellcheck` / `python3` / `jq` が無い環境では、それを使う検査だけを飛ばして通す。
検査できないことを理由に push を止めても検査の質は上がらないため。

## なぜ git 側にも置くのか

**Claude Code のフックは発火しない実行環境がある。** リモート実行環境（Claude Code on the
web など）では `.claude/settings.json` の配線が読み込まれないことがあり、しかも
**フェイルオープンかつサイレント**なので、通ったのか検査されなかったのかが区別できない。

強制力の序列は次のとおり。詳細と、CI でも git でも代替できない制約の一覧は
[`.claude/hooks/README.md`](../../.claude/hooks/README.md)。

| # | 層 | 効く範囲 | タイミング |
| --- | --- | --- | --- |
| 1 | CI | 無条件 | push の後 |
| 2 | git hooks（ここ） | クライアント非依存 | push の前 |
| 3 | Claude Code hooks | CLI 起動セッションのみ | 編集・コマンドの直前 |
| 4 | skill / rules | お願いベース | 読まれたとき |

## 動作確認

```bash
bash harness/githooks/pre-push
```

`core.hooksPath` を設定したうえで push すると、失敗した検査の出力がそのまま出て
push が中止される。
