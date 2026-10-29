# Meet URL のコピー

- 種別: 機能設計書
- 対象 UC: UC-007 (docs/design/USECASES.md)

## 何を作るか

予定の詳細で `y` を押すと、その予定の Google Meet URL をシステムクリップボード（`+` レジスタ）へコピーし、コピーした旨を通知する。Meet URL がない予定ではコピーせず、その旨を通知する。クリップボードが使えない環境では失敗を通知し、URL を通知本文に含める。

## 入出力と振る舞い

**操作 → 振る舞い**:

| 操作 | 振る舞い |
| --- | --- |
| 詳細で `y` | Meet URL を `+` レジスタへコピーし、`Meet URL copied: <URL>` と通知する |
| 詳細で `y`（Meet URL なし） | `This event has no Meet URL` と通知する |
| 詳細で `y`（クリップボード不可） | `Could not copy to clipboard: <URL>` と通知する |

**URL の取得**:

1. 予定モデルの `hangout_link` を使う
2. なければ `conferenceData.entryPoints` から `entryPointType == 'video'` の `uri` を使う
3. どちらもなければ Meet URL なしとして扱う

**コピー**:

- クリップボードへの書き込みは `config.clipboard(url)` で注入可能にする。既定は `vim.fn.setreg('+', url)` を使い、シェルを介さない
- `vim.fn.has('clipboard') == 0` の場合はコピーせず、失敗を通知して URL を本文に含める
- `setreg` が失敗した場合は `pcall` で検出し、通知に URL を含める
- 成功時は `vim.notify(..., vim.log.levels.INFO)` で 1 行だけ出す

## API

該当なし（HTTP API を持たない）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| `y` のキー処理と通知 | UI | `lua/google-calendar/ui/detail.lua` |
| Meet URL の抽出（`hangoutLink` / `conferenceData`） | ドメイン | `lua/google-calendar/event.lua` |
| クリップボードへの書き込み（`config.clipboard` で注入可能） | UI | `lua/google-calendar/ui/detail.lua` / `config.lua` |

## エッジケースの決定

- **空・最小データ**: Meet URL がない予定ではコピーしない。空文字の URL も「なし」として扱う
- **上限・境界値**: URL が長い場合は通知内で切り詰めるが、コピーする値は完全な URL とする。クエリパラメータを含む URL もそのままコピーする
- **エラー時に利用者へ見えるもの**: クリップボードが使えない場合は失敗を通知し、URL を本文に含める（手動でコピーできるようにする）
- **並行操作・二重実行**: `y` の連打は同じ URL をコピーするだけで、状態を変えない
- **再表示時の整合**: 予定が更新されて Meet URL が変わった場合は、詳細を開き直したときに新しい URL をコピーする。更新で Meet URL は変更しない（[event-update.md](event-update.md)）

## テスト方針

| 受け入れ基準 (docs/design/USECASES.md) | レベル |
| --- | --- |
| （US-012）Meet URL を持つ予定の詳細で `y` を押すと、URL がクリップボードにコピーされ、コピーした旨の通知が出る | 結合 |
| （US-012）Meet URL を持たない予定の詳細で `y` を押すと、コピーできない旨の通知が出る | 単体 |
| （US-012）クリップボードが利用できない環境で `y` を押すと、失敗した旨と URL を含む通知が出る | 単体 |
