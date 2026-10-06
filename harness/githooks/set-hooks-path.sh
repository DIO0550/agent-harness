#!/usr/bin/env bash
#
# `core.hooksPath` を harness/githooks へ向ける。
#
# **いまはクローンのあと手で 1 度実行する。** このリポジトリはまだパッケージマネージャを
# 持たないので、インストールの後処理から自動で呼ぶ先が無い(harness/githooks/README.md
# 「配線」)。手で実行する形は実行し忘れた環境が穴になるので、依存関係のインストール手順が
# 入ったらその後処理から呼ぶこと。
#
# 失敗しても呼び出し元は止めない。インストールの後処理から呼ぶようになったとき、git の
# 無い環境でインストールごと落とすと、検査のための設定が開発そのものを妨げることになる。
set -uo pipefail

if ! command -v git >/dev/null 2>&1; then
  echo "githooks: git が無いため core.hooksPath の設定を飛ばします" >&2
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "githooks: git リポジトリではないため core.hooksPath の設定を飛ばします" >&2
  exit 0
fi

if ! git config core.hooksPath harness/githooks; then
  echo "githooks: core.hooksPath の設定に失敗しました。手で 'git config core.hooksPath harness/githooks' を実行してください" >&2
  exit 0
fi

echo "githooks: core.hooksPath = harness/githooks"
