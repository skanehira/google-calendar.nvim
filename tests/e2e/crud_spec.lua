---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local month_view = require('google-calendar.ui.month_view')
local notify_module = require('google-calendar.notify')
local plugin = require('google-calendar')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local repo_root = vim.fn.getcwd()
local fake_gws = assert(vim.fn.exepath('gws'))
local fake_fixture = repo_root .. '/tests/fixtures/fake-gws.py'
local state_path = assert(vim.env.FAKE_GWS_STATE)
local call_log = assert(vim.env.FAKE_GWS_CALL_LOG)
local cwd_log = assert(vim.env.FAKE_GWS_CWD_LOG)
local auth_fixture = repo_root .. '/tests/fixtures/auth-error.json'
local api_fixture = repo_root .. '/tests/fixtures/api-error.json'
local cache_dir = vim.fn.stdpath('cache') .. '/google-calendar.nvim'

local notifications = {}
local original_columns
local original_lines

local function notify(message, level)
  table.insert(notifications, { message = message, level = level })
end

local function read_lines(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local file = assert(io.open(path, 'r'))
  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()
  return lines
end

local function read_json(path)
  local file = assert(io.open(path, 'r'))
  local content = file:read('*a')
  file:close()
  return vim.json.decode(content)
end

local function state_items()
  if vim.fn.filereadable(state_path) == 0 then
    return {}
  end

  local body = read_json(state_path)
  if body.items == nil or body.items == vim.NIL then
    return {}
  end
  return body.items
end

local function write_state(items)
  vim.fn.writefile({ vim.json.encode({ items = items }) }, state_path)
end

local function gws_calls()
  local calls = {}
  for _, line in ipairs(read_lines(call_log)) do
    table.insert(calls, vim.json.decode(line))
  end
  return calls
end

local function insert_calls()
  local result = {}
  for _, call in ipairs(gws_calls()) do
    if call.argv[2] == '+insert' or (call.argv[2] == 'events' and call.argv[3] == 'insert') then
      table.insert(result, call)
    end
  end
  return result
end

local function timed_raw(id, summary, date, start_time, end_time)
  return {
    id = id,
    summary = summary,
    start = { dateTime = calendar.rfc3339(date, start_time) },
    ['end'] = { dateTime = calendar.rfc3339(date, end_time) },
  }
end

local function all_day_raw(id, summary, start_date, end_date)
  return {
    id = id,
    summary = summary,
    start = { date = start_date },
    ['end'] = { date = end_date },
  }
end

local function close_all_windows()
  while #state.stack > 0 do
    window.close(state.stack[#state.stack].name)
  end
  state.reset()
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local WEEKDAYS = { '日', '月', '火', '水', '木', '金', '土' }

local function japanese_date(date)
  local year, month, day = calendar.date_parts(date)
  year, month, day = assert(year), assert(month), assert(day)
  local weekday = tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 })))
  return string.format('%d月%d日 (%s曜日)', month, day, WEEKDAYS[weekday + 1])
end

local function window_lines(name)
  local win = state.windows[name]
  assert.is_true(win ~= nil and vim.api.nvim_win_is_valid(win))
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function form_lines()
  return window_lines('form')
end

local function month_lines()
  return window_lines('month')
end

local function month_virt_lines()
  local rows = {}
  local win = state.windows.month
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return rows
  end

  local ns = vim.api.nvim_get_namespaces()['google-calendar-month']
  if ns == nil then
    return rows
  end

  local marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win), ns, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    if mark[4].virt_lines ~= nil and mark[4].virt_lines_above ~= true then
      rows[mark[2]] = mark[4].virt_lines
    end
  end
  return rows
end

local function chunks_text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    table.insert(parts, chunk[1])
  end
  return table.concat(parts)
end

local function rows_text(rows)
  local parts = {}
  for _, row in ipairs(rows) do
    table.insert(parts, chunks_text(row))
  end
  return table.concat(parts, '\n')
end

local function has_chunk(text, group)
  for _, rows in pairs(month_virt_lines()) do
    for _, row in ipairs(rows) do
      for _, chunk in ipairs(row) do
        if chunk[1] == text and (group == nil or chunk[2] == group) then
          return true
        end
      end
    end
  end
  return false
end

