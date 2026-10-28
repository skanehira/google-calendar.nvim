---@diagnostic disable: undefined-field
local plugin = require('google-calendar')
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local notify_module = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')
local month_view = require('google-calendar.ui.month_view')

local repo_root = vim.fn.getcwd()

local notifications = {}
local gws_calls = {}
local gws_handler
local pending_callbacks = {}
local openers = {}

local function notify(message, level)
  table.insert(notifications, { message = message, level = level })
end

local fake_gws = {
  list_events = function(opts, cb)
    table.insert(gws_calls, opts)
    gws_handler(opts, cb)
  end,
}

local fake_agenda = {
  open = function()
    openers.agenda = true
  end,
  refresh = function() end,
}

local fake_form = {
  open_create = function()
    openers.create = true
  end,
}

local fake_help = {
  open = function(screen)
    openers.help = screen
  end,
}

local previous_modules = {}
local function stub_module(name, value)
  if previous_modules[name] == nil then
    previous_modules[name] = { loaded = package.loaded[name] }
  end
  package.loaded[name] = value
end

local function restore_modules()
  for name, saved in pairs(previous_modules) do
    package.loaded[name] = saved.loaded
  end
  previous_modules = {}
end

local function override_field(module, field, value)
  local original = rawget(module, field)
  rawset(module, field, value)
  return original
end

local original_columns
local original_lines
local original_today
local original_local_datetime

local function offset_suffix()
  local offset = tostring(os.date('%z'))
  return offset:sub(1, 3) .. ':' .. offset:sub(4, 5)
end

local function timed_event(id, summary, start)
  return {
    id = id,
    summary = summary,
    start = { dateTime = start },
    ['end'] = { dateTime = start },
  }
end

local function run_command(args)
  if args == nil or args == '' then
    vim.cmd('GoogleCalendar')
  else
    vim.cmd('GoogleCalendar ' .. args)
  end
end

local function wait_loading()
  assert.is_true(vim.wait(2000, function()
    return not state.loading
  end, 10))
end

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function month_buf()
  return vim.api.nvim_win_get_buf(state.windows.month)
end

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(month_buf(), 0, -1, false)
end

local function window_title()
  local title = vim.api.nvim_win_get_config(state.windows.month).title
  if type(title) == 'string' then
    return title
  end

  local parts = {}
  for _, chunk in ipairs(title) do
    table.insert(parts, chunk[1])
  end
  return table.concat(parts)
end

local function month_marks()
  local ns = vim.api.nvim_get_namespaces()['google-calendar-month']
  return vim.api.nvim_buf_get_extmarks(month_buf(), ns, 0, -1, { details = true })
end

local function virt_lines(row)
  for _, mark in ipairs(month_marks()) do
    if mark[2] == row and mark[4].virt_lines ~= nil then
      return mark[4].virt_lines
    end
  end
  return nil
end

local function has_highlight(group, row, col)
  for _, mark in ipairs(month_marks()) do
    local details = mark[4]
    if details.hl_group == group and mark[2] == row and mark[3] == col then
      return true
    end
  end
  return false
end

local function chunks_text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    table.insert(parts, chunk[1])
  end
  return table.concat(parts)
end

local function has_chunk(line, text, group)
  for _, chunk in ipairs(line) do
    if chunk[1] == text and chunk[2] == group then
      return true
    end
  end
  return false
end

local function row(...)
  local cells = { ... }
  local padded = {}
  for _, cell in ipairs(cells) do
    table.insert(padded, cell .. string.rep(' ', 12 - vim.fn.strdisplaywidth(cell)))
  end
  return table.concat(padded, '│')
end

local OCTOBER_FIRST_WEEK =
  '          27│          28│          29│          30│           1│           2│           3'
local NOVEMBER_FIRST_WEEK =
  '           1│           2│           3│           4│           5│           6│           7'

