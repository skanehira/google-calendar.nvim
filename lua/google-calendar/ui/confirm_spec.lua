---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local confirm = require('google-calendar.ui.confirm')
local detail = require('google-calendar.ui.detail')
local event = require('google-calendar.event')
local notify_module = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local repo_root = vim.fn.getcwd()
local fake_gws = repo_root .. '/tests/fixtures/fake-gws.py'

local env_keys = {
  'FAKE_GWS_STATE',
  'FAKE_GWS_CALL_LOG',
  'FAKE_GWS_CWD_LOG',
  'FAKE_GWS_ERROR_FIXTURE',
}

local notifications = {}
local tmp_root
local state_path
local call_log
local saved_env
local saved_tz
local original_columns
local original_lines
local original_today
local original_local_datetime

local function notify(message, level)
  table.insert(notifications, { message = message, level = level })
end

local function new_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function read_lines(path)
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

local function fixture_items()
  local body = vim.json.decode(table.concat(vim.fn.readfile('tests/fixtures/events.json'), '\n'))
  return body.items
end

local function write_state(items)
  vim.fn.writefile({ vim.json.encode({ items = items }) }, state_path)
end

local function setup(opts)
  opts = opts or {}
  opts.gws_cmd = opts.gws_cmd or fake_gws
  opts.notify = opts.notify or notify
  opts.width = opts.width or 1.0
  opts.height = opts.height or 1.0
  config.setup(opts)
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function confirm_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.confirm), 0, -1, false)
end

local function wait_until(predicate)
  assert.is_true(vim.wait(10000, predicate, 10))
end

local function wait_loading()
  wait_until(function()
    return not state.loading
  end)
end

local function gws_calls()
  if vim.fn.filereadable(call_log) == 0 then
    return {}
  end

  local calls = {}
  for _, line in ipairs(read_lines(call_log)) do
    table.insert(calls, vim.json.decode(line))
  end
  return calls
end

local function delete_calls()
  local result = {}
  for _, call in ipairs(gws_calls()) do
    if call.argv[2] == 'events' and call.argv[3] == 'delete' then
      table.insert(result, call)
    end
  end
  return result
end

local function month_marks()
  local ns = vim.api.nvim_get_namespaces()['google-calendar-month']
  return vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(state.windows.month), ns, 0, -1, { details = true })
end

local function virt_lines(row_index)
  for _, mark in ipairs(month_marks()) do
    if mark[2] == row_index and mark[4].virt_lines ~= nil then
      return mark[4].virt_lines
    end
  end
  return nil
end

local function chunks_text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do
    table.insert(parts, chunk[1])
  end
  return table.concat(parts)
end

local function row(...)
  local cells = { ... }
  local padded = {}
  for _, cell in ipairs(cells) do
    table.insert(padded, cell .. string.rep(' ', 12 - vim.fn.strdisplaywidth(cell)))
  end
  return table.concat(padded, '│')
end

local WEEK_5_WITH_EVENT = row('', '', ' ● 09:00 定…', ' 終日', ' ● 13:00 Me…', '', '')
local WEEK_5_AFTER_DELETE = row('', '', '', ' 終日', ' ● 13:00 Me…', '', '')

local function full_event()
  return {
    id = 'evt-timed-1',
    summary = '定例',
    start = { dateTime = '2026-10-27T09:00:00+09:00' },
    ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
  }
end

local function open_month()
  write_state(fixture_items())
  vim.cmd('runtime! plugin/google-calendar.lua')
  vim.cmd('GoogleCalendar')
  wait_loading()
end

