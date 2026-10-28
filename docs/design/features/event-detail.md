# 予定の日別アジェンダと詳細

- 種別: 機能設計書
- 対象 UC: UC-001 (docs/design/USECASES.md)

## 何を作るか

月表示で選んだ日の予定を一覧する日別アジェンダと、選んだ予定の詳細を float window で表示する。アジェンダは開始時刻順（終日予定が先頭）に並べ、`j` / `k` で選択、`<CR>` で詳細を開く。詳細は Google カレンダーの予定カード風に、タイトル・日時・場所・ゲスト・説明・Meet URL・カレンダーを表示し、`e`（更新）、`d`（削除）、`y`（Meet URL コピー）、`q`（戻る）の導線を持つ。更新・削除・コピーの実処理は各機能設計書（[event-update.md](event-update.md) / [event-delete.md](event-delete.md) / [meet-url-copy.md](meet-url-copy.md)）が持つ。

## 入出力と振る舞い

**アジェンダ**:

| 操作 | 振る舞い |
| --- | --- |
| 月表示で `<CR>` | 選択日のアジェンダを開く |
| `j` / `k` | 予定の選択を上下に移動する |
| `<CR>` | 選択した予定の詳細を開く |
| `?` | アジェンダのヘルプを開く（[help.md](help.md)） |
| `q` / `<Esc>` | アジェンダを閉じ、月表示に戻る |

- 表示形式は `● HH:MM タイトル`（終日は `● 終日 タイトル`）。予定ごとに色付きのドットを付け、`status == 'tentative'` または `transparency == 'transparent'` の予定は hollow の `○` にする。場所は表示しない
- 予定が 0 件の場合は `予定なし` を表示し、`<CR>` は何もしない
- アジェンダのサイズは `config.agenda.width` / `config.agenda.height`（既定 0.5 / 0.7）を、ボーダーを除く利用可能領域に掛けた値にする。縦長のリストとして表示し、内容が収まらない場合はスクロールする

**詳細**:

| 操作 | 振る舞い |
| --- | --- |
| アジェンダで `<CR>` | 選択した予定の詳細を開く |
| `e` | 更新フォームを開く（[event-update.md](event-update.md)） |
| `d` | 削除確認を開く（[event-delete.md](event-delete.md)） |
| `y` | Meet URL をコピーする（[meet-url-copy.md](meet-url-copy.md)） |
| `g` | ゲスト一覧を折り畳み・展開する |
| `?` | 詳細のヘルプを開く（[help.md](help.md)） |
| `q` / `<Esc>` | 詳細を閉じ、アジェンダに戻る |

- ゲストが 5 人を超える場合は折り畳んだ状態で開き、`g` で展開・折り畳みを切り替える。折り畳み時は人数と参加状況だけを表示し、ヘッダーの `▸` / `▾` で状態を示す。`g` のキーは `config.keymaps.detail.toggle_guests` で変更できる
- 表示は Google カレンダーの予定カード風のセクションにする
  - `▣ タイトル`（カレンダーアイコン + 太字タイトル）
  - `  10月24日 (土曜日)・13:00〜15:00`（日本語の日時。終日は日付のみ）
  - `↗ Meet URL`（存在する場合）
  - `⌖ 場所`
  - `☷ N人のゲスト`、`参加: N人`、`返答待ち: N人`、`仮: N人`、`辞退: N人`
  - ゲストごとに `✓`（参加）/ `○`（返答待ち）/ `?`（仮）/ `✕`（辞退）とメールアドレス。`displayName` があれば次の行に表示し、主催者には `主催者` を付ける
  - `☰ 説明`（幅に合わせて折り返す。最大 10 行、超過分は `…`）
  - `▣ 主催者またはカレンダー`
- 値がない項目はセクションごと省略する（場所が空なら場所セクションを出さない）
- アイコンは `GoogleCalendarDetailIcon`、タイトルは `GoogleCalendarDetailTitle`、補助情報は `GoogleCalendarDetailMuted`、参加状態は `GoogleCalendarDetailAccepted` / `GoogleCalendarDetailPending` / `GoogleCalendarDetailDeclined`、Meet URL は `GoogleCalendarDetailMeet` でハイライトする
- Meet URL は `hangoutLink` を優先し、なければ `conferenceData.entryPoints` の `entryPointType == 'video'` の `uri` を使う
- 詳細のサイズは `config.detail.width` / `config.detail.height`（既定 0.5）を、ボーダーを除く利用可能領域に掛けた値にする。内容が収まらない場合はスクロールする

**データ**:

- アジェンダの予定は `state.events_by_date[selected_date]` から取得する。月表示の取得結果をそのまま使う（追加の API 呼び出しはしない）
- 詳細は選択した予定モデルをそのまま表示する

キーマップは `config.keymaps.agenda` / `config.keymaps.detail` から解決し、`setup()` で上書きできる。アジェンダ・詳細の `q` / `<Esc>` は `agenda.esc_close` / `detail.esc_close` で別々に変更・無効化できる。

## API

該当なし（HTTP API を持たない。`gws` の呼び出し規約は [DESIGN.md](../DESIGN.md)「CLI インターフェース」「既知の制約」参照）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| 日別アジェンダの描画・選択 | UI | `lua/google-calendar/ui/agenda.lua` |
| 予定詳細の描画・操作の導線（`e` / `d` / `y` / `?` のキーマップを含む） | UI | `lua/google-calendar/ui/detail.lua` |
| 予定の表示用整形（時刻・終日・Meet URL・説明の切り詰め） | ドメイン | `lua/google-calendar/event.lua` |
| 選択日の予定一覧の取得 | ドメイン | `lua/google-calendar/state.lua` |
| float の生成・破棄・フォーカス復帰 | UI | `lua/google-calendar/ui/window.lua` |

## エッジケースの決定

- **空・最小データ**: 予定が 0 件の日はアジェンダに `予定なし` を表示し、`<CR>` は無効にする。詳細は開かない
- **上限・境界値**: 予定が 20 件を超える日はアジェンダをスクロール可能にし、`j` / `k` で全件を辿れるようにする。説明が 10 行を超える場合は切り詰める。タイトルが 1 行に収まらない場合は `…` で切り詰める
- **エラー時に利用者へ見えるもの**: 表示済みの予定モデルを使うため、アジェンダ・詳細の表示自体では API エラーは起きない。詳細から更新・削除に進んだ際のエラーは各機能の通知に従う
- **並行操作・二重実行**: アジェンダ・詳細は読み取り専用で、状態を変えない。同時に複数開かない（スタックで 1 つずつ）
- **再表示時の整合**: 月表示の再取得後は、選択日と選択中の予定 ID を維持する。予定が消えている場合はアジェンダを再描画し、詳細を閉じる

## テスト方針

| 受け入れ基準 (docs/design/USECASES.md) | レベル |
| --- | --- |
| （US-004）日を選んで `<CR>` を押すと、その日の予定を開始時刻順に並べた日別アジェンダが開く | 結合 |
| （US-004）日別アジェンダで予定を選んで `<CR>` を押すと、タイトル・日時・場所・ゲスト・説明・Meet URL を含む詳細が開く | 結合 |
| （US-004）ゲストが 5 人を超える場合は折り畳んで表示し、`g` で展開・折り畳みを切り替えられる | 結合 |
| （US-004）詳細で `q` を押すと日別アジェンダに戻り、さらに `q` を押すと月表示に戻る | 結合 |
