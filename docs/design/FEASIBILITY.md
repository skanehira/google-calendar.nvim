# 技術検証（Feasibility Check）

- 種別: 技術検証
- 対象: google-calendar.nvim MVP（月表示・予定 CRUD・Meet 連携・gws 必須）

## 対象機能

Google カレンダーの月表示を Neovim の float window で再現し、`gws` コマンド経由で予定の一覧・登録・更新・削除・Meet URL 付与を行うプラグイン。MVP は primary カレンダー 1 つ、月単位の表示切り替え、日別アジェンダと予定詳細、登録・更新フォーム、削除確認、gws のセットアップ不備の通知を含む。

## 技術的不確実性

| ID | 不確実性 | 種類 | 影響度 | 発生確率 | リスクレベル |
|----|----------|------|--------|----------|-------------|
| R1 | `gws` の calendar events API で、一覧・Meet 付き作成・更新・削除・終日予定が期待通りに動くか。削除時の `download.html` 生成などの副作用も含む | 統合 | 致命的 | 低 | 🟡 優先 |
| R2 | Neovim の float window で 7 列×6 週の月グリッドを描画し、日本語の表示幅を揃え、複数の float（月表示・アジェンダ・詳細・フォーム）を重ねて管理できるか | 技術的実現性 | 重大 | 中 | 🟡 優先 |
| R3 | headless Neovim で float を開き、キー入力を与えてバッファ内容を assert する E2E テストが書けるか | 技術的実現性 | 中程度 | 中 | 🟢 通常 |
| R4 | Google が返す RFC3339 の `dateTime`（`Z` や `+09:00` を含む）を、Neovim のタイムゾーンに依存せず正しいローカル時刻に変換できるか | 技術的実現性 | 中程度 | 中 | 🟢 通常 |
| R5 | 予定が多い月に `nextPageToken` でページを追加取得し、全件を月表示に載せられるか | 統合 | 中程度 | 低 | 🟢 通常 |
| R6 | DSH の workspace-write サンドボックス下で `gws` が認証情報を書き込めず、実 API の検証ができない問題を回避できるか | 統合 | 重大 | 高 | 🟡 優先 |

## 検証項目

### R1: gws の予定 CRUD

**検証内容**:
- `gws calendar events list` で対象月の予定が JSON で取得できること
- `gws calendar +insert --meet` で Meet URL 付き予定が作成できること
- `gws calendar events patch` でタイトル・日時・場所・説明が更新できること
- `gws calendar events delete` で予定が削除できること
- `gws calendar events insert` で終日予定（`start.date` / `end.date`）が作成できること
- 削除時に cwd へ `download.html` が生成される副作用と、`cwd` を一時ディレクトリにすることで避けられること

**成功基準**:
- 各操作が終了コード 0 で完了し、返却 JSON から必要なフィールド（`id` / `hangoutLink` / `start` / `end`）が読める
- 作成したテスト予定が検証後に削除され、一覧から消えている
- リポジトリの cwd に `download.html` が残らない

**失敗した場合の代替案**:
- `+insert` ではなく `events insert` + `conferenceDataVersion=1` を直接使う
- 削除は `events delete` の代わりに `events patch` で `status=cancelled` にする

### R2: Neovim の月グリッド描画

**検証内容**:
- `nvim_open_win` で float window を作り、7 列×6 週の日付行をバッファに描画できること
- `nvim_buf_set_extmark` の `virt_lines` で各週の予定行をセルごとの色付きチャンクとして描画できること
- 日本語タイトルの表示幅を `strdisplaywidth` で揃え、セル幅で切り詰められること
- 月表示・日別アジェンダ・詳細・フォームの float を重ねて開き、閉じる順序を管理できること

**成功基準**:
- バッファ行数・extmark 数・virt_lines 数が期待通りになる
- 日本語を含むセルで列がずれない
- 複数 float の open/close でフォーカスが正しく戻る

**失敗した場合の代替案**:
- `virt_lines` を使わず、予定行もバッファの実ラインとして描画する
- 7 列グリッドを諦め、日別アジェンダ形式のリスト表示にする

