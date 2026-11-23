---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local help = require('google-calendar.ui.help')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local screen_opts = { relative = 'editor', width = 40, height = 10, row = 1, col = 1 }

local function is_hidden(win)
  return vim.api.nvim_win_get_config(win).hide == true
end

local default_month_lines = {
  'h/l:前日/翌日',
  'k/j:前週/翌週',
  'H/L:前月/次月',
  't:今日',
  '<CR>:アジェンダ',
  'a:登録',
  's:空き枠',
  'r:再取得',
  '?:ヘルプ',
  '<Esc>:閉じる',
  'q:隠す',
}

describe('ui.help', function()
  before_each(function()
    config.setup({})
    state.reset()
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
  end)

  it('月表示で有効なキーの一覧を生成する', function()
    assert.are.same(default_month_lines, help.lines('month'))
  end)

  it('アジェンダで有効なキーの一覧を生成する', function()
    assert.are.same({
      'j/k:選択',
      '<CR>:詳細',
      '<C-o>:カレンダーで開く',
      'd:削除',
      '<Esc>:戻る',
      'q:隠す',
    }, help.lines('agenda'))
  end)

  it('詳細で有効なキーの一覧を生成する', function()
    assert.are.same({
      'e:更新',
      'd:削除',
      'y:Meet URL コピー',
      'g:ゲスト折り畳み',
      '<Esc>:戻る',
      'q:隠す',
    }, help.lines('detail'))
  end)

  it('空き枠の条件選択で有効なキーの一覧を生成する', function()
    assert.are.same({
      'j/k:移動',
      '<Space>:選択',
      '<CR>:検索',
      '<Esc>:閉じる',
      'q:隠す',
    }, help.lines('slot_filter'))
  end)

  it('空き枠の候補一覧で有効なキーの一覧を生成する', function()
    assert.are.same({
      'j/k:選択',
      '<Space>:複数選択',
      'a:全選択',
      'y:コピー',
      '<Esc>:戻る',
      'q:隠す',
    }, help.lines('slots'))
  end)

  it('フォームで有効なキーの一覧を生成する', function()
    assert.are.same({
      '<Tab>/<S-Tab>:移動',
      '<CR>:編集',
      '<Space>:切替',
      ':w:保存',
      '<Esc>:取消',
      'q:隠す',
      '?:ヘルプ',
    }, help.lines('form'))
  end)

  it('setup() で変更したキーマップを反映する', function()
    config.setup({ keymaps = { month = { close = 'Q', next_month = 'N' }, form = { save = '<A-s>' } } })

    local expected_month = vim.deepcopy(default_month_lines)
    expected_month[3] = 'H/N:前月/次月'
    expected_month[11] = 'Q:隠す'

    assert.are.same(expected_month, help.lines('month'))
    assert.are.same({
      '<Tab>/<S-Tab>:移動',
      '<CR>:編集',
      '<Space>:切替',
      '<A-s>:保存',
      '<Esc>:取消',
      'q:隠す',
      '?:ヘルプ',
    }, help.lines('form'))
  end)

  it('false で無効化したキーを表示しない', function()
    config.setup({ keymaps = { month = { create = false, help = false }, form = { save = false } } })

    assert.are.same({
      'h/l:前日/翌日',
      'k/j:前週/翌週',
      'H/L:前月/次月',
      't:今日',
      '<CR>:アジェンダ',
      's:空き枠',
      'r:再取得',
      '<Esc>:閉じる',
      'q:隠す',
    }, help.lines('month'))
    assert.are.same({
      '<Tab>/<S-Tab>:移動',
      '<CR>:編集',
      '<Space>:切替',
      '<Esc>:取消',
      'q:隠す',
      '?:ヘルプ',
    }, help.lines('form'))
  end)

  it('組の片方だけを無効化すると有効なキーだけを表示する', function()
    config.setup({ keymaps = { month = { next_day = false } } })

    local expected_month = vim.deepcopy(default_month_lines)
    expected_month[1] = 'h:前日'

    assert.are.same(expected_month, help.lines('month'))
  end)

  it('有効なキーが 1 つも無い画面では有効なキーがありませんと表示する', function()
    config.setup({
      keymaps = {
        agenda = {
          next = false,
          prev = false,
          open = false,
          open_url = false,
          delete = false,
          close = false,
          esc_close = false,
        },
      },
    })

    assert.are.same({ '有効なキーがありません' }, help.lines('agenda'))
  end)

  it('現在の画面の上に仕様のサイズでヘルプを開く', function()
    local parent = vim.api.nvim_get_current_win()

    local win = help.open('month')

    local win_config = vim.api.nvim_win_get_config(win)
    local content_width = 0
    for _, line in ipairs(default_month_lines) do
      content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
    end
    assert.are.equal(math.min(70, vim.o.columns - 8, content_width + 2), win_config.width)
    assert.are.equal(#default_month_lines, win_config.height)
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal('help', state.stack[#state.stack].name)
    assert.are.equal(parent, state.stack[#state.stack].parent)
    assert.are.same(default_month_lines, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false))
  end)

  it('ヘルプで q を押すと、元の画面ごと隠して開く前のウィンドウへ戻る', function()
    local original = vim.api.nvim_get_current_win()
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys('q', 'x', false)

    assert.are.same({ true, true }, { is_hidden(screen_win), is_hidden(help_win) })
    assert.are.equal(original, vim.api.nvim_get_current_win())
    assert.are.equal(2, #state.stack)
  end)

  it('ヘルプで <Esc> を押すと閉じ、元の画面に戻る', function()
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)

    assert.is_false(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(screen_win, vim.api.nvim_get_current_win())
  end)

  it('ヘルプの <Esc> は setup() の keymaps.help.esc_close から解決する', function()
    config.setup({ keymaps = { help = { esc_close = '<C-x>' } } })
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)

    assert.is_true(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-x>', true, false, true), 'x', false)

    assert.is_false(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(screen_win, vim.api.nvim_get_current_win())
  end)

  it('keymaps.help.esc_close = false のとき <Esc> では閉じず、q で隠す', function()
    config.setup({ keymaps = { help = { esc_close = false } } })
    local original = vim.api.nvim_get_current_win()
    window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)

    assert.is_false(is_hidden(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys('q', 'x', false)

    assert.is_true(is_hidden(help_win))
    assert.are.equal(original, vim.api.nvim_get_current_win())
  end)

  it('ヘルプを再表示すると変更した esc_close を反映し、旧キーでは閉じない', function()
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_set_current_win(screen_win)
    config.setup({ keymaps = { help = { esc_close = '<C-x>' } } })

    local reopened = help.open('month')
    assert.are.equal(help_win, reopened)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)

    assert.is_true(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-x>', true, false, true), 'x', false)

    assert.is_false(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(screen_win, vim.api.nvim_get_current_win())
  end)

  it('既に開いているヘルプを再使用し、最新のキーマップを表示する', function()
    local screen_win = window.open('month', screen_opts)
    local first = help.open('month')

    vim.api.nvim_set_current_win(screen_win)
    config.setup({ keymaps = { month = { close = 'Q' } } })

    local second = help.open('month')

    local expected_month = vim.deepcopy(default_month_lines)
    expected_month[11] = 'Q:隠す'

    assert.are.equal(first, second)
    assert.are.equal(first, vim.api.nvim_get_current_win())
    assert.are.equal(1, #vim.tbl_filter(function(entry)
      return entry.name == 'help'
    end, state.stack))
    assert.are.same(expected_month, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(first), 0, -1, false))
  end)
  it('keymaps.help.close の上書きが効き、既定の q では隠さない', function()
    config.setup({ keymaps = { help = { close = 'Q' } } })
    local original = vim.api.nvim_get_current_win()
    window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_feedkeys('q', 'x', false)

    assert.is_false(is_hidden(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys('Q', 'x', false)

    assert.is_true(is_hidden(help_win))
    assert.are.equal(original, vim.api.nvim_get_current_win())
  end)

  it('keymaps.help.close = false のとき q では隠さず、<Esc> で閉じる', function()
    config.setup({ keymaps = { help = { close = false } } })
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_feedkeys('q', 'x', false)

    assert.is_false(is_hidden(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)

    assert.is_false(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(screen_win, vim.api.nvim_get_current_win())
  end)

  it('ヘルプを再表示すると変更した close を反映し、旧キーでは隠さない', function()
    local original = vim.api.nvim_get_current_win()
    local screen_win = window.open('month', screen_opts)
    local help_win = help.open('month')

    vim.api.nvim_set_current_win(screen_win)
    config.setup({ keymaps = { help = { close = 'Q' } } })

    local reopened = help.open('month')
    assert.are.equal(help_win, reopened)

    vim.api.nvim_feedkeys('q', 'x', false)

    assert.is_false(is_hidden(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())

    vim.api.nvim_feedkeys('Q', 'x', false)

    assert.is_true(is_hidden(help_win))
    assert.are.equal(original, vim.api.nvim_get_current_win())
  end)
end)
