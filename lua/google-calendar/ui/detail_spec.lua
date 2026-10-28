---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local detail = require('google-calendar.ui.detail')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local screen_opts = { relative = 'editor', width = 40, height = 10, row = 1, col = 1 }

local original_columns
local original_lines
local original_local_datetime
local original_openers

local edited
local deleted
local copied
local opened_help

local function fake_local_datetime(value)
  return value:sub(1, 10), value:sub(12, 16)
end

local function full_event()
  return {
    id = 'evt-1',
    summary = '定例',
    location = '会議室A',
    description = '議題1\n議題2',
    start = { dateTime = '2026-10-28T09:00:00+09:00' },
    ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
    hangout_link = 'https://meet.google.com/abc-defg-hij',
    calendar_id = 'primary',
  }
end

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.detail), 0, -1, false)
end

local function fixture_events()
  local body = vim.json.decode(table.concat(vim.fn.readfile('tests/fixtures/events.json'), '\n'))
  return event.normalize_list(body.items, { calendar_id = 'primary' })
end

describe('ui.detail', function()
  before_each(function()
    state.reset()
    config.setup({})
    edited = nil
    deleted = nil
    copied = nil
    opened_help = nil

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 100
    vim.o.lines = 40

    original_local_datetime = rawget(event, 'local_datetime')
    rawset(event, 'local_datetime', fake_local_datetime)

    original_openers = vim.deepcopy(detail.openers)
    detail.openers.edit = function(item)
      edited = item
    end
    detail.openers.delete = function(item)
      deleted = item
    end
    detail.openers.copy_meet = function(item)
      copied = item
    end
    detail.openers.help = function(screen)
      opened_help = screen
    end
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
    state.reset()

    rawset(event, 'local_datetime', original_local_datetime)
    detail.openers = original_openers
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it('予定の詳細を仕様の項目順で表示する', function()
    local item = full_event()
    local parent = vim.api.nvim_get_current_win()

    local win = detail.open(item)

    local win_config = vim.api.nvim_win_get_config(win)
    assert.are.equal(70, win_config.width)
    assert.are.equal(14, win_config.height)
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal('detail', state.stack[#state.stack].name)
    assert.are.equal(parent, state.stack[#state.stack].parent)
    assert.are.same({
      'タイトル: 定例',
      '開始: 2026-10-28 09:00',
      '終了: 2026-10-28 10:00',
      '場所: 会議室A',
      '説明: 議題1',
      '議題2',
      'Meet URL: https://meet.google.com/abc-defg-hij',
      'カレンダー: primary',
    }, buffer_lines())
  end)

  it('値がない項目は行ごと省略し、終日予定は日付をそのまま表示する', function()
    local item = {
      id = 'evt-2',
      summary = '休み',
      location = '',
      description = '',
      start = { date = '2026-10-28' },
      ['end'] = { date = '2026-10-29' },
    }

    detail.open(item)

    assert.are.same({
      'タイトル: 休み',
      '開始: 2026-10-28',
      '終了: 2026-10-29',
    }, buffer_lines())
  end)

  it('説明が 5 行を超える場合は 5 行で … を付けて切り詰める', function()
    local item = {
      id = 'evt-3',
      summary = '議題',
      description = '1\n2\n3\n4\n5\n6\n7',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
    }

    detail.open(item)

    assert.are.same({
      'タイトル: 議題',
      '開始: 2026-10-28 09:00',
      '終了: 2026-10-28 10:00',
      '説明: 1',
      '2',
      '3',
      '4',
      '5…',
    }, buffer_lines())
  end)

  it('タイトルが 1 行に収まらない場合は … で切り詰める', function()
    vim.o.columns = 30
    local item = full_event()
    item.summary = '定例ミーティング'

    detail.open(item)

    assert.are.same('タイトル: 定例ミーテ…', buffer_lines()[1])
  end)

  it('Meet URL を持つ予定（fixture）で URL を表示する', function()
    local items = fixture_events()
    local item = items[3]
    assert.are.equal('evt-meet-1', item.id)

    detail.open(item)

    local lines = buffer_lines()
    assert.is_true(vim.tbl_contains(lines, 'タイトル: Meet 付き'))
    assert.is_true(vim.tbl_contains(lines, 'Meet URL: https://meet.google.com/abc-defg-hij'))
    assert.is_true(vim.tbl_contains(lines, 'カレンダー: primary'))
  end)

  it('e / d / y / ? の opener をスタブで差し替えてキーが呼ばれる', function()
    local item = full_event()

    detail.open(item)

    feed('e')
    assert.are.equal(item, edited)

    feed('d')
    assert.are.equal(item, deleted)

    feed('y')
    assert.are.equal(item, copied)

    feed('?')
    assert.are.equal('detail', opened_help)
  end)

  it('q で詳細を閉じ、アジェンダに戻る', function()
    local parent = window.open('agenda', screen_opts)
    local win = detail.open(full_event())
    assert.are.equal(win, vim.api.nvim_get_current_win())

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_nil(state.windows.detail)
    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.are.equal(1, #state.stack)
    assert.are.equal('agenda', state.stack[1].name)
  end)

  it('<Esc> で詳細を閉じる', function()
    local parent = window.open('agenda', screen_opts)
    local win = detail.open(full_event())

    feed('<Esc>')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
  end)

  it('setup() で上書きしたキーで詳細を閉じ、esc_close = false では <Esc> で閉じない', function()
    config.setup({ keymaps = { detail = { close = 'Q', esc_close = false } } })
    local parent = window.open('agenda', screen_opts)
    local win = detail.open(full_event())

    feed('<Esc>')
    assert.is_true(vim.api.nvim_win_is_valid(win))

    feed('Q')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
  end)
end)
