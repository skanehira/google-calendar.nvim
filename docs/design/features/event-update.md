# 予定の更新

- 種別: 機能設計書
- 対象 UC: UC-003 (docs/design/USECASES.md)

## 何を作るか

予定の詳細から更新フォームを開き、現在の値を初期値としてタイトル・日時・場所・説明・終日を変更する。変更は `gws calendar events update`（PUT）で送る。`events patch` は終日⇔時刻付きの切り替えで `Invalid start time.` になるため使わない（[FEASIBILITY.md](../FEASIBILITY.md) の PoC `gws-calendar-crud`）。更新前に `events get` で現在の予定を取得し、編集可能なフィールドを保持したまま変更分を上書きする。既存の Meet URL は保持する。

## 入出力と振る舞い

**操作 → 振る舞い**:

| 操作 | 振る舞い |
| --- | --- |
| 詳細で `e` | 現在の値が入力された更新フォームを開く |
| `<Tab>` / `<S-Tab>` | メインウィンドウの次の行 / 前の行へ移動する |
| `<CR>` | タイトル・日時・場所・説明・ゲストのエディタを開く。Meet 行は読み取り専用 |
| `<Space>` | 日時行では終日をトグルする（Meet は変更不可） |
| `:w` | 入力を検証し、変更があれば `gws` で更新する |
| `<Esc>` / `q` | フォームを閉じ、変更を破棄する（`<Esc>` は insert モードでは insert を抜けるだけで、normal モードでキャンセルする。`q` は normal モードのみ） |
| `?` | フォームのヘルプを開く（[help.md](help.md)） |
| エディタで `<CR>` | 日時エディタの選択フィールドを編集する |
| エディタで `:w` | エディタの値をフォームへ適用して閉じる |
| エディタで `<Esc>` / `q` | 値を適用せずにエディタを閉じる |

**フォームの初期値**:

| フィールド | 初期値 |
| --- | --- |
| タイトル | 予定の `summary` |
| 開始 | 予定の `start`（`dateTime` はローカル時刻、`date` は日付） |
| 終了 | 予定の `end` |
| 終日 | `start.date` があれば on、`start.dateTime` があれば off |
| 場所 | 予定の `location` |
| 説明 | 予定の `description` |
| Meet | 読み取り専用（既存の Meet URL を表示。変更・新規作成はしない） |
| ゲスト | 既存の `attendees` のメールアドレス |

説明エディタでは改行を含む複数行の説明を編集できる。変更しなければ `events get` で取得した説明をそのまま送る。

**更新の手順**:

1. フォームの値を検証する（[event-create.md](event-create.md) と同じ規則）
2. 現在の予定を `gws calendar events get --params '{"calendarId":"primary","eventId":"<id>"}'` で取得する
3. 取得した予定の編集可能フィールド（`summary` / `description` / `location` / `start` / `end` / `attendees` / `reminders` / `colorId` / `visibility` / `transparency` / `conferenceData`）を保持し、フォームの変更分で上書きする
4. ゲストを変更した場合は `attendees` を既存の参加情報（`responseStatus` など）を保ったまま差し替える
5. `gws calendar events update --params '{"calendarId":"primary","eventId":"<id>","conferenceDataVersion":1}' --json <body>` を実行する（`conferenceData` がある場合のみ `conferenceDataVersion=1`）
6. 成功時はフォームと詳細を閉じ、月表示を再取得し、`Event updated` と通知する

**変更がない場合**:

- フォームの値が初期値とすべて同じ場合は `gws` を呼ばず、フォームを閉じる

キーマップは `config.keymaps.form` から解決し、`setup()` で上書きできる。保存の既定コマンドは `:w`（`<C-s>` は herdr の prefix と衝突するため使わない）。

## API

該当なし（HTTP API を持たない。`gws` の呼び出し規約は [DESIGN.md](../DESIGN.md)「CLI インターフェース」「既知の制約」参照）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| 更新フォームの描画・入力・検証 | UI | `lua/google-calendar/ui/form.lua` |
| 予定の取得と編集可能フィールドのマージ | ドメイン | `lua/google-calendar/event.lua` |
| `events get` / `events update` の実行（アダプタの `get_event` / `update_event` を呼ぶ） | アダプタ | `lua/google-calendar/gws.lua` |
| 404・API エラーの通知（アダプタの通知を使う） | アダプタ | `lua/google-calendar/notify.lua` |
| 更新後の月表示の再取得 | UI | `lua/google-calendar/ui/month_view.lua`（月表示が `on_changed` コールバックをアジェンダ・詳細経由でフォームへ渡し、フォームが更新後に呼ぶ） |

## エッジケースの決定

- **空・最小データ**: タイトルを空にできない。場所・説明は空にできる（空にした場合は `location` / `description` を空文字で送る）
- **上限・境界値**: タイトル 1024 文字、説明 8192 文字。終日⇔時刻付きの切り替えは `events update` で行う。終日予定の終了日は開始日 + 1 日以上。月をまたぐ変更も扱う
- **エラー時に利用者へ見えるもの**: 検証エラーはフォーム内に表示する。gws のエラーはフォームを閉じずにフッターへ表示し、入力値を保持する。404 の場合は`The event has already been deleted.`と通知し、フォームと詳細を閉じて月表示を再取得する
- **並行操作・二重実行**: 保存中は `:w` を無効化し、`Saving...` を表示する。他者が同時に更新した場合は、`events get` で取得した最新の値をベースにマージする（最後の書き込みが勝つ）
- **再表示時の整合**: 更新後に表示中の月を再取得し、選択日と選択中の予定 ID を維持する。予定が表示範囲外へ移動した場合は、月表示から消える旨を通知に含める

## テスト方針

| 受け入れ基準 (docs/design/USECASES.md) | レベル |
| --- | --- |
| （US-007）予定の詳細で `e` を押すと、現在の値が入力された更新フォームが開く | 結合 |
| （US-007）タイトルを変更して `:w` を押すと、gws 経由で予定が更新され、月表示の該当セルに新しいタイトルが表示される | 結合 |
| （US-007）開始時刻を変更して `:w` を押すと、予定の開始時刻が更新され、月表示の該当セルに反映される | 結合 |
| （US-007）`Esc` を押すと更新フォームが閉じ、予定は変更されない | 結合 |
| （US-007）他者によって削除済みの予定を更新しようとすると、404 のエラーが通知され、月表示が再取得される | 結合 |
| （US-007）更新に失敗した場合、フォームは閉じず、入力値が保持されたままエラーが表示される | 結合 |
| （US-011）終日予定を時刻付き予定に変更して `:w` を押すと、時刻付き予定として更新される | 結合 |