describe('ui.confirm', function()
  before_each(function()
    notifications = {}
    tmp_root = new_tmp_dir()
    state_path = tmp_root .. '/state.json'
    call_log = tmp_root .. '/call.log'
    saved_env = {}
    for _, key in ipairs(env_keys) do
      saved_env[key] = vim.env[key]
      vim.env[key] = nil
    end
    saved_tz = vim.env.TZ
    vim.env.TZ = 'Asia/Tokyo'
    vim.env.FAKE_GWS_STATE = state_path
    vim.env.FAKE_GWS_CALL_LOG = call_log

    state.reset()
    notify_module.reset()

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 94
    vim.o.lines = 39

    original_today = rawget(calendar, 'today')
    rawset(calendar, 'today', function()
      return '2026-10-27'
    end)

    original_local_datetime = rawget(event, 'local_datetime')
    rawset(event, 'local_datetime', function(value)
      return value:sub(1, 10), value:sub(12, 16)
    end)

    setup()
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
    state.reset()
    for _, key in ipairs(env_keys) do
      vim.env[key] = saved_env[key]
    end
    vim.env.TZ = saved_tz
    config.setup({})
    rawset(calendar, 'today', original_today)
    rawset(event, 'local_datetime', original_local_datetime)
    vim.o.columns = original_columns
    vim.o.lines = original_lines
    vim.fn.delete(tmp_root, 'rf')
  end)

  it('詳細で d を押すと、タイトルを含む削除の確認を開く', function()
    local item = full_event()
    local detail_win = detail.open(item)

    feed('d')

    local win = state.windows.confirm
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal('confirm', state.stack[#state.stack].name)
    assert.are.equal(detail_win, state.stack[#state.stack].parent)
    assert.are.same({
      '予定「定例」を削除しますか? (y/n)',
      'y:削除  n:キャンセル',
    }, confirm_lines())
  end)

  it('確認は長いタイトルを … で切り詰め、メッセージを 1 行に収める', function()
    local item = full_event()
    item.summary = string.rep('あ', 50)

    local win = confirm.open(item)

    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.same({
      '予定「' .. string.rep('あ', 20) .. '…」を削除しますか? (y/n)',
      'y:削除  n:キャンセル',
    }, confirm_lines())
  end)

  for _, case in ipairs({
    { key = 'n', label = 'n' },
    { key = '<Esc>', label = '<Esc>' },
    { key = 'q', label = 'q' },
  }) do
    it('確認で ' .. case.label .. ' を押すと確認を閉じ、予定を削除しない', function()
      local detail_win = detail.open(full_event())
      feed('d')
      local confirm_win = state.windows.confirm
      assert.is_true(vim.api.nvim_win_is_valid(confirm_win))

      feed(case.key)

      assert.is_false(vim.api.nvim_win_is_valid(confirm_win))
      assert.is_nil(state.windows.confirm)
      assert.is_true(vim.api.nvim_win_is_valid(detail_win))
      assert.are.equal(detail_win, vim.api.nvim_get_current_win())
      assert.are.equal('detail', state.stack[#state.stack].name)
      assert.are.equal(0, #delete_calls())
    end)
  end

  it(
    '詳細で y を押すと予定を削除し、確認と詳細を閉じ、月表示から予定を消す',
    function()
      open_month()

      assert.are.equal('2026-10-27', state.selected_date)
      assert.are.equal(WEEK_5_WITH_EVENT, chunks_text(assert(virt_lines(5))[1]))

      feed('<CR>')
      assert.are.equal('agenda', state.stack[#state.stack].name)
      assert.are.same(
        { '● 09:00 定例' },
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.agenda), 0, -1, false)
      )

      feed('<CR>')
      assert.are.equal('detail', state.stack[#state.stack].name)

      feed('d')
      assert.are.equal('confirm', state.stack[#state.stack].name)

      feed('y')
      wait_until(function()
        return state.windows.confirm == nil and state.windows.detail == nil and not state.loading
      end)

      assert.is_nil(state.windows.confirm)
      assert.is_nil(state.windows.detail)
      assert.are.equal('agenda', state.stack[#state.stack].name)
      assert.are.equal(state.windows.agenda, vim.api.nvim_get_current_win())

      local calls = gws_calls()
      assert.are.equal(3, #calls)
      assert.are.same({ 'calendar', 'events', 'list' }, { calls[1].argv[1], calls[1].argv[2], calls[1].argv[3] })
      assert.are.same({ 'calendar', 'events', 'delete' }, { calls[2].argv[1], calls[2].argv[2], calls[2].argv[3] })
      assert.are.equal('--params', calls[2].argv[4])
      assert.are.same({ calendarId = 'primary', eventId = 'evt-timed-1' }, vim.json.decode(calls[2].argv[5]))
      assert.are.same({ '--format', 'json' }, { calls[2].argv[6], calls[2].argv[7] })
      assert.are.same({ 'calendar', 'events', 'list' }, { calls[3].argv[1], calls[3].argv[2], calls[3].argv[3] })

      assert.are.same({
        { message = 'Event deleted', level = vim.log.levels.INFO },
      }, notifications)

      local ids = {}
      for _, item in ipairs(read_json(state_path).items) do
        table.insert(ids, item.id)
      end
      assert.are.same({ 'evt-all-day-1', 'evt-meet-1' }, ids)

      assert.is_nil(state.events_by_date['2026-10-27'])
      assert.are.same(
        { '予定なし' },
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.agenda), 0, -1, false)
      )
      assert.are.equal(WEEK_5_AFTER_DELETE, chunks_text(assert(virt_lines(5))[1]))
    end
  )

  it('y 以外のキーでは削除せず確認を開いたままにし、その後の y で削除する', function()
    write_state({ full_event() })

    local win = confirm.open(full_event())
    feed('h')

    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.same({
      '予定「定例」を削除しますか? (y/n)',
      'y:削除  n:キャンセル',
    }, confirm_lines())
    assert.are.equal(0, #delete_calls())

    feed('y')
    wait_until(function()
      return state.windows.confirm == nil
    end)

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(1, #delete_calls())
    assert.are.same({
      { message = 'Event deleted', level = vim.log.levels.INFO },
    }, notifications)
  end)

  it('二重に y を押しても削除は 1 回だけ実行する', function()
    local script = tmp_root .. '/slow-gws'
    vim.fn.writefile({
      '#!/bin/sh',
      'echo "$@" >> "$FAKE_GWS_CALL_LOG"',
      'sleep 1',
      'echo \'{"status":"success"}\'',
    }, script)
    vim.fn.setfperm(script, 'rwxr-xr-x')
    setup({ gws_cmd = script })

    local win = confirm.open(full_event())
    feed('y')

    assert.are.same({
      '予定「定例」を削除しますか? (y/n)',
      '削除中...',
    }, confirm_lines())

    feed('y')
    wait_until(function()
      return state.windows.confirm == nil
    end)

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(1, #read_lines(call_log))
    assert.are.same({
      { message = 'Event deleted', level = vim.log.levels.INFO },
    }, notifications)
  end)

  it(
    '削除に失敗した場合はエラーを通知し、確認を閉じず、予定を月表示に残す',
    function()
      open_month()

      feed('<CR>')
      feed('<CR>')
      feed('d')

      local error_fixture = tmp_root .. '/internal-error.json'
      vim.fn.writefile({
        vim.json.encode({
          error = { code = 500, message = 'Internal Server Error', reason = 'internalError' },
        }),
      }, error_fixture)
      vim.env.FAKE_GWS_ERROR_FIXTURE = error_fixture

      feed('y')
      wait_until(function()
        return #notifications > 0
      end)

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.confirm))
      assert.are.equal(state.windows.confirm, vim.api.nvim_get_current_win())
      assert.are.same({
        '予定「定例」を削除しますか? (y/n)',
        'y:削除  n:キャンセル',
      }, confirm_lines())
      assert.are.same({
        { message = 'Google Calendar API error: Internal Server Error', level = vim.log.levels.ERROR },
      }, notifications)
      assert.are.equal(1, #delete_calls())
      assert.are.equal(2, #gws_calls())
      assert.are.equal('定例', state.events_by_date['2026-10-27'][1].summary)
      assert.are.equal(WEEK_5_WITH_EVENT, chunks_text(assert(virt_lines(5))[1]))

      vim.env.FAKE_GWS_ERROR_FIXTURE = nil
      feed('y')
      wait_until(function()
        return state.windows.confirm == nil and state.windows.detail == nil and not state.loading
      end)

      assert.are.equal(2, #delete_calls())
      assert.is_nil(state.events_by_date['2026-10-27'])
      assert.are.same({
        { message = 'Google Calendar API error: Internal Server Error', level = vim.log.levels.ERROR },
        { message = 'Event deleted', level = vim.log.levels.INFO },
      }, notifications)
    end
  )

  it(
    '404 の場合は予定が既に削除されている旨を通知し、確認と詳細を閉じて月表示を再取得する',
    function()
      open_month()

      feed('<CR>')
      feed('<CR>')
      feed('d')

      vim.env.FAKE_GWS_ERROR_FIXTURE = repo_root .. '/tests/fixtures/api-error.json'

      feed('y')
      wait_until(function()
        return state.windows.confirm == nil and state.windows.detail == nil and not state.loading
      end)

      assert.are.same({
        { message = 'The event has already been deleted.', level = vim.log.levels.ERROR },
      }, notifications)
      local calls = gws_calls()
      assert.are.equal(3, #calls)
      assert.are.same({ 'calendar', 'events', 'delete' }, { calls[2].argv[1], calls[2].argv[2], calls[2].argv[3] })
      assert.are.same({ 'calendar', 'events', 'list' }, { calls[3].argv[1], calls[3].argv[2], calls[3].argv[3] })
      assert.are.equal('agenda', state.stack[#state.stack].name)
      assert.are.equal(state.windows.agenda, vim.api.nvim_get_current_win())
      assert.are.equal('定例', state.events_by_date['2026-10-27'][1].summary)
      assert.are.equal(WEEK_5_WITH_EVENT, chunks_text(assert(virt_lines(5))[1]))
    end
  )

  it('setup() で上書きしたキーで確認を操作し、esc_close=false では <Esc> で閉じない', function()
    setup({ keymaps = { confirm = { yes = 'Y', no = 'N', close = 'Q', esc_close = false } } })
    write_state({ full_event() })

    confirm.open(full_event())
    assert.are.same({
      '予定「定例」を削除しますか? (y/n)',
      'Y:削除  N:キャンセル',
    }, confirm_lines())

    feed('y')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.confirm))

    feed('<Esc>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.confirm))

    feed('Q')
    assert.is_nil(state.windows.confirm)
    assert.are.equal(0, #delete_calls())

    confirm.open(full_event())
    feed('N')
    assert.is_nil(state.windows.confirm)
    assert.are.equal(0, #delete_calls())

    confirm.open(full_event())
    feed('Y')
    wait_until(function()
      return state.windows.confirm == nil
    end)

    assert.are.equal(1, #delete_calls())
  end)
  it('on_finished を削除成功時に 1 回だけ呼び、キャンセル時は呼ばない', function()
    local item = {
      id = 'evt-on-finished',
      summary = '定例',
      start = { date = '2026-10-28' },
      ['end'] = { date = '2026-10-29' },
    }
    write_state({ item })

    local finished = 0
    confirm.open(item, {
      on_finished = function()
        finished = finished + 1
      end,
    })
    feed('n')

    assert.are.equal(0, finished)
    assert.is_nil(state.windows.confirm)

    confirm.open(item, {
      on_finished = function()
        finished = finished + 1
      end,
    })
    feed('y')
    wait_until(function()
      return state.windows.confirm == nil
    end)

    assert.are.equal(1, finished)
  end)
  it('確認ウィンドウの幅がメッセージとキーの表示幅に一致する', function()
    local item = {
      id = 'evt-confirm-width',
      summary = '短い',
      start = { date = '2026-10-28' },
      ['end'] = { date = '2026-10-29' },
    }

    local win = confirm.open(item)
    local lines = confirm_lines()
    local content_width = 0
    for _, line in ipairs(lines) do
      content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
    end

    assert.are.equal(math.min(70, vim.o.columns - 8, content_width + 2), vim.api.nvim_win_get_config(win).width)
    assert.are.equal(2, vim.api.nvim_win_get_config(win).height)
  end)
end)