### R3: headless E2E

**検証内容**:
- headless Neovim で `:GoogleCalendar` 相当の関数を呼び、float が開くこと
- `nvim_feedkeys` でキーを送り、月移動・日選択・フォーム入力を再現できること
- `vim.wait` で非同期の gws 呼び出し完了を待てること

**成功基準**:
- headless で float のバッファ内容を assert できる
- キー入力後に期待するバッファ内容へ遷移する
- 非同期処理の完了を待ってから assert できる

**失敗した場合の代替案**:
- キー入力の代わりに view のメソッドを直接呼ぶ統合テストにする
- E2E をやめ、単体・結合テストだけにする

### R4: タイムゾーン変換

**検証内容**:
- `2026-10-01T08:00:00Z` がローカル（Asia/Tokyo）で 17:00 になること
- `2026-10-01T17:00:00+09:00` が 17:00 のままであること
- オフセットの符号と分単位の差を扱えること

**成功基準**:
- 複数の ISO 8601 形式で期待するローカル時刻になる
- Neovim の `os.date` のタイムゾーン設定に依存しない

**失敗した場合の代替案**:
- イベントの `dateTime` の時刻部分をそのまま表示し、変換しない（カレンダーのタイムゾーンと一致する予定のみ正しい）

### R5: ページネーション

**検証内容**:
- `nextPageToken` を含むレスポンスを返す偽 gws で、アダプタが追加ページを取得できること
- 取得した全ページの `items` を結合して月表示に渡せること

**成功基準**:
- 2 ページ分の予定が重複なく結合される
- `nextPageToken` が無くなるまで取得する

**失敗した場合の代替案**:
- `maxResults=2500` の 1 ページのみとし、超過時は警告を出す

### R6: サンドボックス下の gws 認証

**検証内容**:
- `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` をワークスペース内の書き込み可能なディレクトリに向け、`client_secret.json` と `credentials.enc` をコピーして gws を実行できること
- 実 API の読み取り・書き込みが成功すること

**成功基準**:
- `gws calendar calendarList list` と `events list` が成功する
- 検証用の設定ディレクトリがリポジトリにコミットされない（`.gitignore` 対象）

**失敗した場合の代替案**:
- 実 API の検証を諦め、偽 gws との結合テストのみで設計を進める

## PoC計画

### PoC: gws の予定 CRUD
<!-- POC_STATUS: id=gws-calendar-crud, blocker=true, status=verified, confidence=manual -->

**id**: gws-calendar-crud
**目的**: gws で予定の一覧・Meet 付き作成・更新・削除・終日予定が動作することを実 API で確かめる
**risk**: medium
**blocker**: true

**スコープ**:
- 含む: primary カレンダーに対する list / insert（Meet あり・終日）/ patch / delete、エラー時の出力形式、削除の副作用
- 含まない: 複数カレンダー、参加者招待、繰り返し予定の編集

**実装内容**:
1. `gws calendar events list` で対象月の予定を取得し、JSON の構造を確認する
2. `gws calendar +insert --meet` でテスト予定を作成し、`hangoutLink` を確認する
3. `gws calendar events patch` でタイトル・日時・場所・説明を更新する
4. `gws calendar events delete` で削除し、一覧から消えたことを確認する
5. `gws calendar events insert` で終日予定を作成し、`start.date` / `end.date` を確認する
6. 削除時の `download.html` の生成を確認し、`cwd` を一時ディレクトリにして回避できるか確かめる

**必要なリソース**:
- 技術: gws 0.22.5、認証済みの Google アカウント
- 環境: macOS、Neovim 0.13 nightly
- データ: primary カレンダーの既存予定、検証用のテスト予定

**成功基準**:
- 各操作が終了コード 0 で完了する
- 作成したテスト予定が検証後に削除されている
- リポジトリの cwd に `download.html` が残らない

**判断**:
- 成功 → 本実装へ
- 失敗 → 代替案（events insert の直接利用、status=cancelled による削除）を検討

