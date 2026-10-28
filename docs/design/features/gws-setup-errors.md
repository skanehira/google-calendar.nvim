# gws のセットアップ不備とエラー処理

- 種別: 機能設計書
- 対象 UC: UC-005 (docs/design/USECASES.md)

## 何を作るか

`gws` の未インストール・未認証・API エラー・ネットワークエラーを判別し、原因と対処を含む通知を出す。エラー処理はすべて非同期で行い、Neovim の操作をブロックしない。月表示を開けない場合も Neovim は通常どおり操作できる。

## 入出力と振る舞い

**エラー分類**:

| 種別 | 判定 | 通知文言（案） | 後続の動作 |
| --- | --- | --- | --- |
| 未インストール | `vim.fn.executable(gws_cmd) == 0`、または `pcall(vim.system, ...)` の失敗（ENOENT） | `gws が見つかりません。README のセットアップ手順に従って gws をインストールしてください。` | 月表示を開かない |
| 未認証 | 終了コード 2 かつ stdout の `error.reason == 'authError'` | `gws の認証が切れています。gws auth login を実行してください。` | 月表示を開かない。既存の表示があれば維持する |
| API エラー | 上記以外の非 0 で `error` を持つ | `Google Calendar API エラー: <error.message>` | 既存の表示を維持する |
| ネットワーク | `vim.system` のタイムアウト / 接続失敗 | `Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。` | 既存の表示を維持する |
| 404 | 終了コード非 0 で `error.code == 404` | `予定が既に削除されています。` | 月表示を再取得する |

**表示**:

- `vim.notify(msg, vim.log.levels.ERROR)` を使う。成功時は `INFO` で 1 行だけ出す
- 通知は 1 回の失敗につき 1 件とし、同じエラーを連続で出さない
- エラー時もキー操作（`q` で閉じる、`r` で再試行する）は受け付ける

**起動時の確認**:

- `:GoogleCalendar` の実行時に `vim.fn.executable(gws_cmd)` で `gws` の存在を確認する。存在しない場合は `events.list` を呼ばずに未インストールの通知を出す。`vim.system` は実行ファイル不在時に ENOENT を raise するため、呼び出しは `pcall` で包む
- 存在する場合は `events.list` を呼び、認証エラーを分類する

## API

該当なし（HTTP API を持たない。`gws` の呼び出し規約は [DESIGN.md](../DESIGN.md)「CLI インターフェース」「既知の制約」参照）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| エラー種別ごとの通知文言と `vim.notify` | アダプタ | `lua/google-calendar/notify.lua` |
| gws の実行結果（終了コード・stdout・stderr）の分類 | アダプタ | `lua/google-calendar/gws.lua` |
| 起動時の gws 存在確認と分岐 | エントリポイント | `lua/google-calendar/init.lua` |

## エッジケースの決定

- **空・最小データ**: stdout が空、または JSON として解釈できない場合は「gws の出力を解釈できませんでした」と通知し、生の stderr を `DEBUG` で残す
- **上限・境界値**: API エラーの `error.message` が長い場合は画面幅（`columns`）に切り詰め、全文は `DEBUG` で `:messages` に残す。固定文言（未インストール・未認証・ネットワーク・出力不正）は切り詰めない
- **エラー時に利用者へ見えるもの**: 未インストール・未認証は対処（インストール / `gws auth login`）を含める。API エラーは `error.message` を含める。ネットワークエラーは再試行のキー（`r`）を案内する
- **並行操作・二重実行**: 同じエラーが連続した場合は 1 回だけ通知する。確認中に別のエラーが起きても、最後のエラーだけを表示する
- **再表示時の整合**: 認証をやり直したあとに `:GoogleCalendar` または `r` を実行すると、通常の取得に戻る

## テスト方針

| 受け入れ基準 (docs/design/USECASES.md) | レベル |
| --- | --- |
| （US-009）gws が PATH にない状態で `:GoogleCalendar` を実行すると、gws が見つからない旨と導入方法を含む通知が出る | 単体 |
| （US-009）gws の認証が切れている状態で `:GoogleCalendar` を実行すると、`gws auth login` を促す通知が出る | 単体 |
| （US-009）gws が API エラーを返したとき、エラー内容を含む通知が出て、Neovim の操作がブロックされない | 結合 |
