# google-calendar.nvim

Neovim を離れずに Google カレンダーの月表示を開き、予定の確認・登録・更新・削除・Google Meet URL の付与を行うプラグインです。予定の取得と更新は [`gws`](https://github.com/googleworkspace/cli) に任せ、プラグイン自身は Google Calendar API を直接呼びません。

## 必須要件

- Neovim 0.10 以上
- `gws` 0.22.5 以上がインストールされ、認証済みであること
- Google Calendar API が有効な Google アカウントで `gws auth login` を実行済みであること
- 予定の操作には `gws` が必須です。`gws` が無い場合や未認証の場合は、プラグインはエラーを通知します

```bash
# gws は公式のインストール手順に従って導入してください

# 認証
gws auth login
```

## セットアップ

lazy.nvim を使う場合:

```lua
{
  'skanehira/google-calendar.nvim',
  config = function()
    require('google-calendar').setup()
  end,
}
```

手動で `runtimepath` に追加する場合:

```lua
vim.opt.runtimepath:append('/path/to/google-calendar.nvim')
require('google-calendar').setup()
```

`setup()` を呼ばなくても既定値で動作します。設定は最後に呼んだ `setup()` が有効になります。

## コマンド

| コマンド | 動作 |
| --- | --- |
| `:GoogleCalendar` | 当月の月表示を開く。既に開いている場合は再取得してフォーカスする |
| `:GoogleCalendar 2026-11` | 指定した月の月表示を開く |
| `:GoogleCalendar 2026-13` | 不正な年月として通知し、月表示を開かない |

## 既定キーマップ

| 画面 | キー | 動作 |
| --- | --- | --- |
| 月表示 | `h` / `l` | 前日 / 翌日を選択 |
| 月表示 | `k` / `j` | 前週 / 翌週を選択 |
| 月表示 | `H` / `L` | 前月 / 次月へ移動 |
| 月表示 | `t` | 今日へ移動 |
| 月表示 | `<CR>` | 選択日の日別アジェンダを開く |
| 月表示 | `a` | 選択日の予定を登録する |
| 月表示 | `r` | 表示中の月を再取得する |
| 月表示 | `?` | ヘルプを開く |
| 月表示 | `q` / `<Esc>` | 月表示を閉じる |
| アジェンダ | `j` / `k` | 予定を選択 |
| アジェンダ | `<CR>` | 予定詳細を開く |
| アジェンダ | `q` / `<Esc>` | 月表示に戻る |
| 詳細 | `e` | 更新フォームを開く |
| 詳細 | `d` | 削除確認を開く |
| 詳細 | `y` | Meet URL をコピーする |
| 詳細 | `q` / `<Esc>` | アジェンダに戻る |
| 確認 | `y` | 予定を削除する |
| 確認 | `n` / `q` / `<Esc>` | 確認を閉じる（削除しない） |
| フォーム | `<Tab>` / `<S-Tab>` | 次のフィールド / 前のフィールド |
| フォーム | `<CR>` | テキストフィールドの編集を開始する |
| フォーム | `<Space>` | 終日・Meet のトグルを切り替える |
| フォーム | `<F2>` | 保存する |
| フォーム | `<Esc>` / `q` | キャンセルする |
| フォーム | `?` | フォームのヘルプを開く |
| ヘルプ | `q` / `<Esc>` | ヘルプを閉じる |

フォームの保存の既定キーは `<F2>` です。`<C-s>` は herdr の prefix と衝突するため使いません。

## 設定

```lua
require('google-calendar').setup({
  -- 表示するカレンダー。MVP は primary のみを想定
  calendars = { 'primary' },
  -- 週の開始曜日。'sunday' または 'monday'
  week_start = 'sunday',
  -- 1 セルに表示する予定の最大件数 (1〜10)
  max_events_per_cell = 3,
  -- float のサイズ (画面に対する割合)
  width = 0.9,
  height = 0.85,
  -- 日時の表示形式
  date_format = '%Y-%m-%d %H:%M',
  -- gws の実行ファイル
  gws_cmd = 'gws',
  -- 通知関数 (テストで差し替え可能)
  notify = vim.notify,
  -- クリップボードへの書き込み関数 (テストで差し替え可能)
  clipboard = function(url)
    vim.fn.setreg('+', url)
  end,
  -- キーマップの上書き (画面ごとに指定。false で無効化)
  keymaps = {
    month = {
      prev_day = 'h',
      next_day = 'l',
      prev_week = 'k',
      next_week = 'j',
      prev_month = 'H',
      next_month = 'L',
      today = 't',
      agenda = '<CR>',
      create = 'a',
      refresh = 'r',
      help = '?',
      close = 'q',
      esc_close = '<Esc>',
    },
    agenda = { next = 'j', prev = 'k', open = '<CR>', help = '?', close = 'q', esc_close = '<Esc>' },
    detail = { edit = 'e', delete = 'd', copy_meet = 'y', help = '?', close = 'q', esc_close = '<Esc>' },
    form = {
      next_field = '<Tab>',
      prev_field = '<S-Tab>',
      edit = '<CR>',
      toggle = '<Space>',
      save = '<F2>',
      cancel = '<Esc>',
      close = 'q',
      help = '?',
    },
    confirm = { yes = 'y', no = 'n', close = 'q', esc_close = '<Esc>' },
    help = { close = 'q', esc_close = '<Esc>' },
  },
  -- ハイライトの上書き
  highlights = {},
})
```

キーマップは既定値と深くマージされます。`false` を指定したキーは無効になります。未知の画面名・アクション名を指定すると警告が出て、その指定は無視されます。

例: フォームの保存キーを `<A-s>` に変え、月表示の `q` を無効にする

```lua
require('google-calendar').setup({
  keymaps = {
    form = { save = '<A-s>' },
    month = { close = false },
  },
})
```

## 開発

```bash
# テスト (plenary の busted harness)
make test

# 単一の spec ファイル
make test-file FILE=lua/google-calendar/config_spec.lua

# 偽 gws を使った headless E2E
make test-e2e

# lint / format / 型チェック
make lint
make format-check
make typecheck

# すべて実行 (lint -> format-check -> typecheck -> test)
make check
```

テストは `tests/fixtures/fake-gws.py` を使うため、実カレンダーを変更しません。`plenary.nvim` が必要です。場所は `PLENARY_PATH` で指定できます (既定は `~/.local/share/nvim/lazy/plenary.nvim`)。サンドボックス環境では `XDG_STATE_HOME` を書き込み可能なディレクトリに向けてください (Makefile の既定は `.tmp-state/`)。

開発ツール:

- `stylua` 2.x
- `luacheck` 1.x
- `lua-language-server` 3.x
- Python 3 (偽 gws 用)

## スコープ

MVP は primary カレンダー 1 つの月表示のみを対象とします。週表示・複数カレンダーの横断表示・キーワード絞り込み・参加者の招待は対象外です。
