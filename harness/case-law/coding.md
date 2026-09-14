# 判例: コーディング

規範は [`rules/coding.md`](../../rules/coding.md)。ここはその実例。

## `type-vocabulary` — 語彙が `string` のまま残る

| NG | OK |
|---|---|
| `/** rgb は6桁の hex であることを呼び出し側が保証する */`<br>`withRgb(color: ColorToken, rgb: string)` | `` type Rgb = `#${string}` `` を立て、生成を `Rgb.create(value): Option<Rgb>` に閉じてから `withRgb(color: ColorToken, rgb: Rgb)` |
| `AXES.width` | `Axes.Width` |
| `DOCUMENT_ERROR_ORIGINS.openedFile` | `DocumentErrorOrigins.OpenedFile` |

- **既にある型エイリアスへ付け替えるだけでは閉じられない。** `ColorToken = string` のように
  構造が `string` のままの型に付け替えても、素の `string` がそのまま代入できる。
  テンプレートリテラル型で構造を狭めて初めて代入が弾かれる
- **キーの型が union そのものだと、キーを PascalCase にした時点で `satisfies` が落ちる。**
  `Capitalize` を通して過不足の検査を残す（`LeftPaneViews` が
  `Readonly<Record<Capitalize<LeftPaneView>, LeftPaneView>>`）。行き先の id にハイフンや
  複数語が入ると `Capitalize<"left-pane">` = `"Left-pane"` を型が要求するので、
  そのときはキーの綴りを別に持つ
- スキーマなど既にある定数から導出する場合は出どころの形に従う（`CssDirection` が
  `BoxSchema.props.direction.values` から引く）
- 既存の `TokenKinds` / `TypographyFields` / `PrimitiveTypes` は配列 + `(typeof X)[number]` の
  まま（#105 で寄せる）

## `illegal-state` — 不正な状態が型で作れてしまう

計画検証・実装検証で 1 つずつ当てる形。繰り返し出ている。

- **辞書引きの「まだ無い」と「0」が同じ顔になる。** `Record<string, number>` をキーで引くと、
  定義の無いキーも型上 `number` になる（`noUncheckedIndexedAccess` が無いため）。
  区別したいなら `(名前, 値)` の並びにする
- **出し分けの最後の枝がラベルの無い受け皿になる。** `if` の連なり・nested ternary の最後の
  分岐は、行き先を足し忘れても黙って通る。`switch` を `default` 無しで書き、戻り値の型を
  `ReactNode` ではなく `ReactElement` にする
- **`as const` から union を export するのに `satisfies` と型テストが無い。** 隣接する既存の
  語彙（`TypographyFields` 等）と縛り方を揃える
- **本来届かないはずの `Option.none` / 分岐を作る。** `findX` → `findY` のような多段の参照は、
  途中の `none` が「起こり得ないのに UI が持つ枝」になる。1 段で引ける型・既存の公開 API を先に探す
- **構造が変わらない型エイリアスを新設する**（`type A = B`）
- **同じ位置づけの既存の型が `Option` で表しているものを、そこだけ空配列 / 既定値へ潰す。**
  隣の型と揃っているかを見る
- **1 つの型に、本来直交する状態が同居する。** ある枝でしか意味を持たないフィールド
  （色トークンにしか無い swatch 等）を共通の親に持たせない

### ブランド型

```typescript
declare const FontWeightBrand: unique symbol;
export type FontWeight = Brand<number, typeof FontWeightBrand>;

export const FontWeight = {
  create(value: number): Option<FontWeight> {
    return Range.contains(FontWeightRange, value)
      ? Option.some(value as FontWeight)
      : Option.none;
  },
} as const;
```

- **目印の `unique symbol` は使う側で宣言する。** `unique symbol` は宣言した場所ごとに別の型に
  なるので、目印まで `Brand` の中へ書くとそこから作った型がすべて同じ目印を共有し、
  取り違えを弾けなくなる
- **同じ制約を持つ値を 1 つの型にまとめない。** `blur` と `spacing` はどちらも「0 以上の px」
  だが、まとめると片方をもう片方へ渡せてしまい、ブランドを入れた目的が消える