local function assert_month_matches_state()
  local cfg = config.get()
  local win = state.windows.month
  assert.is_true(win ~= nil and vim.api.nvim_win_is_valid(win))

  local cell_w = math.floor((vim.api.nvim_win_get_width(win) - 6) / 7)
  local grid = calendar.month_grid(state.year, state.month, cfg.week_start)
  local first_date = grid.weeks[1][1].date
  local last_date = grid.weeks[6][7].date
  local normalized = event.normalize_list(state_items(), { calendar_id = cfg.calendars[1] })
  local by_date = event.events_by_date(normalized, first_date, last_date)
  local layout = month_view.compute_layout(vim.o.columns, vim.o.lines, cfg)
  local expected =
    month_view.build_view(grid, by_date, cfg, calendar.today(), state.selected_date, cell_w, layout.rows_per_week)

  local actual = month_virt_lines()
  for week_index, week in ipairs(expected.weeks) do
    if #week.event_rows == 0 then
      assert.is_nil(actual[week_index])
    else
      assert.are.same(week.event_rows, actual[week_index])
    end
  end
end

local function edit_field(line, value)
  vim.api.nvim_set_current_win(state.windows.form)
  vim.api.nvim_win_set_cursor(state.windows.form, { line, 0 })
  feed('<CR><C-u>' .. value .. '<CR>')
end

local function wait_month_loaded()
  assert.is_true(vim.wait(10000, function()
    return not state.loading
  end, 10))
end

local function open_month(month)
  vim.cmd('GoogleCalendar ' .. month)
  wait_month_loaded()
end

