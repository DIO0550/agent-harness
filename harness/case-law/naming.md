# 判例: 命名

規範は [`rules/naming.md`](../../rules/naming.md)。ここはその実例。

## `naming-precedent` — その語がリポジトリの他の場所で既に別の意味を持っていた

`rules/naming.md`「名前と実体を一致させる」「内容を表さない汎用語を使わない」は既に書かれて
いるが、**書いた時点では気づかれず、すべてレビューで指摘されてから直っている**。だから
`implementation-reviewer` が grep で確かめる観点として持っている。

| 起きたこと | 何が衝突したか |
|---|---|
| `Document*` の接頭辞を付けた | 既存の `Document*` が指す対象からはみ出していた |
| 他ツールの慣習名 `install` を借りた | このリポジトリで**何を install するか**を言えなかった（`set-hooks-path` が実体） |
| 比喩 `Legend` を使った | UI 案にも仕様書にも `grep -i` で 0 回。このリポジトリの語彙に無い |

確かめ方は 3 つ。

1. **接頭辞・語幹を grep する。** 同じ接頭辞を持つ既存モジュールが指している対象と一致するか
2. **借用した慣習名は、このリポジトリの文脈で何を指すかを言えるか**
3. **比喩・抽象語は `docs/06-ui.md` と `docs/Design Composer.html` に `grep -i` で数える**

## 名前と実体を一致させる

| NG | OK | 理由 |
|---|---|---|
| `validateNode(node)` | `collectNodeErrors(node)` | エラー配列を返すだけで、検証の成否は返さない |
| `locate(location, errors)` | `withLocation(location, errors)` | 何も探していない。位置を付与している |
| `PropDefinition.validate` | `PropDefinition.collectErrors` | 公開 API も例外にしない |

## 条件を組んだ式に名前を付ける

| NG | OK |
|---|---|
| `{hasChildren && isExpanded ? <NodeList /> : null}` | `const showsChildren = hasChildren && isExpanded;` を経由する |
| `if (key === e.key && ctrl === e.ctrlKey && shift === e.shiftKey)` | 条件ごとに変数へ分け、最後に連言にする |

**条件が 2 つ以上要る理由がコードから読み取れないなら、変数のそばにコメントで残す。**
「子を持たない行は畳めないので `isExpanded` が常に true になり、それだけでは空の `<ul>` が出る」
のように、片方を削れない理由を書く。

## 汎用語で名前が付かないのは役割が 2 つあるサイン

「名前空間の構成要素」と「エラー報告用の位置」を 1 つの型に持たせていたため名前が付かなかった
→ 役割を分けたら**その型自体が不要になった**。

## `naming-vocabulary-gap` — 対応表のキーをどう綴るか

**キーが値の別名になっている定数**（`Axes` / `LeftPaneViews` / `DocumentErrorOrigins`）は
キーも PascalCase。それ以外は据え置く。

| キーが何か | 例 | 据え置く理由 |
|---|---|---|
| union の値を引く見出し | `LeftPaneViewLabels[view]` / `KindLabels` | 引くたびに実行時の capitalize が要る |
| 外部フォーマットのキー | `BoxSchema.props.direction` | `docs/01-file-format.md` の JSON キーそのもの |
| 型が決めているキー | `PanelBounds.left` / `Padding.x` | 型のフィールド名なので、綴りを選ぶ余地が無い |
| 表示文字列・フィクスチャの見出し | `Labels.instance` / `SaveStates.saved` | 値が別のもの（表示文字列・オブジェクト）で、キーの語彙ではない |

判断の仕方: **その値は語彙そのものか、別のものか。** 値が id や union の値そのもの
（`Axes` の `"width"`）ならキーは値の別名なので PascalCase。値が表示文字列・オブジェクト・
クラス名など**別のもの**なら、たまたま綴りが一致していても（`LeftPaneViewLabels.layers` は
`"Layers"`）見出しなので据え置く。

**「キーを値へ置き換えても意味が変わらないか」で判断しない。** `LeftPaneViewLabels` のように
キーと値が大小文字しか違わない対応表で、逆の答えが出る（この判定文が実際に規約へ入り、
規約自身が挙げている例で逆の答えを出した → `process.md` の `rules-consistency`）。

## `utils/` のメソッドは動詞で始める

| NG | OK | 理由 |
|---|---|---|
| `ArrayEx.withPrepended(array, item)` | `ArrayEx.prependIfAbsent(array, item)` | `ArrayEx` に `with*` は 1 つも無く語形が浮く。「含まれていなければ先頭へ足す」という実体も名前に出ていない |
| `ArrayEx.prependDistinct(array, item)` | 同上 | 「重複を取り除いて足す」と読めるが、元の並びにある重複は畳まない |

既存の語形: `first` / `last` / `dropFirst` / `dropLast` / `distinct` / `insertAt` /
`replaceAt` / `moveWithin` / `toggle` / `isNatural`。

`with*` はドメイン側の語彙（`ColorToken.withRgb` / `withLocation`）。

## ファイル名

- `resolve-prop-definition.ts` のような**関数名のファイル名**は付けない
- `use-editor-reducer` / `use-xxx-context` のような**React の API 名**をモジュール名にしない。
  器を差し替えたら名前が嘘になる。状態を持つなら `use-editor-state`
