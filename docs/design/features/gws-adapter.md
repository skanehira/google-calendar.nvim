# gws アダプタ

- 種別: 機能設計書
- 対象 UC: なし (基盤)

## 何を作るか

`gws` コマンドを `vim.system` で非同期に実行し、Google Calendar の予定一覧・作成・取得・更新・削除を提供する共通アダプタ。JSON の解析、`nextPageToken` によるページ取得、終了コードとエラー JSON の分類、`cwd` の設定（`download.html` の副作用回避）、タイムアウトを担う。UI 層はこのアダプタだけを通して `gws` を呼ぶ。

## 入出力と振る舞い

**提供する関数**:

| 関数 | 引数 | 戻り値（コールバック） | 対応する gws |
| --- | --- | --- | --- |
| `list_events(opts, cb)` | `calendar_id`, `time_min`, `time_max` | `events[]` / `error` | `calendar events list`（ページ取得） |
| `create_event(event, cb)` | `summary`, `start`, `end`, `location`, `description`, `meet`, `all_day` | `event` / `error` | `calendar +insert` または `calendar events insert` |
| `get_event(id, cb)` | `event_id` | `event` / `error` | `calendar events get` |
| `update_event(event, cb)` | 予定モデル全体 | `event` / `error` | `calendar events update` |
| `delete_event(id, cb)` | `event_id` | `ok` / `error` | `calendar events delete` |

**共通の実行規則**:

- argv の配列で `vim.system` に渡し、シェルを介さない
- `--format json` を付ける。stdout だけを `vim.json.decode` する（stderr は診断用）
- `cwd` は `vim.fn.stdpath('cache') .. '/google-calendar.nvim'`。ディレクトリが無ければ `vim.fn.mkdir(dir, 'p')` で作る
- タイムアウトは 30 秒。`vim.system` の `timeout` を使う
- 1 つのリクエストにつき 1 回だけコールバックを呼ぶ
- コールバックは `cb(value, err)` の形で呼ぶ。成功時は `err == nil`、失敗時は `value == nil`
- `events list` の `--params` には `calendarId` / `timeMin` / `timeMax` に加えて `singleEvents=true` と `maxResults=2500` を入れる
- ページ取得は `nextPageToken` がある限り `pageToken` を付けて再実行し、`items` を結合する。`vim.NIL` は終端として扱う。10 ページを超える場合は 10 ページで打ち切り、`vim.log.levels.WARN` で警告を出して取得済みの `items` を返す

**エラー分類**:

| 条件 | 分類 | 返す情報 |
| --- | --- | --- |
| `vim.fn.executable(gws_cmd) == 0`、または `pcall(vim.system, ...)` の失敗（ENOENT） | `not_found` | 実行ファイル不在の情報 |
| 終了コード 2 かつ `error.reason == 'authError'` | `auth` | `error.message` |
| 終了コード非 0 で `error` を持つ | `api` | `error.code`, `error.message`, `error.reason` |
| 終了コード 0 だが stdout が JSON でない | `invalid_output` | stdout の先頭 200 文字 |
| タイムアウト | `network` | `timeout` |

エラーは `{ kind = '<分類>', ... }` の形で返す。`kind` は `not_found` / `auth` / `api` / `invalid_output` / `network`。分類ごとの追加キーは `command`（not_found）、`message`（auth / network）、`code` / `reason`（api）、`output` / `stderr`（invalid_output）。

**予定モデルへの正規化**:

- `id`, `summary`, `location`, `description`, `start`, `end`, `hangout_link`, `calendar_id`, `status`
- `start` / `end` は `{ date = 'YYYY-MM-DD' }` または `{ dateTime = 'RFC3339', timeZone = '...' }`
- `hangout_link` は `hangoutLink`、なければ `conferenceData.entryPoints` の `entryPointType == 'video'` の `uri`
- `dateTime` はローカル時刻へ変換して表示用の値を持たせる（変換式は [DESIGN.md](../DESIGN.md)「横断規約」）
- 更新時に保持する API フィールド（`attendees` / `reminders` / `colorId` / `visibility` / `transparency` / `conferenceData`）は、応答に存在する場合だけモデルへ引き継ぐ（[DESIGN.md](../DESIGN.md)「既知の制約」）

## API

該当なし（HTTP API を持たない。`gws` の呼び出し規約は [DESIGN.md](../DESIGN.md)「CLI インターフェース」「既知の制約」参照）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| `vim.system` による gws 実行、ページ取得、エラー分類 | アダプタ | `lua/google-calendar/gws.lua` |
| 予定 JSON の正規化、Meet URL の抽出、日時変換、更新リクエストボディの組み立て（編集可能フィールドの保持） | ドメイン | `lua/google-calendar/event.lua` |
| エラー種別ごとの通知 | アダプタ | `lua/google-calendar/notify.lua` |

## エッジケースの決定

- **空・最小データ**: `items` が無い応答は 0 件として扱う。`error` が無い非 0 は `invalid_output` とする
- **実行ファイル不在**: `vim.system` は ENOENT を raise するため、呼び出し前に `vim.fn.executable(gws_cmd)` を確認し、`pcall` で包む
- **上限・境界値**: `maxResults=2500` を上限とし、ページ取得で全件を集める。ページ数が 10 を超える場合は打ち切り、警告を出す
- **エラー時に利用者へ見えるもの**: 分類に応じた通知を出す（[gws-setup-errors.md](gws-setup-errors.md)）。呼び出し元には `error` を返し、UI がフォームを閉じないなどの分岐に使う
- **並行操作・二重実行**: 同じ予定に対する同時更新は最後の書き込みが勝つ。アダプタ自体はリクエストをキューしない（UI 層が 1 リクエストに制限する）
- **再表示時の整合**: 取得結果は毎回新しいモデルとして返す。キャッシュは UI 層の `state` が持つ

## テスト方針

| 確かめること (タスク説明から起こした) | レベル |
| --- | --- |
| `gws calendar events list` の JSON から予定モデルを組み立て、`nextPageToken` がある限りページを取得して `items` を結合する | 単体 |
| 終了コード 2 かつ `error.reason == 'authError'` の応答を認証エラーとして分類する | 単体 |
| `gws` が見つからないときに未インストールとして分類する | 単体 |
| `gws calendar events delete` をキャッシュディレクトリで実行し、偽 gws の cwd ログがキャッシュディレクトリであることを assert する（リポジトリに `download.html` を残さない） | 結合 |
| `dateTime` をローカル時刻へ変換し、終日予定は `date` のまま扱う | 単体 |
| `calendar +insert --meet` の応答から `hangoutLink` を取り出す | 結合 |
| `nextPageToken` が `null`（`vim.NIL`）のときにページ取得を終了する | 単体 |