### PoC: Neovim の月グリッド描画
<!-- POC_STATUS: id=nvim-month-grid, blocker=true, status=verified, confidence=manual -->

**id**: nvim-month-grid
**目的**: float window で 7 列×6 週の月グリッドと日本語セルを描画でき、複数 float を管理できることを確かめる
**risk**: medium
**blocker**: true

**スコープ**:
- 含む: float の作成、日付行、virt_lines による予定行、日本語幅のパディングと切り詰め、複数 float の open/close
- 含まない: 実際の gws 連携、キーマップの全動作

**実装内容**:
1. `nvim_open_win` で float を作り、7 列×6 週の日付行をバッファに設定する
2. `nvim_buf_set_extmark` の `virt_lines` で予定行をセルごとのチャンクとして設定する
3. 日本語タイトルを `strdisplaywidth` でパディングし、セル幅で切り詰める
4. 月表示の上にアジェンダ・詳細・フォームの float を重ね、閉じる順序でフォーカスが戻ることを確認する

**必要なリソース**:
- 技術: Neovim 0.13 nightly、Lua
- 環境: headless Neovim
- データ: 日本語を含む予定タイトル

**成功基準**:
- バッファ行数・extmark 数・virt_lines 数が期待通りになる
- 日本語を含むセルで列がずれない
- 複数 float の open/close でフォーカスが正しく戻る

**判断**:
- 成功 → 本実装へ
- 失敗 → 予定行を実ラインにする、またはリスト表示へ変更する

### PoC: headless E2E
<!-- POC_STATUS: id=headless-e2e, blocker=false, status=verified, confidence=manual -->

**id**: headless-e2e
**目的**: headless Neovim で float を開き、キー入力を与えてバッファ内容を assert できることを確かめる
**risk**: medium
**blocker**: false

**スコープ**:
- 含む: `:GoogleCalendar` 相当の関数呼び出し、`nvim_feedkeys`、`vim.wait`、バッファ内容の assert
- 含まない: 実 API の呼び出し（偽 gws を使う）

**実装内容**:
1. headless Neovim でプラグインをロードし、月表示を開く
2. `nvim_feedkeys` で `l` / `<CR>` / `a` などを送る
3. `vim.wait` で非同期処理の完了を待ち、バッファ内容を assert する

**必要なリソース**:
- 技術: Neovim 0.13 nightly、plenary.nvim
- 環境: headless Neovim
- データ: 偽 gws が返す固定の予定 JSON

**成功基準**:
- headless で float のバッファ内容を assert できる
- キー入力後に期待するバッファ内容へ遷移する
- 非同期処理の完了を待ってから assert できる

**判断**:
- 成功 → E2E を実装する
- 失敗 → view のメソッドを直接呼ぶ統合テストに切り替える

### PoC: タイムゾーン変換
<!-- POC_STATUS: id=timezone-conversion, blocker=false, status=verified, confidence=manual -->

**id**: timezone-conversion
**目的**: RFC3339 の `dateTime` を Neovim のタイムゾーン設定に依存せずローカル時刻へ変換できることを確かめる
**risk**: low
**blocker**: false

**スコープ**:
- 含む: `Z` / `+09:00` / `+00:00` の変換、日付境界
- 含まない: 夏時間のあるタイムゾーンの網羅

**実装内容**:
1. ISO 8601 の文字列から日時とオフセットを取り出す
2. ローカルオフセットを `os.date('%z')` から取得し、UTC エポックへ変換する
3. `os.date` でローカル時刻を表示し、期待値と比較する

**必要なリソース**:
- 技術: Lua の `os.date` / `os.time`
- 環境: Asia/Tokyo
- データ: `2026-10-01T08:00:00Z`、`2026-10-01T17:00:00+09:00`、`2026-10-01T09:00:00+00:00`

**成功基準**:
- 3 つの入力がそれぞれ 17:00 / 17:00 / 18:00 になる

