---@diagnostic disable: undefined-field
local agenda = require('google-calendar.ui.agenda')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local screen_opts = { relative = 'editor', width = 40, height = 10, row = 1, col = 1 }

local original_columns
local original_lines
local original_local_datetime
local original_open_detail
local original_delete
local original_help

local opened_detail
local opened_delete
local delete_opts
local opened_help

local function fake_local_datetime(value)
  return value:sub(1, 10), value:sub(12, 16)
end

local function timed_event(id, summary, start, finish, location)
  return {
    id = id,
    summary = summary,
    location = location,
    start = { dateTime = start },
    ['end'] = { dateTime = finish },
  }
end

local function all_day_event(id, summary)
  return {
    id = id,
    summary = summary,
    start = { date = '2026-10-28' },
    ['end'] = { date = '2026-10-29' },
  }
end

local function set_events(events)
  state.events_by_date = event.events_by_date(events, '2026-10-01', '2026-10-31')
  state.selected_date = '2026-10-28'
end

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.agenda), 0, -1, false)
end

describe('ui.agenda', function()
  before_each(function()
    state.reset()
    config.setup({})
    opened_detail = nil
    opened_delete = nil
    delete_opts = nil
    opened_help = nil

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 100
    vim.o.lines = 40

    original_local_datetime = rawget(event, 'local_datetime')
    rawset(event, 'local_datetime', fake_local_datetime)

    original_open_detail = agenda.openers.open_detail
    original_delete = agenda.openers.delete
    original_help = agenda.openers.help
    agenda.openers.open_detail = function(item)
      opened_detail = item
    end
    agenda.openers.delete = function(item, opts)
      opened_delete = item
      delete_opts = opts
    end
    agenda.openers.help = function(screen)
      opened_help = screen
    end
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
    state.reset()

    rawset(event, 'local_datetime', original_local_datetime)
    agenda.openers.open_detail = original_open_detail
    agenda.openers.delete = original_delete
    agenda.openers.help = original_help
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it(
    '選択日の予定を開始時刻順（終日が先頭）に並べ、ドット・開始時刻・タイトルを 1 行で表示する',
    function()
      set_events({
        timed_event('e3', 'ランチ', '2026-10-28T12:00:00+09:00', '2026-10-28T13:00:00+09:00'),
        all_day_event('e1', '休み'),
        timed_event('e2', '定例', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00', '会議室A'),
      })

      local win = agenda.open()

      local win_config = vim.api.nvim_win_get_config(win)
      local width, height = window.target_size(0.5, 0.7)
      assert.are.equal(width, win_config.width)
      assert.are.equal(height, win_config.height)
      assert.are.equal(win, vim.api.nvim_get_current_win())
      assert.are.equal('agenda', state.stack[#state.stack].name)
      assert.are.same({
        '● 終日 休み',
        '● 09:00 定例',
        '● 12:00 ランチ',
      }, buffer_lines())
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end
  )

  it('予定の色と状態に応じたドットを表示する', function()
    set_events({
      timed_event('e1', '通常', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00'),
      {
        id = 'e2',
        summary = '仮',
        status = 'tentative',
        start = { dateTime = '2026-10-28T10:00:00+09:00' },
        ['end'] = { dateTime = '2026-10-28T11:00:00+09:00' },
      },
      {
        id = 'e3',
        summary = '空き',
        transparency = 'transparent',
        start = { dateTime = '2026-10-28T11:00:00+09:00' },
        ['end'] = { dateTime = '2026-10-28T12:00:00+09:00' },
      },
      {
        id = 'e4',
        summary = '色付き',
        colorId = '6',
        start = { dateTime = '2026-10-28T12:00:00+09:00' },
        ['end'] = { dateTime = '2026-10-28T13:00:00+09:00' },
      },
    })

    agenda.open()

    assert.are.same({
      '● 09:00 通常',
      '○ 10:00 仮',
      '○ 11:00 空き',
      '● 12:00 色付き',
    }, buffer_lines())

    local buf = vim.api.nvim_win_get_buf(state.windows.agenda)
    local ns = vim.api.nvim_get_namespaces()['google-calendar-agenda']
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      table.insert(groups, mark[4].hl_group)
    end
    assert.are.same({
      'GoogleCalendarEventColor7',
      'GoogleCalendarEventColor7',
      'GoogleCalendarEventColor7',
      'GoogleCalendarEventColor6',
    }, groups)
  end)

  it('予定が 0 件の日は予定なしを表示し、<CR> では詳細を開かない', function()
    state.events_by_date = {}
    state.selected_date = '2026-10-28'

    local win = agenda.open()

    local _, height = window.target_size(0.5, 0.7)
    assert.are.equal(height, vim.api.nvim_win_get_config(win).height)
    assert.are.same({ '予定なし' }, buffer_lines())

    feed('<CR>')

    assert.is_nil(opened_detail)
    assert.are.same({ '予定なし' }, buffer_lines())
  end)

  it('j / k で予定の選択を移動し、<CR> で選択中の予定の詳細 opener を呼ぶ', function()
    set_events({
      timed_event('e1', '朝会', '2026-10-28T09:00:00+09:00', '2026-10-28T09:30:00+09:00'),
      timed_event('e2', '定例', '2026-10-28T10:00:00+09:00', '2026-10-28T11:00:00+09:00'),
      timed_event('e3', 'ランチ', '2026-10-28T12:00:00+09:00', '2026-10-28T13:00:00+09:00'),
    })

    local win = agenda.open()

    feed('j')
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(win))

    feed('j')
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(win))

    feed('<CR>')
    assert.are.equal('e3', opened_detail.id)

    feed('k')
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(win))

    feed('<CR>')
    assert.are.equal('e2', opened_detail.id)
  end)

  it('d で選択中の予定の削除確認を開き、削除後に一覧を更新する', function()
    local changed = false
    set_events({
      timed_event('e1', '朝会', '2026-10-28T09:00:00+09:00', '2026-10-28T09:30:00+09:00'),
      timed_event('e2', '定例', '2026-10-28T10:00:00+09:00', '2026-10-28T11:00:00+09:00'),
      timed_event('e3', 'ランチ', '2026-10-28T12:00:00+09:00', '2026-10-28T13:00:00+09:00'),
    })

    local win = agenda.open({
      on_changed = function()
        changed = true
      end,
    })

    feed('j')
    feed('j')
    feed('d')

    assert.are.equal('e3', opened_delete.id)
    assert.is_not_nil(delete_opts)
    assert.is_not_nil(delete_opts.on_finished)

    delete_opts.on_finished()

    assert.are.same({
      '● 09:00 朝会',
      '● 10:00 定例',
    }, buffer_lines())
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(win))
    assert.is_true(changed)
  end)

  it('q でアジェンダを閉じ、元の月表示へフォーカスが戻る', function()
    local parent = window.open('month', screen_opts)
    set_events({
      timed_event('e1', '定例', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00'),
    })

    local win = agenda.open()
    assert.are.equal(win, vim.api.nvim_get_current_win())

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_nil(state.windows.agenda)
    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.are.equal(1, #state.stack)
    assert.are.equal('month', state.stack[1].name)
  end)

  it('<Esc> でアジェンダを閉じる', function()
    local parent = window.open('month', screen_opts)
    set_events({
      timed_event('e1', '定例', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00'),
    })

    local win = agenda.open()

    feed('<Esc>')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
  end)

  it('? でアジェンダのヘルプ opener を呼ぶ', function()
    set_events({
      timed_event('e1', '定例', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00'),
    })

    agenda.open()

    feed('?')

    assert.are.equal('agenda', opened_help)
  end)

  it('q で詳細からアジェンダ、さらに q で月表示へ 1 段ずつ戻る', function()
    agenda.openers.open_detail = original_open_detail
    local parent = window.open('month', screen_opts)
    set_events({
      timed_event('e1', '定例', '2026-10-28T09:00:00+09:00', '2026-10-28T10:00:00+09:00'),
    })

    local agenda_win = agenda.open()
    feed('<CR>')

    local detail_win = state.windows.detail
    assert.is_true(vim.api.nvim_win_is_valid(detail_win))
    assert.are.equal(detail_win, vim.api.nvim_get_current_win())
    assert.are.equal(3, #state.stack)

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(detail_win))
    assert.are.equal(agenda_win, vim.api.nvim_get_current_win())

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(agenda_win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.are.equal(1, #state.stack)
  end)

  it('setup() で上書きしたキーで予定を選択し、アジェンダを閉じる', function()
    config.setup({ keymaps = { agenda = { next = 'n', close = 'Q', esc_close = false } } })
    local parent = window.open('month', screen_opts)
    set_events({
      timed_event('e1', '朝会', '2026-10-28T09:00:00+09:00', '2026-10-28T09:30:00+09:00'),
      timed_event('e2', '定例', '2026-10-28T10:00:00+09:00', '2026-10-28T11:00:00+09:00'),
    })

    local win = agenda.open()

    feed('<Esc>')
    assert.is_true(vim.api.nvim_win_is_valid(win))

    feed('n')
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(win))

    feed('Q')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
  end)

  it('予定が 25 件の日は設定した高さで表示し、j で最後の予定まで選択できる', function()
    local events = {}
    for index = 1, 25 do
      local minute = string.format('%02d', index)
      table.insert(
        events,
        timed_event(
          'e' .. index,
          '予定' .. index,
          '2026-10-28T09:' .. minute .. ':00+09:00',
          '2026-10-28T10:' .. minute .. ':00+09:00'
        )
      )
    end
    set_events(events)

    local win = agenda.open()
    local _, height = window.target_size(0.5, 0.7)
    assert.are.equal(height, vim.api.nvim_win_get_config(win).height)

    for _ = 1, 24 do
      feed('j')
    end

    assert.are.same({ 25, 0 }, vim.api.nvim_win_get_cursor(win))

    feed('<CR>')

    assert.are.equal('e25', opened_detail.id)
  end)
end)