- **同じ制約の型が 2 つ以上あるなら、互いに代入できないことを `expectTypeOf` で固定する。**
  検証が同じだと実装を 1 つに畳んでも `tsc` もテストも通ってしまう（`FontSize` と `LineHeight`
  が実際にこれで、レビューまで気づかなかった / #143）

### 処理の通過を型に刻む

```typescript
// スキーマでデフォルトを持つ prop のキーが「必ず存在する」ことが構造に現れる
type DefaultedKeys<P extends PropDefinitionRecord> = {
  [K in keyof P]: P[K] extends { default: PropValue } ? K : never;
}[keyof P];

export type ResolvedProps<T extends PrimitiveType> = Props &
  Readonly<Record<DefaultedKeys<SchemaPropsOf<T>>, PropValue>>;

// 消費側は解決済みであることを型で要求する。未解決の Props は必須キー欠落でコンパイルエラー
function compile(props: ResolvedProps<"Box">): Style { /* ... */ }
```

## `comment-false-claim` — 主張を確かめずに書いた

書いた時点では**もっともらしく読める**ので、確かめない限り残る。

| 主張の形 | 確かめ方 | 実例 |
|---|---|---|
| この class / 属性が◯◯を防ぐ | 外した状態を実際に作って見る | `shrink-0` は守る対象を取り違えた上に実質 no-op（縮まないのは `min-width:auto` のため） |
| あの型は◯◯できない | できると書いてあるコードを探す | 「影・タイポは 1 つの値に畳めない」→ `token-control` の `valueTextOf` が実際に畳んでいた |
| この枝は値域付きの型しか持てない | 同じ差分の型テストを先に開く | `x` / `y` / `spread` は素の `number` のままなのに「値域付きの型しか持てないので」と書き、同じ差分の `shadow.type.test.ts` と矛盾していた |
| この API / フックはこう振る舞う | 公式ドキュメント・型定義を実際に読む | 「ref は render 中に読めない」と書いたが読めてしまう（React が推奨しないだけ） |
| この経路はまれにしか通らない | その経路に実際に到達する入力でコードを追う | 「巻き戻る状況でしか負にならない」と書いたが、mount 時 1 度だけ初期化される `now` により通常経路で毎回踏んでいた |

## `comment-stale-edit` — 一部だけ直して終えた

**この判断は pr-305 で更新された。** `comment-stale-edit` は
`comment-referent-drift` / `comment-enumeration-drift` / `comment-premise-drift` /
`comment-block-placement` へ分割し、下の実例もそれぞれの節へ引き継いだ。以降は
1 件しか出ていない単発の形だけがこのタグに残る。

| 記述の組 | 実例 |
|---|---|
| コメントが手法を説明している | `switch` と書いたまま実装が対応表になっていた |
| 挙動を説明する記述が 2 箇所以上 | `@returns` は更新したのに、ゴールそのものを書いた唯一の箇所（呼び出し側のコメント）が元のまま |
| 削除・改名したシンボル名がコメントに残る | `isWithin` を `Range.contains` へ移した同じ PR で、`Brand.ts` の `@example` だけ古い名前を指したまま（typecheck も lint も落ちない） |

## `comment-referent-drift` — 名指しした先が同じ差分でずれた

| ずれ方 | 実例 |
|---|---|
| `@param` の名前が実引数名と不一致 | `rowsOf` の doc に `@param editables` と書いたが仮引数は `enabled`。`@param props` の説明も判定を済ませている呼び出し側 `sectionsOf` の doc をコピーしたまま残っていた |
| 移設・シグネチャ変更後も doc が旧層の型を根拠にしたまま | 上位層へ移した doc が、移動後の層からは参照できない型を名指ししたまま残っていた |

## `comment-enumeration-drift` — 列挙・件数が同じ差分の増減に追随しなかった

