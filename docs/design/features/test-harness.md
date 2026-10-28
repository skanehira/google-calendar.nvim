# テストハーネス（偽 gws と fixture）

- 種別: 機能設計書
- 対象 UC: なし (基盤)

## 何を作るか

実カレンダーを変更せずに予定の CRUD を検証するための偽 `gws` と、テスト用の fixture・実行スクリプトを提供する。偽 `gws` は状態ファイル（JSON）を持ち、`events list` / `+insert` / `events get` / `events update` / `events delete` / `calendarList list` を再現する。E2E の CRUD シナリオ自体は [e2e-crud.md](e2e-crud.md) が持つ。

## 入出力と振る舞い

**偽 gws**:

| 引数 | 振る舞い |
| --- | --- |
| `calendar events list --params <JSON>` | 状態ファイルの予定を `timeMin` / `timeMax` で絞り、`items` を返す。`pageToken` があれば次ページを返す |
| `calendar +insert ...` | 状態ファイルに予定を追加し、`id` と `hangoutLink`（`--meet` 時）を返す |
| `calendar events insert --params <JSON> --json <JSON>` | 状態ファイルに終日予定を追加し、`id` を返す |
| `calendar events get --params <JSON>` | 指定 ID の予定を返す。無ければ 404 のエラー JSON を返す |
| `calendar events update --params <JSON> --json <JSON>` | 予定を置換して返す |
| `calendar events delete --params <JSON>` | 予定を削除し、`{"status":"success"}` を返す。cwd に 0 バイトの `download.html` を生成し、cwd を `FAKE_GWS_CWD_LOG` に記録する |
| `calendar calendarList list` | primary カレンダーの 1 件を返す |

- 状態ファイルのパスは環境変数 `FAKE_GWS_STATE` で指定する。未指定なら一時ディレクトリの `google-calendar-fake-gws-state.json` を使う
- 状態ファイルの形式は `{"items": [...]}`。`events list` は絞り込んだ `items` を返す
- ページ取得のページサイズは環境変数 `FAKE_GWS_PAGE_SIZE` で指定する（既定 2500）。`pageToken` は次ページの開始オフセットを表す文字列
- 環境変数 `FAKE_GWS_ERROR_FIXTURE` にエラー fixture のパスを指定すると、その JSON を stdout に出して終了する。`error.reason` が `authError` なら終了コード 2、それ以外は 1
- 環境変数 `FAKE_GWS_CALL_LOG` にパスを指定すると、呼び出しごとに `{"argv": [...], "cwd": "..."}` を 1 行ずつ追記する（二重送信の検証用）
- 終了コードは成功 0、認証エラー 2、API エラー 1。エラー時は stdout に `{"error": {...}}` を出す
- `--format json` を受け付け、それ以外の形式は無視する
- 実カレンダーには一切アクセスしない

**fixture**:

| fixture | 用途 |
| --- | --- |
| `tests/fixtures/empty-month.json` | 予定 0 件の月 |
| `tests/fixtures/events.json` | 通常の予定（時刻付き・終日・Meet あり） |
| `tests/fixtures/many-events.json` | 同じ日に 5 件以上ある月（`+N` とレイアウトの検証用） |
| `tests/fixtures/paginated-page1.json` / `paginated-page2.json` | `nextPageToken` のページ取得 |
| `tests/fixtures/auth-error.json` | 認証エラー（終了コード 2） |
| `tests/fixtures/api-error.json` | API エラー（404 を含む） |

**実行環境**:

- `XDG_STATE_HOME` をワークスペース内の書き込み可能なディレクトリに向ける（サンドボックスでの `nvim.log` 書き込みエラーを避ける）
- `PLENARY_PATH` で plenary.nvim の場所を指定できる
- テストが 0 件の場合は失敗とする。`PlenaryBustedDirectory` は 0 件のディレクトリで終了コード 0 を返すため、`tests/minimal_init.lua` が 0 件なら `cquit 1` にし、`scripts/test.sh` も集計結果が 0 件なら失敗にする
- `scripts/e2e.sh` は一時ディレクトリを作り、`FAKE_GWS_STATE` / `FAKE_GWS_CWD_LOG` / `FAKE_GWS_CALL_LOG` / `XDG_STATE_HOME` を設定し、`gws` シンボリックリンクを `PATH` の先頭に置き、終了時に後始末する