describe('ui.month_view', function()
  before_each(function()
    notifications = {}
    gws_calls = {}
    pending_callbacks = {}
    openers = {}
    gws_handler = function(_, cb)
      cb({}, nil)
    end

    state.reset()
    notify_module.reset()
    stub_module('google-calendar.gws', fake_gws)
    stub_module('google-calendar.ui.agenda', fake_agenda)
    stub_module('google-calendar.ui.form', fake_form)
    stub_module('google-calendar.ui.help', fake_help)

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    -- 既存の期待値 (セル幅 12) を維持しつつ、余白のない幅・高さにする
    vim.o.columns = 94
    vim.o.lines = 39

    original_today = override_field(calendar, 'today', function()
      return '2026-10-28'
    end)

    original_local_datetime = override_field(event, 'local_datetime', function(value)
      return value:sub(1, 10), value:sub(12, 16)
    end)

    plugin.setup({
      notify = notify,
      width = 1.0,
      height = 1.0,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
    })
    vim.cmd('runtime! plugin/google-calendar.lua')
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
    state.reset()
    restore_modules()
    rawset(calendar, 'today', original_today)
    rawset(event, 'local_datetime', original_local_datetime)
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it(
    ':GoogleCalendar が当月の月表示 float を開き、タイトル・曜日ヘッダー・6 週分のセルを描画する',
    function()
      run_command()
      wait_loading()

      local win = state.windows.month
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.are.equal(win, vim.api.nvim_get_current_win())
      assert.are.equal(' Google Calendar — 2026年10月 — 選択: 10-28 ', window_title())
      assert.are.same({
        '     日     │     月     │     火     │     水     │     木     │     金     │     土     ',
        '          27│          28│          29│          30│           1│           2│           3',
        '           4│           5│           6│           7│           8│           9│          10',
        '          11│          12│          13│          14│          15│          16│          17',
        '          18│          19│          20│          21│          22│          23│          24',
        '          25│          26│          27│          28│          29│          30│          31',
        '           1│           2│           3│           4│           5│           6│           7',
      }, buffer_lines())
      assert.are.equal(2026, state.year)
      assert.are.equal(10, state.month)
      assert.are.equal('2026-10-28', state.selected_date)
      assert.are.equal(1, #state.stack)
      assert.are.same({
        calendar_id = 'primary',
        time_min = '2026-09-27T00:00:00' .. offset_suffix(),
        time_max = '2026-11-08T00:00:00' .. offset_suffix(),
      }, gws_calls[1])
    end
  )

  it('q で float を閉じ、元のウィンドウへフォーカスが戻る', function()
    local parent = vim.api.nvim_get_current_win()
    run_command()
    wait_loading()
    local win = state.windows.month

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.is_nil(state.windows.month)
    assert.are.equal(0, #state.stack)
  end)

  it('H で前月、L で次月へ移動し、タイトルと日付セルがその月になる', function()
    run_command()
    wait_loading()

    feed('L')
    wait_loading()

    assert.are.equal(2026, state.year)
    assert.are.equal(11, state.month)
    assert.are.equal('2026-11-28', state.selected_date)
    assert.are.equal(' Google Calendar — 2026年11月 — 選択: 11-28 ', window_title())
    assert.are.equal(NOVEMBER_FIRST_WEEK, buffer_lines()[2])
    assert.are.equal('2026-11-01T00:00:00' .. offset_suffix(), gws_calls[2].time_min)
    assert.are.equal('2026-12-13T00:00:00' .. offset_suffix(), gws_calls[2].time_max)

    feed('H')
    wait_loading()

    assert.are.equal(2026, state.year)
    assert.are.equal(10, state.month)
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.equal(' Google Calendar — 2026年10月 — 選択: 10-28 ', window_title())
    assert.are.equal(OCTOBER_FIRST_WEEK, buffer_lines()[2])
  end)

  it('t で今日を含む月に戻り、今日のセルが強調される', function()
    run_command('2026-11')
    wait_loading()
    assert.are.equal(11, state.month)

    feed('t')
    wait_loading()

    assert.are.equal(2026, state.year)
    assert.are.equal(10, state.month)
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.equal(' Google Calendar — 2026年10月 — 選択: 10-28 ', window_title())
    assert.is_true(has_highlight('GoogleCalendarToday', 5, 55))
    assert.is_true(has_highlight('GoogleCalendarSelected', 5, 45))
  end)

  it(':GoogleCalendar YYYY-MM が指定月の月表示を開く', function()
    run_command('2026-11')
    wait_loading()

    assert.are.equal(2026, state.year)
    assert.are.equal(11, state.month)
    assert.are.equal('2026-11-28', state.selected_date)
    assert.are.equal(' Google Calendar — 2026年11月 — 選択: 11-28 ', window_title())
    assert.are.equal(NOVEMBER_FIRST_WEEK, buffer_lines()[2])
    assert.are.equal('2026-11-01T00:00:00' .. offset_suffix(), gws_calls[1].time_min)
  end)

  it(
    '予定がある日は開始時刻とタイトルを最大 3 件表示し、4 件以上は +N を表示する',
    function()
      gws_handler = function(_, cb)
        cb({
          timed_event('e1', '定例', '2026-10-27T12:00:00+09:00'),
          timed_event('e2', '会議1', '2026-10-28T12:00:00+09:00'),
          timed_event('e3', '会議2', '2026-10-28T13:00:00+09:00'),
          timed_event('e4', '会議3', '2026-10-28T14:00:00+09:00'),
          timed_event('e5', '会議4', '2026-10-28T15:00:00+09:00'),
          timed_event('e6', '会議5', '2026-10-28T16:00:00+09:00'),
        }, nil)
      end

      run_command()
      wait_loading()

      local rows = assert(virt_lines(5))
      assert.are.equal(4, #rows)
      assert.are.equal(row('', '', ' 12:00 定例', ' 12:00 会議1', '', '', ''), chunks_text(rows[1]))
      assert.are.equal(row('', '', '', ' 13:00 会議2', '', '', ''), chunks_text(rows[2]))
      assert.are.equal(row('', '', '', ' 14:00 会議3', '', '', ''), chunks_text(rows[3]))
      assert.are.equal(row('', '', '', ' +2', '', '', ''), chunks_text(rows[4]))
      assert.are.equal(4, #assert(virt_lines(1)))
      assert.is_true(has_chunk(rows[1], ' 12:00 ', 'GoogleCalendarEventTime'))
      assert.is_true(has_chunk(rows[1], '定例', 'GoogleCalendarEvent'))
      assert.is_true(has_chunk(rows[4], ' +2', 'GoogleCalendarSelected'))
    end
  )

  it('予定がない日にはセルに予定の行を表示しない', function()
    gws_handler = function(_, cb)
      cb({ timed_event('e1', '定例', '2026-10-27T12:00:00+09:00') }, nil)
    end

    run_command()
    wait_loading()

    local rows = assert(virt_lines(5))
    assert.are.equal(4, #rows)
    assert.are.equal(row('', '', ' 12:00 定例', '', '', '', ''), chunks_text(rows[1]))
    for index = 2, 4 do
      assert.are.equal(row('', '', '', '', '', '', ''), chunks_text(rows[index]))
    end
    assert.are.equal(4, #assert(virt_lines(1)))
    assert.are.equal(4, #assert(virt_lines(2)))
  end)

  it('予定が 0 件の月はエラーにせず、全ての日に予定行を表示しない', function()
    run_command()
    wait_loading()

    assert.are.equal(0, #notifications)
    assert.are.same({}, state.events_by_date)
    assert.is_false(state.loading)
    assert.are.equal(7, #buffer_lines())
    for _, mark in ipairs(month_marks()) do
      if mark[4].virt_lines ~= nil and mark[4].virt_lines_above ~= true then
        assert.are.equal(4, #mark[4].virt_lines)
        for _, event_row in ipairs(mark[4].virt_lines) do
          assert.are.equal(row('', '', '', '', '', '', ''), chunks_text(event_row))
        end
      end
    end
  end)

  it('API エラー時はエラー内容を通知し、取得済みの表示を維持する', function()
    local call = 0
    gws_handler = function(_, cb)
      call = call + 1
      if call == 1 then
        cb({ timed_event('e1', '定例', '2026-10-27T12:00:00+09:00') }, nil)
      else
        cb(nil, { kind = 'api', code = 500, message = 'Backend Error', reason = 'backendError' })
      end
    end

    run_command()
    wait_loading()
    assert.are.equal(4, #assert(virt_lines(5)))

    feed('r')
    wait_loading()

    assert.are.equal(1, #notifications)
    assert.are.equal('Google Calendar API エラー: Backend Error', notifications[1].message)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.equal(4, #assert(virt_lines(5)))
    assert.are.equal(gws_calls[1].time_min, gws_calls[2].time_min)
  end)

  it('不正な YYYY-MM は通知して月表示を開かない', function()
    run_command('2026-13')

    assert.are.equal(1, #notifications)
    assert.are.equal('月の指定は YYYY-MM 形式で入力してください', notifications[1].message)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.is_nil(state.windows.month)
    assert.are.equal(0, #gws_calls)

    run_command('2026-1')

    assert.are.equal(2, #notifications)
    assert.are.equal('月の指定は YYYY-MM 形式で入力してください', notifications[2].message)
    assert.is_nil(state.windows.month)
  end)

  it('偽 gws の認証エラー fixture では通知だけを出し、月表示を開かない', function()
    local body = vim.json.decode(table.concat(vim.fn.readfile('tests/fixtures/auth-error.json'), '\n'))
    gws_handler = function(_, cb)
      cb(nil, {
        kind = 'auth',
        code = body.error.code,
        message = body.error.message,
        reason = body.error.reason,
      })
    end

    run_command()
    wait_loading()

    assert.are.equal(1, #notifications)
    assert.are.equal(
      'gws の認証が切れています。gws auth login を実行してください。',
      notifications[1].message
    )
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.is_nil(state.windows.month)
    assert.are.equal(0, #state.stack)
    assert.is_false(state.loading)
  end)

  it('<CR> / a / ? がアジェンダ・登録フォーム・ヘルプの opener を呼ぶ', function()
    run_command()
    wait_loading()

    feed('<CR>')
    assert.is_true(openers.agenda)

    feed('a')
    assert.is_true(openers.create)

    feed('?')
    assert.are.equal('month', openers.help)
  end)

  it('h/l/j/k で選択日を移動し、月をまたぐと表示月も切り替える', function()
    run_command()
    wait_loading()

    feed('l')
    assert.are.equal('2026-10-29', state.selected_date)
    assert.are.equal(1, #gws_calls)

    feed('h')
    assert.are.equal('2026-10-28', state.selected_date)

    feed('j')
    wait_loading()
    assert.are.equal(2026, state.year)
    assert.are.equal(11, state.month)
    assert.are.equal('2026-11-04', state.selected_date)
    assert.are.equal(' Google Calendar — 2026年11月 — 選択: 11-04 ', window_title())
    assert.are.equal(2, #gws_calls)

    feed('k')
    wait_loading()
    assert.are.equal(2026, state.year)
    assert.are.equal(10, state.month)
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.equal(2, #gws_calls)
  end)

  it('取得中はキー操作を無視し、ヘッダーに読み込み中を表示する', function()
    gws_handler = function(_, cb)
      table.insert(pending_callbacks, cb)
    end

    run_command()

    assert.is_true(state.loading)
    assert.are.equal(' Google Calendar — 2026年10月 — 選択: 10-28 — 読み込み中... ', window_title())

    feed('l')
    assert.are.equal('2026-10-28', state.selected_date)

    feed('q')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))

    pending_callbacks[1]({}, nil)
    wait_loading()
    assert.are.equal(' Google Calendar — 2026年10月 — 選択: 10-28 ', window_title())

    feed('l')
    assert.are.equal('2026-10-29', state.selected_date)
  end)

  it('セル幅が 7 未満になる場合は通知して開かない', function()
    vim.o.columns = 20

    run_command()

    assert.are.equal(1, #notifications)
    assert.are.equal('ウィンドウが狭すぎます', notifications[1].message)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.is_nil(state.windows.month)
    assert.are.equal(0, #gws_calls)
  end)

  it(':GoogleCalendar を再度実行すると既存の月表示を再利用してフォーカスする', function()
    local parent = vim.api.nvim_get_current_win()
    run_command()
    wait_loading()
    local win = state.windows.month

    vim.api.nvim_set_current_win(parent)
    run_command()
    wait_loading()

    assert.are.equal(1, #gws_calls)
    assert.are.equal(1, #state.stack)
    assert.are.equal(win, state.windows.month)
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal('2026-10-28', state.selected_date)
  end)
  it('<Esc> でも閉じ、esc_close の上書きと false を反映する', function()
    run_command()
    wait_loading()
    local win = state.windows.month
    feed('<Esc>')
    assert.is_false(vim.api.nvim_win_is_valid(win))

    plugin.setup({
      notify = notify,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
      keymaps = { month = { esc_close = '<C-x>' } },
    })
    run_command()
    wait_loading()
    win = state.windows.month
    feed('<Esc>')
    assert.is_true(vim.api.nvim_win_is_valid(win))
    feed('<C-x>')
    assert.is_false(vim.api.nvim_win_is_valid(win))

    plugin.setup({
      notify = notify,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
      keymaps = { month = { esc_close = false } },
    })
    run_command()
    wait_loading()
    win = state.windows.month
    feed('<Esc>')
    assert.is_true(vim.api.nvim_win_is_valid(win))
    feed('q')
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  it('タイトル・ボーダー・選択セル・チップ背景にハイライトを適用する', function()
    gws_handler = function(_, cb)
      cb({ timed_event('e1', '定例', '2026-10-27T09:00:00+09:00') }, nil)
    end
    run_command()
    wait_loading()

    local win = state.windows.month
    assert.are.equal('FloatBorder:GoogleCalendarBorder,FloatTitle:GoogleCalendarHeader', vim.wo[win].winhl)
    assert.is_true(has_highlight('GoogleCalendarHeader', 0, 0))
    assert.is_true(has_highlight('GoogleCalendarSunday', 2, 11))
    assert.is_true(has_highlight('GoogleCalendarSaturday', 1, 101))
    assert.is_true(has_highlight('GoogleCalendarOtherMonth', 1, 10))
    assert.is_true(has_highlight('GoogleCalendarSelected', 5, 45))

    local rows = assert(virt_lines(5))
    assert.is_true(has_chunk(rows[1], '定例', 'GoogleCalendarEvent'))
    for index, chunk in ipairs(rows[1]) do
      if chunk[1] == '定例' and chunk[2] == 'GoogleCalendarEvent' then
        assert.are.equal('GoogleCalendarEvent', rows[1][index + 1][2])
      end
    end
  end)

  it('4 件以上の予定 fixture を +N 表示で扱う', function()
    local body = vim.json.decode(table.concat(vim.fn.readfile('tests/fixtures/many-events.json'), '\n'))
    local events = event.normalize_list(body.items, { calendar_id = 'primary' })
    gws_handler = function(_, cb)
      cb(events, nil)
    end

    run_command()
    wait_loading()

    local rows = assert(virt_lines(5))
    assert.is_true(has_chunk(rows[4], ' +2', 'GoogleCalendarSelected'))
  end)

  it('取得中は移動・再取得・opener・close の全キーを無視する', function()
    gws_handler = function(_, cb)
      table.insert(pending_callbacks, cb)
    end
    run_command()

    assert.is_true(state.loading)
    for _, key in ipairs({ 'h', 'l', 'j', 'k', 'H', 'L', 't', 'r', 'a', '?', '<CR>', '<Esc>', 'q' }) do
      feed(key)
    end

    assert.are.equal(2026, state.year)
    assert.are.equal(10, state.month)
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.same({}, openers)
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))

    pending_callbacks[1]({}, nil)
    wait_loading()
  end)

  it('H/L で月末をクランプする', function()
    run_command('2026-01')
    wait_loading()
    assert.are.equal('2026-01-28', state.selected_date)

    feed('l')
    feed('l')
    feed('l')
    assert.are.equal('2026-01-31', state.selected_date)

    feed('L')
    wait_loading()
    assert.are.equal(2026, state.year)
    assert.are.equal(2, state.month)
    assert.are.equal('2026-02-28', state.selected_date)
  end)

  it('古いリクエストの応答を破棄する', function()
    gws_handler = function(_, cb)
      table.insert(pending_callbacks, cb)
    end
    run_command()
    run_command('2026-11')

    pending_callbacks[1]({ timed_event('e1', '10月', '2026-10-28T09:00:00+09:00') }, nil)
    vim.wait(100)
    assert.are.equal(2026, state.year)
    assert.are.equal(11, state.month)
    assert.are.equal('2026-11-28', state.selected_date)

    pending_callbacks[2]({}, nil)
    wait_loading()
    assert.are.equal(11, state.month)
  end)

  it('r で表示中の月を再取得する', function()
    run_command()
    wait_loading()
    assert.are.equal(1, #gws_calls)

    feed('r')
    wait_loading()
    assert.are.equal(2, #gws_calls)
  end)

  it('外部でウィンドウ幅が変わっても設定した幅に戻す', function()
    plugin.setup({
      notify = notify,
      width = 0.7,
      height = 1.0,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
    })
    run_command()
    wait_loading()

    local layout = month_view.compute_layout(vim.o.columns, vim.o.lines, config.get())
    window.resize(state.windows.month, vim.o.columns - 2, layout.win_height)
    assert.are.equal(vim.o.columns - 2, vim.api.nvim_win_get_width(state.windows.month))

    feed('r')
    wait_loading()
    assert.are.equal(layout.win_width, vim.api.nvim_win_get_width(state.windows.month))
  end)

  it('取得済みの月に戻るときはキャッシュを使い、gws を呼ばない', function()
    run_command()
    wait_loading()
    assert.are.equal(1, #gws_calls)

    feed('L')
    wait_loading()
    assert.are.equal(2, #gws_calls)

    feed('H')
    wait_loading()
    assert.are.equal(2, #gws_calls)

    feed('L')
    wait_loading()
    assert.are.equal(2, #gws_calls)
  end)

  it('R でも表示中の月を再取得する', function()
    run_command()
    wait_loading()
    assert.are.equal(1, #gws_calls)

    feed('R')
    wait_loading()
    assert.are.equal(2, #gws_calls)
  end)

  it('月表示を閉じるとキャッシュを破棄する', function()
    run_command()
    wait_loading()
    assert.are.equal(1, #gws_calls)

    feed('q')
    assert.is_nil(state.windows.month)

    run_command()
    wait_loading()
    assert.are.equal(2, #gws_calls)
  end)

  it('エラー → 成功 → 同じエラーで 2 回目の通知も出す', function()
    local call = 0
    gws_handler = function(_, cb)
      call = call + 1
      if call == 1 or call == 3 then
        cb({}, nil)
      else
        cb(nil, { kind = 'network' })
      end
    end

    run_command()
    wait_loading()
    feed('r')
    wait_loading()
    feed('r')
    wait_loading()
    feed('r')
    wait_loading()

    assert.are.equal(4, #gws_calls)
    assert.are.equal(2, #notifications)
    assert.are.equal(
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
      notifications[1].message
    )
    assert.are.equal(notifications[1].message, notifications[2].message)
  end)

  it('month.close の上書きと false を反映する', function()
    plugin.setup({
      notify = notify,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
      keymaps = { month = { close = 'Q' } },
    })
    run_command()
    wait_loading()
    local win = state.windows.month
    feed('q')
    assert.is_true(vim.api.nvim_win_is_valid(win))
    feed('Q')
    assert.is_false(vim.api.nvim_win_is_valid(win))

    plugin.setup({
      notify = notify,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
      keymaps = { month = { close = false } },
    })
    run_command()
    wait_loading()
    win = state.windows.month
    feed('q')
    assert.is_true(vim.api.nvim_win_is_valid(win))
    feed('<Esc>')
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)
  it('ウィンドウが内容の行数・幅に一致し、下部・右側に空白を残さない', function()
    local events = {}
    for index = 1, 5 do
      table.insert(events, timed_event('e' .. index, '予定' .. index, '2026-10-28T' .. (8 + index) .. ':00:00+09:00'))
    end
    gws_handler = function(_, cb)
      cb(events, nil)
    end

    run_command()
    wait_loading()

    local win = state.windows.month
    local win_config = vim.api.nvim_win_get_config(win)
    local lines = buffer_lines()
    local virt = 0
    for _, mark in ipairs(month_marks()) do
      if mark[4].virt_lines ~= nil then
        virt = virt + #mark[4].virt_lines
      end
    end

    assert.are.equal(#lines + virt, win_config.height)
    assert.are.equal(vim.fn.strdisplaywidth(lines[1]), win_config.width)
  end)

  it('各週の上に横線を引き、セルのグリッドを作る', function()
    run_command()
    wait_loading()

    local header_width = vim.fn.strdisplaywidth(buffer_lines()[1])
    local count = 0
    for _, mark in ipairs(month_marks()) do
      if mark[4].virt_lines_above == true then
        local line = mark[4].virt_lines[1][1][1]
        assert.are.equal(header_width, vim.fn.strdisplaywidth(line))
        assert.is_not_nil(line:find('┼', 1, true))
        count = count + 1
      end
    end
    assert.are.equal(6, count)
  end)

  it('画面いっぱいに広がり、余った高さを各週に配分する', function()
    vim.o.columns = 120
    vim.o.lines = 40

    run_command()
    wait_loading()

    local layout = month_view.compute_layout(vim.o.columns, vim.o.lines, config.get())
    assert.are.equal(118, layout.win_width)
    assert.are.equal(38, layout.win_height)
    assert.are.equal(16, layout.cell_w)
    assert.are.same({ 5, 4, 4, 4, 4, 4 }, layout.rows_per_week)

    local win_config = vim.api.nvim_win_get_config(state.windows.month)
    assert.are.equal(118, win_config.width)
    assert.are.equal(38, win_config.height)
    assert.are.equal(0, win_config.row)
    assert.are.equal(0, win_config.col)

    assert.are.equal(5, #assert(virt_lines(1)))
    assert.are.equal(6, vim.api.nvim_win_get_cursor(state.windows.month)[1])

    local small = month_view.compute_layout(120, 40, {
      width = 0.8,
      height = 0.8,
      max_events_per_cell = 3,
    })
    assert.are.equal(90, small.win_width)
    assert.are.equal(30, small.win_height)

    local default = month_view.compute_layout(120, 40, {
      width = 0.7,
      height = 0.7,
      max_events_per_cell = 3,
    })
    assert.are.equal(76, default.win_width)
    assert.are.equal(26, default.win_height)
  end)

  it('取得中と取得完了でウィンドウの高さが変わらない', function()
    gws_handler = function(_, cb)
      table.insert(pending_callbacks, cb)
    end

    run_command()
    local win = state.windows.month
    local expected = 1 + 6 + 6 + 6 * (config.get().max_events_per_cell + 1)
    expected = math.min(expected, vim.o.lines - 2)

    assert.is_true(state.loading)
    assert.are.equal(expected, vim.api.nvim_win_get_config(win).height)

    pending_callbacks[1]({}, nil)
    wait_loading()

    assert.are.equal(expected, vim.api.nvim_win_get_config(win).height)
  end)

  it('選択セルを全幅で目立つ背景にする', function()
    gws_handler = function(_, cb)
      cb({ timed_event('e1', '定例', '2026-10-28T09:00:00+09:00') }, nil)
    end

    run_command()
    wait_loading()

    local highlight = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarSelected', link = false })
    assert.are.equal(tonumber('7aa2f7', 16), highlight.bg)
    assert.is_true(highlight.bold)

    local selected
    for _, mark in ipairs(month_marks()) do
      if mark[4].hl_group == 'GoogleCalendarSelected' then
        selected = mark
      end
    end
    assert.is_not_nil(selected)

    local win_config = vim.api.nvim_win_get_config(state.windows.month)
    local cell_w = math.floor((win_config.width - 6) / 7)
    assert.are.equal(cell_w, selected[4].end_col - selected[3])
  end)
  it('選択中のセルの日付行と予定行を全体ハイライトする', function()
    gws_handler = function(_, cb)
      cb({
        timed_event('e1', '定例', '2026-10-28T09:00:00+09:00'),
        timed_event('e2', '別の予定', '2026-10-29T10:00:00+09:00'),
      }, nil)
    end

    run_command()
    wait_loading()

    assert.are.equal(
      '          25│          26│          27│          28│          29│          30│          31',
      buffer_lines()[6]
    )

    local rows = assert(virt_lines(5))
    assert.is_true(#rows > 0)

    local function cell_chunks(chunks)
      local cells = {}
      local current = {}
      for _, chunk in ipairs(chunks) do
        if chunk[1] == '│' then
          table.insert(cells, current)
          current = {}
        else
          table.insert(current, chunk)
        end
      end
      table.insert(cells, current)
      return cells
    end

    for _, event_row in ipairs(rows) do
      local cells = cell_chunks(event_row)
      -- 2026-10-28 は水曜 (日曜始まりで 4 番目)
      for _, chunk in ipairs(cells[4]) do
        assert.are.equal('GoogleCalendarSelected', chunk[2])
      end
      for _, chunk in ipairs(cells[5]) do
        assert.are_not.equal('GoogleCalendarSelected', chunk[2])
      end
    end
  end)
  it('height が小さいときも選択中の週が見えるようにスクロールする', function()
    vim.o.columns = 120
    vim.o.lines = 40
    plugin.setup({
      notify = notify,
      width = 0.7,
      height = 0.7,
      gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py',
    })

    run_command()
    wait_loading()

    local win = state.windows.month
    assert.are.equal(26, vim.api.nvim_win_get_config(win).height)
    assert.are.equal('2026-10-28', state.selected_date)
    assert.are.equal(6, vim.api.nvim_win_get_cursor(win)[1])
  end)
end)