| ずれ方 | 実例 |
|---|---|
| 見出し項目を増やしたのに後続の件数表現が追随しない | `.claude/hooks/README.md` の「doc コメントとテスト規約は CI へ上げた」に import 規約を挿し込んで 3 項目にしたのに、後続の「この 2 つは層 2・層 3 にしか無かった」がそのまま残り、指す先が壊れた |

## `comment-premise-drift` — Why / Why not の前提が同じ差分で崩れた

| ずれ方 | 実例 |
|---|---|
| 分岐が無くなったのに、分岐由来の理由が残る | `PropertyPanelTitle` の doc に「`case` を足し忘れたときにコンパイルエラーにするため `ReactElement` と書いている」が残っていたが、この関数に `switch` は無く（`if` + 三項）、戻り値も `ReactElement \| null` で理屈が効かなくなっていた |
| 実装を対へ移した後もコメントが元の場所に逐語で残る | 実装をペアの型へ移したのに、Why / Why not をほぼ逐語のまま元の場所にも残し、二重管理になっていた |

## `comment-block-placement` — doc の付着・行幅が機械的にずれた

| ずれ方 | 実例 |
|---|---|
| 隣接する `/** */` ブロックが同じ宣言に付く | メソッドを足す編集の途中で doc ブロックの位置がずれ、`sourceName` が doc を 2 つ重ねて持ち、`selectAllInstances` は doc 無しになっていた。**typecheck も lint も `check-doc-comments.sh` も落ちない**（`missing-doc-comments.py` は入れ子の宣言を対象外にしているため） |
| ファイル全体の doc が直後の宣言の doc に隣接する | テストファイル冒頭の `/**` ブロックが直後の `editor()` の doc に隣接し、ツール上は両方が `editor()` に付く形になっていた。このリポジトリには `/*`（アスタリスク 1 つ）で書き分けて宣言に付けない前例が既にある |

## `comment-missing` — 書くべき Why / Why not が無い

- **経緯を Issue の見出し番号だけで指す**（`// #183 の決定 B のため`）。番号はコードだけを読む
  人には何も伝わらない。理由そのものをその場に書く
- **却下しなかった非自明な選択に Why が無い。** `pressPointer` に `userEvent` を使わない理由が
  無く、レビューで聞かれて初めて書いた

## doc の形

```typescript
/**
 * 指す 1 つを取り除いたトークン一式。
 *
 * @param tokens 取り除く前のトークン一式
 * @param ref 取り除くトークンの種別と名前
 * @returns 指したトークンを除いた新しい一式。元の一式は変えない
 */
function withoutToken(tokens: TokenSet, ref: TokenRef): TokenSet { /* ... */ }
```

## 名前を付けてから結合する

```typescript
// NG: 何をどこから集めているか名前が無い
return [
  ...withLocation({ nodeName: artboard.name }, PropDefinitionRecord.collectErrors(/* ... */)),
  ...artboard.children.flatMap((child) => collectNodeErrors(child, context.tokens)),
  ...artboard.children.flatMap((child) => collectNodeRefErrors(context, child)),
];

// OK: 一旦名前を付けてから結合する
const propErrors = withLocation(/* ... */);
const childErrors = artboard.children.flatMap(/* ... */);
const refErrors = artboard.children.flatMap(/* ... */);
return [...propErrors, ...childErrors, ...refErrors];
```

## 消すコメントの見分け

| 消すもの | 例 |
|---|---|
| What の言い換え | `// キャンバスの下端に浮かべる` の隣に `absolute bottom-4` |
| コード内の値の再掲 | `（UI 案の 36×32 / border-radius:6px）` の隣に `h-8 w-9 rounded-md` |
| 経緯・実行履歴 | 「実際にアイコンを消して 703 件すべて通ることを確かめた」 |
| Issue の見出し番号だけを指す | `// #183 の決定 B のため` |
| 一般論 | 「アイコンだけのボタンなので読み上げ名が要る」 |

**消してはいけない Why**: 型やテストで表現できず、外すと壊れるのに壊れたことに気づけないもの
（「この `relative` を外すと浮くものが全部ずれるが、テストでは落ちない」）。
