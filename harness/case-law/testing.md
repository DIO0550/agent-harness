# 判例: テスト

規範は [`rules/testing.md`](../../rules/testing.md)。ここはその実例。

## `test-coverage-gap` — 中心の判断を参照するテストが 1 件も無い

**壊しても全件通る**箇所が実際に何度も出ている。原因はいつも同じで、そのブランチ・その判断を
**参照するテストが 1 件も無い**こと。

| 起きたこと | 規模 |
|---|---|
| 壊しても全件通る箇所が同時に 3 つあった | 1942 件すべて通過 |
| 分岐を丸ごと消しても通った | 2014 件すべて通過 |
| 「選んでいないときも見出しの帯は残す」を壊しても通った | 297 件すべて通過 |
| 帯の型アイコンを消しても通った | 69 件すべて通過 |
| 行き先ごとの `switch` を全部 `some` にしても通った | 1 件も落ちず |
| 「ファイルとドキュメントの両方が不正」を作るテストが無く、優先順位を反転しても通った | 1737 件すべて通過 |

**「1 つ選んで壊す」で終えない。** 独立した判断ごとにすべて壊す。配線・フラグ・別ブランチが
それぞれ別の主張を持つ差分では、1 つだけ確かめると残りが素通りする。

UI で消すもの 6 つ（アイコン / 読み上げ名 / 器 / 状態からの配線 / **出し分け** / 位置・大きさ）は
`.claude/agents/implementation-reviewer.md`「テストが守っているかの観点」にある。

## `test-default-input` — 確かめた入力が既定値と一致していた

規則そのものを壊すミューテーションでも、既定値のほうで結果が変わらず通ってしまう。

| 起きたこと |
|---|
| 「保存済みに戻る」の通しテストが、開いた直後の既定状態だけを見ていた |
| 通しのテストがすべて時計の開始時刻（既定値）を起点にしていた |
| 「複数選んでいる間は部品化できない」の対照を単一側だけ既定値と違えたが、複数側は既定値（インスタンス 2 つ）のままだった |
| 「凍結中でなくても `none` を返す」`removeNode` / `undo` / `redo` / `pasteNode` を、前提（選択・履歴・クリップボード）を用意せずに凍結だけで確かめようとしていた（計画検証で発覚） |

```typescript
// NG: 「ノードから artboard を辿る」規則を確かめたいのに、選んだのが先頭の artboard 配下。
// 辿る側が常に none を返すよう壊しても「選択なしは先頭」の既定で同じ答えになる
EditorState.select(state, "home-title"); // home は 1 枚目
expect(currentName(state)).toBe("home");

// OK: 既定値（先頭 = home）と違う答えになる 2 枚目の配下を選ぶ
EditorState.select(state, "settings-title");
expect(currentName(state)).toBe("settings");
```

## assert が落ちない形

```typescript
// NG: props が名前と回数しか持たないので、実装によらず常に null（絶対に落ちない）
render(<ComponentList refCounts={[{ name: "divider", count: 0 }]} />);
expect(screen.queryByText("Box")).toBeNull();

// OK: 出る側を確かめる（実装が壊れれば落ちる）
expect(screen.getByText("◆")).toBeDefined();
```

```typescript
// NG: gray-900 を指すものが 1 つも無いので、常に空を返す実装でも通る
const document = setupDocument({ title: { color: "gray-500" } });
expect(collect(document, Gray900)).toEqual([]);

// OK: 同じドキュメントに gray-900 を指すノードを 1 件置く
const document = setupDocument({
  plain: {},                      // color 未設定（既定で gray-900 に解決される）
  title: { color: "gray-900" },   // 対照
});
expect(collect(document, Gray900).map(toText)).toEqual(["title.color"]);
```

| NG | OK |
|---|---|
| `expect(queryByRole("combobox", { name: "Shadow", description: "8" })).toBeNull()` — `Shadow` の欄ごと消えても通る | `expect(getByRole("combobox", { name: "Shadow" }).getAttribute("aria-describedby")).toBeNull()` |
| `expect(rows.map((row) => row.textContent)).toEqual(["◆card×0挿入", ...])` — 並び・アイコン・使用数・ボタン文言の 4 つを同時に固定している | 行を一意に指せるラベル（`aria-label` 等）の並びだけを比べる |

「0 件なら枠を出さない」を守りたいなら、行の数ではなく**枠そのもの**を見る
（`queryAllByRole("listitem")` が空 → `queryByRole("list")` が `null`）。

## `duplication-test` — テストヘルパーの重複

`check-test-helper-duplication.sh` が機械判定する。ただし対象は**編集したファイルが絡む・
同じ `__tests__/` フォルダ内・関数本体のみ**で、**定数の重複と `__tests__/` を跨いだ重複は
見ていない**（#179）。差分で複数のテストファイルを触ったら、フックが拾わない範囲を
`implementation-reviewer` が補う。

## テストヘルパーを実装側へ移す前に、assert のほうを疑う

| NG | OK |
|---|---|
| `locations(errors)` が `"home-title.typography"` を組み立て、同じ綴りをドメインへ移して共通化する | `errors.map((e) => e.location)` を `[{ kind: "node", nodeName: "home-title", prop: "typography" }]` と比べる |

ヘルパーが表示のための綴りを組み立てているなら、実装側へ移すと表示の知識がドメインへ入る。
多くの場合テストが見たいのは綴りではなく**構造**で、構造のまま比べればヘルパーごと要らなくなる。

## `duplication-logic` — 判断が要る重複

機械判定できない。差分を見る段でしか捕まらない。

| 起きたこと |
|---|
| 見出しのバッジ・ラベル・強調表示がそれぞれ別の値から同じ事実を導いていた |
| `switch (props.origin)` の 3 枝がそれぞれ器と行を組んでいた |
| `isSelected` を行の器と名前のボタンの両方で計算していた |
