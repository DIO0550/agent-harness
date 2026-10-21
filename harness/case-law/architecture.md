# 判例: アーキテクチャ

規範は [`rules/architecture.md`](../../rules/architecture.md)。ここはその実例。

## `ownership-reasoning` — 帰属の理由が理由になっていない

置き場所自体は合っていても、**理由がその型に固有の性質を指していない**形。
「第 1 引数の型が◯◯だから」だけでは、他の型でも同じ理由が成り立ってしまう。
次に似た値が出たときに、同じ場所へ置いてよいか判断できない。

| NG | OK |
|---|---|
| `TypographyToken.withField(token, { field: "fontFamily", value: "" })` が空文字を「省略」と読む | コントロール側で `raw === "" ? Option.none : Option.some(raw)` に解釈し、ドメインは `Option<string>` を受ける |
| `DocumentErrorLocation.toText(location)` をドメインに置き、`"home-title.typography"` を組み立てる | ドメインは `DocumentErrorLocation` の直和まで。綴りは `document-error-list` の `locationLabel` が持つ |

- **テストが表示の綴りを必要としているように見えたら、まず assert のほうを疑う。**
  「テストのヘルパーが実装の再実装になっている」を理由に綴りをドメインへ移したくなるが、
  多くの場合テストが見たいのは綴りではなく**構造**（どのノードのどの prop か）で、
  構造のまま比べれば綴りを作る必要そのものが消える

## `ownership-by-use` — 使い手の数で置き場所を決めていた

値の規則・部品を「いま使っているのが 1 か所だから」でその場(消費側のファイル内関数・機能の
中のコンポーネント・入力から作る型)に置いた形。design-composer では人のレビューで 3 回、同じ形で
戻された。**使い手の数は置き場所の理由にならない。** 見るのは「その規則・部品は誰の性質か」で、
使い手が 1 つでも、持ち主が別にあるなら持ち主へ置く。

| NG | OK |
|---|---|
| ある値の判定を別の層の関数に置き、別の機能がそれを借りていた | その値の型を作って判定を移す |
| 一般概念(角度そのもの)を、ファイル上の綴りから作る型が兼ねていた | 一般概念の型を新設し、綴りから作る型は変換だけを持つ |
| ドメイン知識を持たない部品を、使い手が 1 つなので使う側のファイル内に置いた | 汎用部品の置き場へ置き、出し分けは列挙で受ける |

- 判定の分かれ目: **ドメイン知識を持たないなら横断層、値の規則なら値の型。** 「使うのはここだけ」
  と書いた理由は、持ち主を探した結果ではなく探さなかった印
- 一般概念と「ファイルに書かれる綴り」を 1 つの型が兼ねていたら、兼ねている型を割る
- 計画に「置き場所: ◯◯(使い手が 1 つなので)」と書いたら、`ownership-reasoning` と同じく
  他の型にも成り立つ理由になっていないかを先に確かめる

## `service-placement` — services に置く前にドメインを探していない

「複数ドメインに跨る」という感触だけを根拠に `services/` へ置いた形。過去のレビューで
services に置かれたロジックの多くは、`rules/architecture.md` の 1〜6 で帰属先が見つかっている。

- 対を表す型を作って帰属させた例: `TypographyFieldRef` / `Padding`
- ドメインが出力形式を必要とする場合は、変換手段を**引数で受け取る**ことで依存方向を保ったまま
  ドメインに置ける

  ```typescript
  // domains/padding — カスタムプロパティ名の綴り方（出力層の知識）は引数で受け取る
  declarations(padding: Padding, resolveToken: (token: string) => string): readonly CssDeclaration[]
  ```

## `utils-form` — utils の名前が用途を指している

| NG | OK | 理由 |
|---|---|---|
| `StringEx.toLabel(prop)` | `CaseStyle.toCapitalCase(prop)` | 「ラベル」は表示という**用途**。「camelCase を Capital Case にする」は用途に依らない**操作** |

- 汎用の操作が 1 つだけでも、`<型名>Ex` に押し込めず**まとまりを表すモジュール**を立てる
  （綴りの流儀の変換なら `CaseStyle`）
- 型で閉じた対応表（`as const satisfies` でリテラル型を保つもの）を汎用変換に置き換えない。
  戻り値が `string` へ広がり、網羅性の保証が失われる（`TypographyField.cssProperty` を
  `toKebabCase()` にしない）
- ドメイン概念になった時点で `utils/` から `domains/` へ移す。規則を持つ `Px` は `domains/px/`、
  文字列定数だけの `Font` は `utils/`

## `domain-scope-promotion` — 置き場所を消費する feature の数で決めていない

1 feature でしか使わないのに `src/domains/` へ置く / 2 つ以上の feature が必要なのに
`features/<x>/domains/` に留める。どちらの向きにも出る。