**判断**:
- 成功 → 本実装へ
- 失敗 → イベントの時刻部分をそのまま表示する方式に切り替える

### PoC: ページネーション
<!-- POC_STATUS: id=gws-pagination, blocker=false, status=verified, confidence=manual -->

**id**: gws-pagination
**目的**: `nextPageToken` を含む応答から全ページを取得して結合できることを確かめる
**risk**: low
**blocker**: false

**スコープ**:
- 含む: 偽 gws による 2 ページ応答、アダプタのページ追加取得
- 含まない: 実 API でのページネーション

**実装内容**:
1. 1 ページ目に `nextPageToken`、2 ページ目に残りの予定を返す偽 gws を用意する
2. アダプタの取得ループを実行し、全 `items` が結合されることを確認する

**必要なリソース**:
- 技術: Lua、シェルスクリプト
- 環境: Neovim
- データ: 固定の予定 JSON

**成功基準**:
- 2 ページ分の予定が重複なく結合される
- `nextPageToken` が無くなるまで取得する

**判断**:
- 成功 → 本実装へ
- 失敗 → 1 ページのみとし、超過時に警告する

### PoC: サンドボックス下の gws 認証
<!-- POC_STATUS: id=gws-sandbox-config, blocker=false, status=verified, confidence=manual -->

**id**: gws-sandbox-config
**目的**: workspace-write サンドボックス下でも gws の実 API 検証を行える設定方法を確かめる
**risk**: medium
**blocker**: false

**スコープ**:
- 含む: `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` の利用、認証情報のコピー、calendarList / events list の実行
- 含まない: 本番利用時の認証設定の変更

**実装内容**:
1. ワークスペース内に書き込み可能な設定ディレクトリを作る
2. `~/.config/gws` の `client_secret.json` と `credentials.enc` をコピーする
3. `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` を向けて gws を実行する

**必要なリソース**:
- 技術: gws 0.22.5、macOS の keyring
- 環境: DSH workspace-write
- データ: 既存の gws 認証情報

**成功基準**:
- `gws calendar calendarList list` と `events list` が成功する
- 設定ディレクトリが `.gitignore` で除外できる

**判断**:
- 成功 → 開発・検証コマンドに反映する
- 失敗 → 実 API の検証を諦め、偽 gws の結合テストのみで進める

## PoC 結果

### gws-calendar-crud — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実:
  - `gws calendar events list` が対象月の `items` を返し、`start.dateTime` と `start.date` の両形式を確認した
  - `gws calendar +insert --meet` が `hangoutLink`（例: `https://meet.google.com/...`）付きの予定を作成した
  - `gws calendar events patch` でタイトル・日時・場所・説明が更新された
  - `gws calendar events delete` は終了コード 0 で削除できたが、cwd に 0 バイトの `download.html` を生成した。`cwd` を一時ディレクトリにするとリポジトリ側に残らなかった
  - `gws calendar events insert` で `start.date` / `end.date` の終日予定を作成できた
  - 終日⇔時刻付きの切り替えは `events patch` では `Invalid start time.` (400) になり、`events update`（PUT）では成功した
  - `events update` に取得済みの `conferenceData` を含めると Meet URL が保持された
- 結論: MVP に必要な CRUD は成立する。更新は `events update` を使い、`events get` で取得した編集可能フィールドを保持して送る。削除は `cwd` を一時ディレクトリにして `download.html` の副作用を避ける
- 推奨アプローチ: 作成は `calendar +insert`（Meet は `--meet`）、更新は `events get` + `events update`、削除は `events delete`（cwd は一時ディレクトリ）、一覧は `events list` + `nextPageToken` のページ取得
- 採用した判断: ユーザーが PoC の書き込み範囲を承認し、実 API の結果を採用した

### nvim-month-grid — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実:
  - `nvim_open_win` で float を作成し、7 行の日付行と 3 本の `virt_lines` を持つバッファを描画できた
  - `virt_lines` のチャンクに日本語を含めても `strdisplaywidth` で幅を揃えられ、`strcharpart` で切り詰められた
  - float を 3 枚重ねて閉じると、Neovim は自動で親 float にフォーカスを戻さなかった。`nvim_set_current_win` で明示的に戻すと期待通りになった