describe('e2e crud', function()
  before_each(function()
    notifications = {}
    notify_module.reset()
    vim.env.FAKE_GWS_ERROR_FIXTURE = nil
    os.remove(state_path)
    os.remove(call_log)
    os.remove(cwd_log)

    close_all_windows()

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 100
    vim.o.lines = 40

    plugin.setup({ gws_cmd = fake_gws, notify = notify, width = 1.0, height = 1.0 })
    vim.cmd('runtime! plugin/google-calendar.lua')
  end)

  after_each(function()
    close_all_windows()
    vim.env.FAKE_GWS_ERROR_FIXTURE = nil
    vim.o.columns = original_columns
    vim.o.lines = original_lines
    plugin.setup({})
    notify_module.reset()
  end)

  it('E2E は setup({ gws_cmd = <fake> }) で偽 gws を指定し、実カレンダーを変更しない', function()
    local cfg = config.get()

    assert.are.equal(fake_gws, cfg.gws_cmd)
    assert.are.equal(fake_fixture, vim.fn.resolve(cfg.gws_cmd))
    assert.are.equal(fake_fixture, vim.fn.resolve(vim.fn.exepath('gws')))
    assert.is_true(vim.fn.executable(cfg.gws_cmd) == 1)
    assert.are.equal(0, #state_items())
  end)

  it('月表示を開き、登録・更新・削除を通しで検証する', function()
    open_month('2026-10')

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))
    assert.are.equal(7, #month_lines())
    assert.are.equal(
      '     日      │     月      │     火      │     水      │     木      │     金      │     土      ',
      month_lines()[1]
    )
    assert.are.equal(
      '           27│           28│           29│           30│            1│            2│            3',
      month_lines()[2]
    )
    assert.are.equal(0, #state_items())
    assert_month_matches_state()

    local date = state.selected_date

    feed('a')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('タイトル: ', form_lines()[1])
    edit_field(1, '登録1')
    edit_field(2, date .. ' 11:00')
    edit_field(3, date .. ' 12:00')
    feed('<F2>')
    assert.is_true(vim.wait(10000, function()
      return state.windows.form == nil and not state.loading
    end, 10))

    assert.are.same({ { message = '予定を作成しました', level = vim.log.levels.INFO } }, notifications)
    local items = state_items()
    assert.are.equal(1, #items)
    assert.are.equal('登録1', items[1].summary)
    assert.are.equal(calendar.rfc3339(date, '11:00'), items[1].start.dateTime)
    assert.are.equal(calendar.rfc3339(date, '12:00'), items[1]['end'].dateTime)
    assert_month_matches_state()
    assert.is_true(has_chunk(' 11:00 ', 'GoogleCalendarSelected'))
    assert.is_true(has_chunk('登録1', 'GoogleCalendarSelected'))

    feed('<CR>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.agenda))
    assert.are.same({ '● 11:00 登録1' }, window_lines('agenda'))
    feed('<CR>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.detail))
    assert.are.same({
      '▣ 登録1',
      '  ' .. japanese_date(date) .. '・11:00〜12:00',
      '',
      '▣ primary',
    }, window_lines('detail'))

    feed('e')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('タイトル: 登録1', form_lines()[1])
    edit_field(1, '更新2')
    feed('<F2>')
    assert.is_true(vim.wait(10000, function()
      return state.windows.form == nil and state.windows.detail == nil and not state.loading
    end, 10))

    assert.are.same({
      { message = '予定を作成しました', level = vim.log.levels.INFO },
      { message = '予定を更新しました', level = vim.log.levels.INFO },
    }, notifications)
    items = state_items()
    assert.are.equal(1, #items)
    assert.are.equal('更新2', items[1].summary)
    assert.are.equal(calendar.rfc3339(date, '11:00'), items[1].start.dateTime)
    assert.are.equal(calendar.rfc3339(date, '12:00'), items[1]['end'].dateTime)
    assert_month_matches_state()
    assert.is_true(has_chunk('更新2', 'GoogleCalendarSelected'))
    assert.is_false(has_chunk('登録1', 'GoogleCalendarEvent'))

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.agenda))
    feed('<CR>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.detail))
    assert.are.same({
      '▣ 更新2',
      '  ' .. japanese_date(date) .. '・11:00〜12:00',
      '',
      '▣ primary',
    }, window_lines('detail'))

    feed('d')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.confirm))
    assert.are.same({
      '予定「更新2」を削除しますか? (y/n)',
      'y:削除  n:キャンセル',
    }, window_lines('confirm'))
    feed('y')
    assert.is_true(vim.wait(10000, function()
      return state.windows.confirm == nil and state.windows.detail == nil and not state.loading
    end, 10))

    assert.are.equal(0, #state_items())
    assert_month_matches_state()
    local rows = month_virt_lines()
    local layout = month_view.compute_layout(vim.o.columns, vim.o.lines, config.get())
    assert.are.equal(6, #rows)
    for week = 1, 6 do
      assert.are.equal(layout.rows_per_week[week], #rows[week])
    end
    assert.is_false(has_chunk('更新2', 'GoogleCalendarSelected'))
    assert.are.same({
      { message = '予定を作成しました', level = vim.log.levels.INFO },
      { message = '予定を更新しました', level = vim.log.levels.INFO },
      { message = '予定を削除しました', level = vim.log.levels.INFO },
    }, notifications)
    assert.are.same({ cache_dir }, read_lines(cwd_log))
  end)

  it('予定 4 件以上の日は +N を表示し、月末と月初をまたいで表示する', function()
    write_state({
      timed_raw('evt-1', '予定1', '2026-10-31', '09:00', '10:00'),
      timed_raw('evt-2', '予定2', '2026-10-31', '10:00', '11:00'),
      timed_raw('evt-3', '予定3', '2026-10-31', '11:00', '12:00'),
      timed_raw('evt-4', '予定4', '2026-10-31', '12:00', '13:00'),
      all_day_raw('evt-5', 'またぎ', '2026-10-31', '2026-11-02'),
      timed_raw('evt-6', '月初', '2026-11-01', '09:00', '10:00'),
    })

    open_month('2026-10')

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))
    assert.are.equal(6, #state_items())
    assert_month_matches_state()
    assert.is_true(has_chunk(' +2', 'GoogleCalendarEvent'))
    assert.is_true(has_chunk(' 終日 ', 'GoogleCalendarEventTime'))
    assert.is_true(has_chunk('またぎ', 'GoogleCalendarEvent'))
    assert.is_true(has_chunk('月初', 'GoogleCalendarEvent'))
    assert.is_true(rows_text(month_virt_lines()[5]):find('+2', 1, true) ~= nil)
    assert.is_true(rows_text(month_virt_lines()[6]):find('月初', 1, true) ~= nil)
  end)

  it('偽 gws の認証エラー fixture では月表示を開かず通知する', function()
    vim.env.FAKE_GWS_ERROR_FIXTURE = auth_fixture

    vim.cmd('GoogleCalendar 2026-10')
    wait_month_loaded()

    assert.is_nil(state.windows.month)
    assert.are.equal(0, #state.stack)
    assert.are.same({
      {
        message = 'gws の認証が切れています。gws auth login を実行してください。',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
    assert.are.equal(0, #state_items())
    assert.are.equal(0, #insert_calls())
  end)

  it('作成失敗時はフォームを閉じず、入力値を保持してエラーを表示する', function()
    open_month('2026-10')
    feed('a')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    edit_field(1, '失敗する予定')
    vim.env.FAKE_GWS_ERROR_FIXTURE = api_fixture

    feed('<F2>')
    assert.is_true(vim.wait(10000, function()
      local win = state.windows.form
      if win == nil or not vim.api.nvim_win_is_valid(win) then
        return false
      end
      local footer = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 8, 9, false)[1]
      return footer ~= nil and footer:match('^エラー:') ~= nil
    end, 10))

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('タイトル: 失敗する予定', form_lines()[1])
    assert.are.equal('エラー: 予定を作成できませんでした: Not Found', form_lines()[9])
    assert.are.equal(0, #state_items())
    assert.are.same({
      { message = '予定を作成できませんでした: Not Found', level = vim.log.levels.ERROR },
    }, notifications)
  end)

  it('<F2> の連打で偽 gws の呼び出しは 1 回だけである', function()
    open_month('2026-10')
    feed('a')
    edit_field(1, '連打')
    os.remove(call_log)

    feed('<F2><F2>')
    assert.is_true(vim.wait(10000, function()
      return state.windows.form == nil and not state.loading
    end, 10))

    assert.are.equal(1, #insert_calls())
    assert.are.equal(1, #state_items())
    assert.are.equal('連打', state_items()[1].summary)
    assert_month_matches_state()
  end)
  it(
    'UI ジャーニー: 各画面のサイズとフォーカスが崩れず、insert の Esc でフォームが閉じない',
    function()
      open_month('2026-10')
      state.selected_date = '2026-10-28'
      write_state({ timed_raw('evt-ui-1', '定例', '2026-10-28', '09:00', '10:00') })
      feed('r')
      wait_month_loaded()

      local month_win = state.windows.month
      local month_config = vim.api.nvim_win_get_config(month_win)
      local content_lines = month_lines()
      local virt = 0
      for _, rows in pairs(month_virt_lines()) do
        virt = virt + #rows
      end
      local separators = 0
      local ns = vim.api.nvim_get_namespaces()['google-calendar-month']
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(month_win), ns, 0, -1, { details = true }))
      do
        if mark[4].virt_lines_above == true then
          separators = separators + 1
        end
      end
      assert.are.equal(#content_lines + virt + separators, month_config.height)
      assert.are.equal(vim.fn.strdisplaywidth(content_lines[1]), month_config.width)

      feed('<CR>')
      assert.are.equal('agenda', state.stack[#state.stack].name)
      assert.are.equal(math.floor((vim.o.lines - 2) * 0.7), vim.api.nvim_win_get_config(state.windows.agenda).height)

      feed('<CR>')
      assert.are.equal('detail', state.stack[#state.stack].name)
      assert.are.equal(math.floor((vim.o.lines - 2) * 0.5), vim.api.nvim_win_get_config(state.windows.detail).height)

      feed('e')
      assert.are.equal('form', state.stack[#state.stack].name)
      feed('<CR><C-u>変更<Esc>')
      assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
      feed('<Esc>')
      assert.is_nil(state.windows.form)
      assert.are.equal('detail', state.stack[#state.stack].name)

      feed('d')
      assert.are.equal('confirm', state.stack[#state.stack].name)
      assert.are.equal(2, vim.api.nvim_win_get_config(state.windows.confirm).height)
      feed('n')
      assert.are.equal('detail', state.stack[#state.stack].name)

      feed('?')
      assert.are.equal('help', state.stack[#state.stack].name)
      assert.are.equal(#window_lines('help'), vim.api.nvim_win_get_config(state.windows.help).height)
      feed('q')
      assert.are.equal('detail', state.stack[#state.stack].name)

      feed('q')
      assert.are.equal('agenda', state.stack[#state.stack].name)
      feed('q')
      assert.are.equal('month', state.stack[#state.stack].name)
      feed('q')
      assert.is_nil(state.windows.month)
    end
  )
end)
