---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local slot_filter = require('google-calendar.ui.slot_filter')
local state = require('google-calendar.state')

local original_search
local original_help
local searched
local opened_help
local notifications

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.slot_filter), 0, -1, false)
end

local function footer_text(win)
  local text = ''
  for _, chunk in ipairs(vim.api.nvim_win_get_config(win).footer or {}) do
    text = text .. chunk[1]
  end
  return text
end

local function setup(slots)
  config.setup({
    slots = vim.tbl_extend('force', { weeks = 2 }, slots or {}),
    notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end,
  })
end

describe('ui.slot_filter', function()
  before_each(function()
    state.reset()
    searched = {}
    opened_help = nil
    notifications = {}
    setup()

    original_search = slot_filter.openers.search
    original_help = slot_filter.openers.help
    slot_filter.openers.search = function(conditions)
      table.insert(searched, conditions)
    end
    slot_filter.openers.help = function(screen)
      opened_help = screen
    end
  end)

  after_each(function()
    slot_filter.openers.search = original_search
    slot_filter.openers.help = original_help
    for _, entry in ipairs(vim.deepcopy(state.stack)) do
      require('google-calendar.ui.window').close(entry.name)
    end
  end)

  it(
    '時間帯・所要時間・今日を含む週からの週を選択肢として描き、既定値と今週を選んだ状態で開く',
    function()
      slot_filter.open({ today = '2026-11-18' })

      assert.are.same({
        ' 時間帯',
        '>● 09:00 ~ 18:00',
        ' ○ 09:00 ~ 23:00',
        ' 所要時間',
        ' ○ 30分',
        ' ● 1時間',
        ' ○ 1時間30分',
        ' ○ 2時間',
        ' 週',
        ' ● 11/15(日)~11/21(土)',
        ' ○ 11/22(日)~11/28(土)',
      }, buffer_lines())
    end
  )

  it(
    'j/k は見出しを飛ばして移動し、<Space> で時間帯と所要時間を 1 つに切り替える',
    function()
      slot_filter.open({ today = '2026-11-18' })

      feed('j<Space>j<Space>')

      assert.are.same({
        ' 時間帯',
        ' ○ 09:00 ~ 18:00',
        ' ● 09:00 ~ 23:00',
        ' 所要時間',
        '>● 30分',
        ' ○ 1時間',
        ' ○ 1時間30分',
        ' ○ 2時間',
        ' 週',
        ' ● 11/15(日)~11/21(土)',
        ' ○ 11/22(日)~11/28(土)',
      }, buffer_lines())

      feed('k')
      assert.are.equal('>● 09:00 ~ 23:00', buffer_lines()[3])
    end
  )

  it('<Space> で週の選択を個別に反転し、<CR> で選んだ条件の候補を探す', function()
    setup({ weekdays = { 'monday', 'friday' } })
    slot_filter.open({ today = '2026-11-18' })

    feed('jjjjjjj<Space>')
    assert.are.same(
      { ' ● 11/15(日)~11/21(土)', '>● 11/22(日)~11/28(土)' },
      vim.list_slice(buffer_lines(), 10, 11)
    )
    feed('k<Space><CR>')

    assert.are.same({
      {
        time_range = { start = '09:00', finish = '18:00' },
        duration = 60,
        dates = { '2026-11-23', '2026-11-27' },
      },
    }, searched)
  end)

  it('週を 1 つも選ばずに <CR> を押すと警告し、候補を探さない', function()
    slot_filter.open({ today = '2026-11-18' })

    feed('jjjjjj<Space><CR>')

    assert.are.same({}, searched)
    assert.are.same({ { msg = 'Select at least one week', level = vim.log.levels.WARN } }, notifications)
    assert.are.equal('>○ 11/15(日)~11/21(土)', buffer_lines()[10])
  end)

  it('候補一覧を <Esc> で閉じて戻ると、直前に選んだ条件のまま表示する', function()
    local slots_ui = require('google-calendar.ui.slots')
    local original_fetch = slots_ui.deps.fetch_events
    slots_ui.deps.fetch_events = function() end
    slot_filter.openers.search = original_search
    slot_filter.open({ today = '2026-11-18' })

    feed('jjjj<Space>jjj<Space><CR>')
    assert.is_not_nil(state.windows.slots)
    feed('<Esc>')
    slots_ui.deps.fetch_events = original_fetch

    assert.is_nil(state.windows.slots)
    assert.are.equal(state.windows.slot_filter, vim.api.nvim_get_current_win())
    assert.are.same({
      ' 時間帯',
      ' ● 09:00 ~ 18:00',
      ' ○ 09:00 ~ 23:00',
      ' 所要時間',
      ' ○ 30分',
      ' ○ 1時間',
      ' ● 1時間30分',
      ' ○ 2時間',
      ' 週',
      ' ● 11/15(日)~11/21(土)',
      '>● 11/22(日)~11/28(土)',
    }, buffer_lines())
  end)

  it('q で条件選択を隠し、開く前のウィンドウへフォーカスを戻す', function()
    local original = vim.api.nvim_get_current_win()
    local win = slot_filter.open({ today = '2026-11-18' })

    feed('q')

    assert.is_true(vim.api.nvim_win_get_config(win).hide)
    assert.are.equal(original, vim.api.nvim_get_current_win())
  end)

  it('フッターに選択・検索・閉じる・隠すのキーを表示する', function()
    local win = slot_filter.open({ today = '2026-11-18' })

    assert.are.equal(' <Space>:選択 <CR>:検索 <Esc>:閉じる q:隠す ', footer_text(win))
  end)

  it('? でヘルプを開き、<Esc> で閉じる', function()
    slot_filter.open({ today = '2026-11-18' })

    feed('?')
    assert.are.equal('slot_filter', opened_help)

    feed('<Esc>')
    assert.is_nil(state.windows.slot_filter)
  end)
end)