## API

該当なし（HTTP API を持たない）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| 偽 gws の状態管理とサブコマンドの再現 | テスト | `tests/fixtures/fake-gws.py` |
| E2E の実行スクリプト（PATH・一時ディレクトリ・後始末） | テスト | `scripts/e2e.sh` |
| 空の月・ページネーション・認証エラーの fixture | テスト | `tests/fixtures/*.json` |
| テストハーネスの spec | テスト | `lua/google-calendar/test_harness_spec.lua` |

## エッジケースの決定

- **空・最小データ**: 状態ファイルが空の場合は 0 件の `items` を返す
- **上限・境界値**: ページネーションの検証用に、`nextPageToken` を返す fixture を用意する。予定 0 件・1 件・4 件以上（`+N`）のケースを用意する
- **エラー時に利用者へ見えるもの**: 認証エラー fixture で通知文言と「月表示を開かない」ことを検証する。API エラー fixture で、既存の表示が維持されることを検証する
- **並行操作・二重実行**: 偽 gws は呼び出し回数をログに残し、二重送信の検証に使えるようにする
- **再表示時の整合**: 偽 gws の状態ファイルは CRUD のたびに更新し、次の `list` に反映する

## UI レイアウト・操作の回帰テスト

実際の画面で見つかった「下部の空白」「選択日が分からない」「insert の Esc でフォームが閉じる」を再発させないため、以下をテストで固定する。

| 確かめること | レベル |
| --- | --- |
| 月表示のウィンドウ幅・高さが、ヘッダー + 6 週分の日付行 + 予定行の実数と一致する（下部・右側に空白を残さない） | 結合 |
| 詳細・アジェンダ・ヘルプ・確認のウィンドウ幅・高さが表示行の最大幅・行数と一致する | 結合 |
| 選択日のセルが全幅で目立つ背景（`GoogleCalendarSelected`）になり、今日のハイライトと重なっても判別できる | 結合 |
| フォームの insert モードの `<Esc>` は insert を抜けるだけで閉じず、normal モードの `<Esc>` / `q` でキャンセルする | 結合 |
| 月 → アジェンダ → 詳細 → フォーム → 確認 → ヘルプ → 月へ戻るフォーカスと各画面のサイズが崩れない（UI ジャーニー） | E2E |
| 代表データ（予定が多い日・長いタイトル・日本語・終日・Meet）で実際のターミナル表示を確認し、PR にスクリーンショットを添付する | 手動 |

**運用**:

- UI の変更を含む PR では、`make check` / `make test-e2e` に加えて、実ターミナルで `:GoogleCalendar` を開き、各画面をキー操作してスクリーンショットを撮る
- スクリーンショットは「予定が多い月」「フォームの insert → Esc」「確認・ヘルプ」の 3 枚を最低限用意する
- ユーザーから UI の不具合が報告されたら、まず再現するキー操作を E2E か結合テストに落とし、修正後に回帰させる

## テスト方針

| 確かめること (タスク説明から起こした) | レベル |
| --- | --- |
| 偽 gws が状態ファイルを使って予定の CRUD を再現し、実カレンダーを変更しない | 結合 |
| テストが 0 件のときに `make test` が失敗する | 結合 |
| `XDG_STATE_HOME` を書き込み可能なディレクトリに向けると、サンドボックスでもテストが実行できる | 結合 |
| 偽 gws の認証エラー fixture で、通知が出て月表示が開かないことを検証する | 結合 |
| 偽 gws のページネーション fixture で、2 ページ分の予定が結合されることを検証する | 結合 |