- 結論: 月グリッドの描画方式は成立する。float のスタックを自前で管理し、閉じる際に親へ明示的にフォーカスを戻す
- 推奨アプローチ: `virt_lines` + extmark でセルごとの色付き予定行を描画し、日本語は `strdisplaywidth` でパディングする
- 採用した判断: ユーザーが PoC の範囲を承認し、描画方式を採用した

### headless-e2e — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実:
  - headless Neovim で float を開き、`nvim_feedkeys('l', 'x', false)` の後にカーソルが 2 行目へ移動した
  - `vim.wait(200)` で非同期処理の完了を待ってから assert できた
- 結論: headless E2E は成立する
- 推奨アプローチ: `nvim_feedkeys` + `vim.wait` でキー操作と非同期完了を再現し、バッファ内容を assert する
- 採用した判断: ユーザーが PoC の範囲を承認し、E2E 方式を採用した

### timezone-conversion — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実:
  - `2026-10-01T08:00:00Z` → ローカル 17:00
  - `2026-10-01T17:00:00+09:00` → 17:00
  - `2026-10-01T09:00:00+00:00` → 18:00
- 結論: オフセットを考慮した変換式 `epoch = os.time(components) + local_offset - event_offset` で正しく変換できる
- 推奨アプローチ: ISO 8601 の日時とオフセットを自前でパースし、`os.date('%z')` のローカルオフセットを使って UTC エポックへ変換する
- 採用した判断: ユーザーが PoC の範囲を承認し、変換式を採用した

### gws-pagination — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実: `nextPageToken` を返す偽 gws で 2 ページを取得し、2 件の `items` が重複なく結合された
- 結論: ページネーションは成立する。`nextPageToken` が `null` のときは `vim.NIL` になるため、`vim.NIL` を終端として扱う
- 推奨アプローチ: `nextPageToken` がある限り `pageToken` を付けて再取得し、`items` を結合する
- 採用した判断: ユーザーが PoC の範囲を承認し、ページ取得を採用した

### gws-sandbox-config — verified (判断: ユーザー)
- 検証日: 2026-10-27
- 観測した事実:
  - 既定の `~/.config/gws` ではサンドボックスが token ディレクトリのパーミッション変更を拒否し、401 になった
  - `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` をワークスペース内のコピーに向けると、`calendarList list` と `events list` が成功した
- 結論: 開発環境では設定ディレクトリをワークスペース内に向ければ実 API を検証できる。本番利用では既定の `~/.config/gws` のままでよい
- 推奨アプローチ: 開発・検証コマンドに `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` の設定例を書き、コピー先を `.gitignore` に入れる
- 採用した判断: ユーザーが PoC の範囲を承認し、設定方法を採用した

## 技術スタック（案）

| レイヤー | 技術 | 選定理由 |
|----------|------|----------|
| 言語 | Lua (Neovim 組み込み) | プラグインの標準。追加ランタイム不要 |
| UI | `nvim_open_win` + バッファ + extmark | nui.nvim 等の外部依存を増やさず、float の重ね合わせを自前で管理できる |
| 外部コマンド | `gws` (calendar events / calendarList) | ユーザー指定の必須要件。認証と API 呼び出しを gws に任せる |
| 非同期実行 | `vim.system` | Neovim 0.10+ の標準 API。コールバックで UI をブロックしない |
| テスト | plenary.nvim の busted harness | 参考実装 (docker.nvim / k8s.nvim) と同じ。`nvim --headless` で実行できる |
| Lint / Format | luacheck / stylua | 参考実装と同じ |
| 型チェック | lua-language-server | 参考実装と同じ |

## 次のステップ

1. [x] PoC を実行し、POC_STATUS と「PoC 結果」を更新する
2. [x] blocker=true の計画をすべて解決する
3. [ ] 結果を DESIGN.md と機能設計書へ転記する
