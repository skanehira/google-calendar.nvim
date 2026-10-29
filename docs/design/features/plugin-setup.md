# プラグインの骨格・設定・コマンド

- 種別: 機能設計書
- 対象 UC: なし (基盤)

## 何を作るか

プラグインのエントリポイント、`setup()` による設定のマージ、`:GoogleCalendar` コマンドの登録と引数の解釈、float のスタック管理、開発用の Makefile・minimal_init・CI を提供する。各画面の実装がこの骨格の上に載る。

## 入出力と振る舞い

**`:GoogleCalendar`**:

| 引数 | 振る舞い |
| --- | --- |
| なし | 当月の月表示を開く。既に開いている場合はメモリキャッシュを使ってフォーカスする（再取得は `r` / `R`） |
| `YYYY-MM` | 指定した月の月表示を開く |
| 不正な形式 | `Month must be specified in YYYY-MM format` と通知し、開かない |
| 存在しない月（`2026-13`） | 同上 |

- `nargs = '?'`、`complete` は `YYYY-MM` の候補を返す
- `setup()` を呼ばなくても既定値で動作する

**`setup(opts)`**:

- 既定値と `opts` を深いマージで統合する。`keymaps` / `highlights` は画面ごとにマージし、`false` で無効化できる
- `calendars` は通常 `stdpath('config')/google-calendar.nvim/config.json` から読み込む。ファイルがなければ `primary` を使う。`setup({ calendars = ... })` を明示した場合はファイルより優先する
- `keymaps` は `month` / `agenda` / `detail` / `form` / `confirm` / `help` の画面ごとにアクション名で指定する。未知の画面名・アクション名は警告して無視する
- すべての画面のキーは `config.keymaps` から解決し、実装に直書きしない。保存の既定キーは `<F2>`（`<C-s>` は herdr の prefix と衝突するため使わない）
- 不正な値（`week_start` が `sunday` / `monday` 以外、`max_events_per_cell` が 1 未満）は `vim.notify` で警告し、既定値を使う
- 複数回呼ばれた場合は最後の設定を有効にする（テストで設定を差し替えられるようにする）

**float のスタック**:

- `windows` に月表示・アジェンダ・詳細・フォーム・ヘルプ・確認の winid を保持する
- 開くときはスタックに push し、`nvim_open_win` でフォーカスする
- 閉じるときは pop し、**親のウィンドウへ `nvim_set_current_win` で明示的に戻す**（Neovim は自動で戻さない）
- 月表示は 1 つだけ。既に開いている場合はメモリキャッシュを使ってフォーカスする。`r` / `R` で明示的に再取得する
- `q` / `<Esc>` で 1 段ずつ閉じる

**開発用の骨格**:

- `Makefile` に `test` / `test-file` / `test-e2e` / `lint` / `format` / `format-check` / `typecheck` / `check` を定義する
- `tests/minimal_init.lua` は plenary とリポジトリ自身を `runtimepath` に追加し、`PlenaryBustedDirectory` が未定義なら `cquit 1` で終了する
- `.github/workflows/ci.yml` で `make check` を実行する

## API

該当なし（HTTP API を持たない）。

## 実装の配置

| 処理 | 層 | 実装先ファイル |
| --- | --- | --- |
| `:GoogleCalendar` の登録・引数の補完 | プラグイン | `plugin/google-calendar.lua` |
| `setup()`、コマンド実行、月表示の起動 | エントリポイント | `lua/google-calendar/init.lua` |
| 既定値・キーマップ・ハイライトのマージと検証 | 設定 | `lua/google-calendar/config.lua` |
| float の生成・破棄・フォーカス復帰 | UI | `lua/google-calendar/ui/window.lua` |
| 表示状態（年月、選択日、windows） | ドメイン | `lua/google-calendar/state.lua` |
| テスト・lint・format・typecheck のコマンド | 開発 | `Makefile` |
| plenary の読み込みとテスト実行の前提 | 開発 | `tests/minimal_init.lua` |
| CI | 開発 | `.github/workflows/ci.yml` |

## エッジケースの決定

- **空・最小データ**: `setup()` なしでも既定値で動く。`opts` が空テーブルでも同じ
- **上限・境界値**: `max_events_per_cell` は 1〜10 に制限する。float の幅が 7 セルを描画できない場合は `Window is too narrow` と通知する。`YYYY-MM` は 4 桁年 + 2 桁月のみ受け付ける
- **エラー時に利用者へ見えるもの**: 不正な設定は警告を出して既定値を使う。不正なコマンド引数は通知して開かない
- **並行操作・二重実行**: `:GoogleCalendar` の連続実行は、既存の月表示を再利用してフォーカスする（二重に開かない）
- **再表示時の整合**: `setup()` の変更は次回の画面生成時に反映する。実行中の画面のキーマップは変更しない

## テスト方針

| 確かめること (タスク説明から起こした) | レベル |
| --- | --- |
| `setup()` が既定値をマージし、`keymaps` / `highlights` の上書きを反映する | 単体 |
| `:GoogleCalendar` が引数なしで当月、`YYYY-MM` で指定月の月表示を開く | 結合 |
| 不正な `YYYY-MM` を指定すると通知が出て、月表示は開かない | 単体 |
| float を閉じると親のウィンドウへフォーカスが戻る | 結合 |
| `make test` が plenary の busted harness で `lua/` 配下の spec を実行する | 結合 |
| `make check` が lint / format-check / typecheck / test を順に実行する | 結合 |
| `setup({ keymaps = { form = { save = '<F2>' } } })` がフォームの保存キーを上書きする | 単体 |
| `false` を指定したキーが作用しない | 単体 |
| 未知の画面名・アクション名を指定すると警告が出て、その指定は無視される | 単体 |
