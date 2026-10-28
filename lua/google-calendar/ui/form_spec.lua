---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local form = require('google-calendar.ui.form')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local repo_root = vim.fn.getcwd()
local fake_gws = repo_root .. '/tests/fixtures/fake-gws.py'

local env_keys = {
  'FAKE_GWS_STATE',
  'FAKE_GWS_CALL_LOG',
  'FAKE_GWS_CWD_LOG',
  'FAKE_GWS_ERROR_FIXTURE',
  'FAKE_GWS_PAGE_SIZE',
}

local notifications = {}
local captured_created
local tmp_root
local state_path
local call_log
local saved_env
local original_columns
local original_lines
local original_today

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

local function write_script(path, lines)
  vim.fn.writefile(lines, path)
  vim.fn.setfperm(path, 'rwxr-xr-x')
end

local function setup(opts)
  opts = opts or {}
  opts.gws_cmd = opts.gws_cmd or fake_gws
  opts.notify = opts.notify or notify
  config.setup(opts)
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function form_buf()
  return vim.api.nvim_win_get_buf(state.windows.form)
end

local function form_lines()
  return vim.api.nvim_buf_get_lines(form_buf(), 0, -1, false)
end

local function footer()
  return form_lines()[9]
end

local function cursor_line()
  return vim.api.nvim_win_get_cursor(state.windows.form)[1]
end

local function select_field(line)
  vim.api.nvim_set_current_win(state.windows.form)
  vim.api.nvim_win_set_cursor(state.windows.form, { line, 0 })
end

local function edit_field(line, value)
  select_field(line)
  feed('<CR><C-u>' .. value .. '<CR>')
end

local FIELD_PREFIXES = {
  'タイトル: ',
  '開始:     ',
  '終了:     ',
  '終日:     ',
  '場所:     ',
  '説明:     ',
  'Meet:     ',
}

local function set_field(line, value)
  local buf = form_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { FIELD_PREFIXES[line] .. value })
  vim.bo[buf].modifiable = false
end

local function press_save()
  feed('<F2>')
end

local function wait_form_closed()
  assert.is_true(vim.wait(10000, function()
    return state.windows.form == nil
  end, 10))
end

local function wait_form_error()
  assert.is_true(vim.wait(10000, function()
    local win = state.windows.form
    if win == nil or not vim.api.nvim_win_is_valid(win) then
      return false
    end
    local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 8, 9, false)[1]
    return line ~= nil and line:match('^エラー:') ~= nil
  end, 10))
end

local function wait_month_loading()
  assert.is_true(vim.wait(10000, function()
    return not state.loading
  end, 10))
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

local function insert_calls()
  local result = {}
  for _, call in ipairs(gws_calls()) do
    if call.argv[2] == '+insert' or (call.argv[2] == 'events' and call.argv[3] == 'insert') then
      table.insert(result, call)
    end
  end
  return result
end

local function error_marks()
  local ns = vim.api.nvim_get_namespaces()['google-calendar-form']
  if ns == nil or state.windows.form == nil then
    return {}
  end
  return vim.api.nvim_buf_get_extmarks(form_buf(), ns, 0, -1, { details = true })
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

local function offset_suffix()
  local offset = tostring(os.date('%z'))
  return offset:sub(1, 3) .. ':' .. offset:sub(4, 5)
end

local function initial_lines(date)
  return {
    'タイトル: ',
    '開始:     ' .. date .. ' 09:00',
    '終了:     ' .. date .. ' 10:00',
    '終日:     off',
    '場所:     ',
    '説明:     ',
    'Meet:     off',
    '',
    '<Tab>/<S-Tab>:移動  <CR>:編集  <Space>:切替  <F2>:保存  <Esc>:取消',
  }
end

describe('ui.form', function()
  before_each(function()
    notifications = {}
    captured_created = nil
    tmp_root = new_tmp_dir()
    state_path = tmp_root .. '/state.json'
    call_log = tmp_root .. '/call.log'
    saved_env = {}
    for _, key in ipairs(env_keys) do
      saved_env[key] = vim.env[key]
      vim.env[key] = nil
    end
    vim.env.FAKE_GWS_STATE = state_path
    vim.env.FAKE_GWS_CALL_LOG = call_log

    state.reset()
    state.selected_date = '2026-10-28'

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 100
    vim.o.lines = 40

    original_today = rawget(calendar, 'today')
    rawset(calendar, 'today', function()
      return '2026-10-28'
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
    config.setup({})
    rawset(calendar, 'today', original_today)
    vim.o.columns = original_columns
    vim.o.lines = original_lines
    vim.fn.delete(tmp_root, 'rf')
  end)

  it('月表示で選んだ日を開始日として 09:00〜10:00 の登録フォームを開く', function()
    local win = form.open_create()

    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal(win, state.windows.form)
    assert.are.same(initial_lines('2026-10-28'), form_lines())
    assert.are.equal(1, cursor_line())
    assert.are.equal('form', state.stack[#state.stack].name)
  end)

  it('選択日が変わると開始日と終了日の初期値もその日になる', function()
    state.selected_date = '2026-11-03'

    form.open_create()

    assert.are.same(initial_lines('2026-11-03'), form_lines())
  end)

  it('<Tab> と <S-Tab> でフィールドの選択を前後に移動する', function()
    form.open_create()

    feed('<Tab>')
    assert.are.equal(2, cursor_line())

    feed('<Tab>')
    assert.are.equal(3, cursor_line())

    feed('<S-Tab>')
    assert.are.equal(2, cursor_line())

    feed('<S-Tab>')
    assert.are.equal(1, cursor_line())

    feed('<S-Tab>')
    assert.are.equal(7, cursor_line())

    feed('<Tab>')
    assert.are.equal(1, cursor_line())
  end)

  it('<CR> でテキストフィールドの末尾から入力できる', function()
    form.open_create()

    edit_field(1, '定例ミーティング')

    assert.are.equal('タイトル: 定例ミーティング', form_lines()[1])
    assert.is_false(vim.bo[form_buf()].modifiable)
  end)

  it('<Space> で終日を切り替え、開始・終了を日付形式にする', function()
    form.open_create()

    select_field(4)
    feed('<Space>')

    assert.are.equal('終日:     on', form_lines()[4])
    assert.are.equal('開始:     2026-10-28', form_lines()[2])
    assert.are.equal('終了:     2026-10-29', form_lines()[3])

    feed('<Space>')

    assert.are.equal('終日:     off', form_lines()[4])
    assert.are.equal('開始:     2026-10-28 09:00', form_lines()[2])
    assert.are.equal('終了:     2026-10-28 10:00', form_lines()[3])
  end)

  it('<Space> で Meet を切り替える', function()
    form.open_create()

    select_field(7)
    feed('<Space>')
    assert.are.equal('Meet:     on', form_lines()[7])

    feed('<Space>')
    assert.are.equal('Meet:     off', form_lines()[7])
  end)

  it(
    'タイトルが空のまま <F2> を押すとエラーを表示し、gws を呼ばず、入力後は作成する',
    function()
      form.open_create()

      press_save()

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
      assert.are.equal('エラー: タイトルを入力してください', footer())
      local marks = error_marks()
      assert.are.equal(1, #marks)
      assert.are.equal(0, marks[1][2])
      assert.are.equal(#form_lines()[1], marks[1][4].end_col)
      assert.are.equal('GoogleCalendarError', marks[1][4].hl_group)
      assert.are.equal(0, #insert_calls())

      edit_field(1, '定例')
      press_save()
      wait_form_closed()

      assert.are.equal(1, #insert_calls())
      assert.are.same({ message = '予定を作成しました', level = vim.log.levels.INFO }, notifications[1])
    end
  )

  it('タイトルが 1024 文字を超える場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    set_field(1, string.rep('あ', 1025))

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: タイトルは 1024 文字以内で入力してください', footer())
    assert.are.equal(0, #insert_calls())

    set_field(1, '定例')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('場所が 1024 文字を超える場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '定例')
    set_field(5, string.rep('あ', 1025))

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 場所は 1024 文字以内で入力してください', footer())
    assert.are.equal(0, #insert_calls())

    set_field(5, '会議室A')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('説明が 8192 文字を超える場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '定例')
    set_field(6, string.rep('あ', 8193))

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 説明は 8192 文字以内で入力してください', footer())
    assert.are.equal(0, #insert_calls())

    set_field(6, '週次の進捗確認')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('開始日時が形式に合わない場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '定例')
    edit_field(2, '2026-10-28 9:00')

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 開始日時は YYYY-MM-DD HH:MM 形式で入力してください', footer())
    assert.are.equal(0, #insert_calls())

    edit_field(2, '2026-10-28 09:00')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('終了日時が形式に合わない場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '定例')
    edit_field(3, '2026/10/28 10:00')

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 終了日時は YYYY-MM-DD HH:MM 形式で入力してください', footer())
    assert.are.equal(0, #insert_calls())

    edit_field(3, '2026-10-28 10:00')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('終了が開始以前のまま <F2> を押すとエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '定例')
    edit_field(3, '2026-10-28 09:00')

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 終了は開始より後にしてください', footer())
    assert.are.equal(0, #insert_calls())

    edit_field(3, '2026-10-28 08:00')
    press_save()

    assert.are.equal('エラー: 終了は開始より後にしてください', footer())
    assert.are.equal(0, #insert_calls())

    edit_field(3, '2026-10-28 10:00')
    press_save()
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it(
    '終日で終了日が開始日以前のまま <F2> を押すとエラーを表示し、gws を呼ばない',
    function()
      form.open_create()
      edit_field(1, '終日予定')
      select_field(4)
      feed('<Space>')
      edit_field(3, '2026-10-28')

      press_save()

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
      assert.are.equal('エラー: 終了日は開始日より後にしてください', footer())
      assert.are.equal(0, #insert_calls())

      edit_field(3, '2026-10-29')
      press_save()
      wait_form_closed()

      assert.are.equal(1, #insert_calls())
    end
  )

  it('終日で開始日が YYYY-MM-DD 形式でない場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_field(1, '終日予定')
    select_field(4)
    feed('<Space>')
    edit_field(2, '2026-10-28 09:00')

    press_save()

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal('エラー: 開始日は YYYY-MM-DD 形式で入力してください', footer())
    assert.are.equal(0, #insert_calls())
  end)

  it('Esc でフォームを閉じ、予定を作成しない', function()
    form.open_create()
    edit_field(1, '破棄する予定')
    local win = state.windows.form

    feed('<Esc>')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_nil(state.windows.form)
    assert.are.equal(0, #insert_calls())
    assert.are.same({}, notifications)
  end)

  it('入力中の Esc でもフォームを閉じ、予定を作成しない', function()
    form.open_create()
    select_field(1)

    feed('<CR><C-u>破棄する予定<Esc>')

    assert.is_nil(state.windows.form)
    assert.are.equal(0, #insert_calls())
    assert.are.same({}, notifications)
  end)

  it(
    'gws が作成に失敗した場合はフォームを閉じず、入力値を保持してエラーを表示する',
    function()
      vim.env.FAKE_GWS_ERROR_FIXTURE = repo_root .. '/tests/fixtures/api-error.json'

      form.open_create()
      edit_field(1, '失敗する予定')
      edit_field(5, '会議室A')

      press_save()
      wait_form_error()

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
      assert.are.equal('エラー: 予定を作成できませんでした: Not Found', footer())
      local lines = form_lines()
      assert.are.equal('タイトル: 失敗する予定', lines[1])
      assert.are.equal('開始:     2026-10-28 09:00', lines[2])
      assert.are.equal('終了:     2026-10-28 10:00', lines[3])
      assert.are.equal('場所:     会議室A', lines[5])
      assert.are.same({
        { message = '予定を作成できませんでした: Not Found', level = vim.log.levels.ERROR },
      }, notifications)

      vim.env.FAKE_GWS_ERROR_FIXTURE = nil
      press_save()
      wait_form_closed()

      assert.are.equal(2, #insert_calls())
    end
  )

  it('Meet を有効にして <F2> を押すと、作成された予定に hangout_link が入る', function()
    form.open_create({
      on_created = function(created)
        captured_created = created
      end,
    })
    edit_field(1, 'Meet 付き')
    select_field(7)
    feed('<Space>')

    press_save()
    wait_form_closed()

    assert.is_not_nil(captured_created)
    assert.is_truthy(captured_created.hangout_link:match('^https://meet%.google%.com/'))

    local calls = insert_calls()
    assert.are.equal(1, #calls)
    local argv = calls[1].argv
    assert.are.same({ 'calendar', '+insert', '--calendar', 'primary' }, { argv[1], argv[2], argv[3], argv[4] })
    assert.are.equal('--summary', argv[5])
    assert.are.equal('Meet 付き', argv[6])
    assert.are.equal('--start', argv[7])
    assert.are.equal('2026-10-28T09:00:00' .. offset_suffix(), argv[8])
    assert.are.equal('--end', argv[9])
    assert.are.equal('2026-10-28T10:00:00' .. offset_suffix(), argv[10])
    assert.are.equal('--meet', argv[11])
    assert.are.equal('--format', argv[12])
    assert.are.equal('json', argv[13])
    assert.are.same({ message = '予定を作成しました', level = vim.log.levels.INFO }, notifications[1])

    local stored = read_json(state_path)
    assert.are.equal(1, #stored.items)
    assert.are.equal(captured_created.hangout_link, stored.items[1].hangoutLink)
  end)

  it('場所と説明を入力すると +insert の --location / --description に渡す', function()
    form.open_create()
    edit_field(1, '定例')
    edit_field(5, '会議室A')
    edit_field(6, '週次の進捗確認')

    press_save()
    wait_form_closed()

    local argv = insert_calls()[1].argv
    assert.are.equal('--location', argv[11])
    assert.are.equal('会議室A', argv[12])
    assert.are.equal('--description', argv[13])
    assert.are.equal('週次の進捗確認', argv[14])
    assert.are.equal('--format', argv[15])
    assert.are.equal('json', argv[16])
  end)

  it('月をまたぐ予定を作成できる', function()
    form.open_create()
    edit_field(1, '月またぎ')
    edit_field(2, '2026-10-31 23:00')
    edit_field(3, '2026-11-01 01:00')

    press_save()
    wait_form_closed()

    local argv = insert_calls()[1].argv
    assert.are.equal('2026-10-31T23:00:00' .. offset_suffix(), argv[8])
    assert.are.equal('2026-11-01T01:00:00' .. offset_suffix(), argv[10])
  end)

  it('終日を有効にして <F2> を押すと events insert で end.date が排他になる', function()
    form.open_create({
      on_created = function(created)
        captured_created = created
      end,
    })
    edit_field(1, '終日予定')
    select_field(4)
    feed('<Space>')

    press_save()
    wait_form_closed()

    assert.is_not_nil(captured_created)
    assert.are.same({ date = '2026-10-28' }, captured_created.start)
    assert.are.same({ date = '2026-10-29' }, captured_created['end'])

    local calls = insert_calls()
    assert.are.equal(1, #calls)
    local argv = calls[1].argv
    assert.are.same({ 'calendar', 'events', 'insert' }, { argv[1], argv[2], argv[3] })
    assert.are.equal('--params', argv[4])
    assert.are.same({ calendarId = 'primary' }, vim.json.decode(argv[5]))
    assert.are.equal('--json', argv[6])
    assert.are.same({
      summary = '終日予定',
      start = { date = '2026-10-28' },
      ['end'] = { date = '2026-10-29' },
    }, vim.json.decode(argv[7]))
    assert.are.same({ '--format', 'json' }, { argv[8], argv[9] })
    assert.are.same({
      items = {
        {
          id = captured_created.id,
          summary = '終日予定',
          start = { date = '2026-10-28' },
          ['end'] = { date = '2026-10-29' },
        },
      },
    }, read_json(state_path))
  end)

  it(
    'Meet の作成に失敗した場合は予定を作成し、Meet URL が付かなかった旨の警告を表示する',
    function()
      local script = tmp_root .. '/no-meet-gws'
      write_script(script, {
        '#!/bin/sh',
        'echo \'{"id":"evt-no-meet","summary":"Meet 失敗",'
          .. '"start":{"dateTime":"2026-10-28T09:00:00+09:00"},'
          .. '"end":{"dateTime":"2026-10-28T10:00:00+09:00"}}\'',
      })
      setup({ gws_cmd = script })

      form.open_create({
        on_created = function(created)
          captured_created = created
        end,
      })
      edit_field(1, 'Meet 失敗')
      select_field(7)
      feed('<Space>')

      press_save()
      wait_form_closed()

      assert.is_not_nil(captured_created)
      assert.is_nil(captured_created.hangout_link)
      assert.are.same({
        { message = '予定を作成しました', level = vim.log.levels.INFO },
        {
          message = '予定は作成されましたが、Meet URL は付きませんでした',
          level = vim.log.levels.WARN,
        },
      }, notifications)
    end
  )

  it('? でフォームのキー一覧のヘルプを開き、閉じるとフォームに戻る', function()
    form.open_create()

    feed('?')

    local help_win = state.windows.help
    assert.is_true(vim.api.nvim_win_is_valid(help_win))
    assert.are.equal(help_win, vim.api.nvim_get_current_win())
    assert.are.same({
      '<Tab>/<S-Tab>:移動',
      '<CR>:編集',
      '<Space>:切替',
      '<F2>:保存',
      '<Esc>:取消',
    }, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(help_win), 0, -1, false))

    feed('q')

    assert.is_false(vim.api.nvim_win_is_valid(help_win))
    assert.is_nil(state.windows.help)
    assert.are.equal(state.windows.form, vim.api.nvim_get_current_win())
  end)

  it('setup() で変更した保存キーを使い、既定の <F2> では保存しない', function()
    setup({ keymaps = { form = { save = '<A-s>' } } })

    form.open_create()
    assert.are.equal('<Tab>/<S-Tab>:移動  <CR>:編集  <Space>:切替  <A-s>:保存  <Esc>:取消', footer())
    edit_field(1, '別キー')

    feed('<F2>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
    assert.are.equal(0, #insert_calls())

    feed('<A-s>')
    wait_form_closed()

    assert.are.equal(1, #insert_calls())
  end)

  it('保存中はフッターに保存中... を表示し、<F2> の連打で gws を 2 回呼ばない', function()
    local script = tmp_root .. '/slow-gws'
    write_script(script, {
      '#!/bin/sh',
      'echo insert >> "$FAKE_GWS_CALL_LOG"',
      'sleep 1',
      'echo \'{"id":"evt-slow","summary":"slow",'
        .. '"start":{"dateTime":"2026-10-28T09:00:00+09:00"},'
        .. '"end":{"dateTime":"2026-10-28T10:00:00+09:00"}}\'',
    })
    setup({ gws_cmd = script })

    form.open_create()
    edit_field(1, '連打')

    press_save()
    assert.are.equal('保存中...', footer())

    press_save()
    wait_form_closed()

    assert.are.equal(1, #read_lines(call_log))
  end)

  it('作成した予定が表示中の月の範囲外の場合は、通知にその旨を含める', function()
    state.year = 2026
    state.month = 10
    form.open_create()
    edit_field(1, '翌月の予定')
    edit_field(2, '2026-11-15 09:00')
    edit_field(3, '2026-11-15 10:00')

    press_save()
    wait_form_closed()

    assert.are.same({
      {
        message = '予定を作成しました（表示中の月には表示されません）',
        level = vim.log.levels.INFO,
      },
    }, notifications)
  end)

  it(
    '月表示で a を押してフォームを開き、<F2> で作成すると月表示を再取得して該当セルに予定を表示する',
    function()
      vim.cmd('runtime! plugin/google-calendar.lua')
      vim.cmd('GoogleCalendar')
      wait_month_loading()

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.month))
      assert.are.equal('2026-10-28', state.selected_date)

      feed('a')

      assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
      assert.are.same(initial_lines('2026-10-28'), form_lines())

      edit_field(1, '定例')
      press_save()
      wait_form_closed()
      wait_month_loading()

      local calls = gws_calls()
      assert.are.equal(3, #calls)
      assert.are.same({ 'calendar', 'events', 'list' }, { calls[1].argv[1], calls[1].argv[2], calls[1].argv[3] })
      assert.are.same({ 'calendar', '+insert' }, { calls[2].argv[1], calls[2].argv[2] })
      assert.are.equal('--summary', calls[2].argv[5])
      assert.are.equal('定例', calls[2].argv[6])
      assert.are.equal('--start', calls[2].argv[7])
      assert.are.equal('2026-10-28T09:00:00' .. offset_suffix(), calls[2].argv[8])
      assert.are.equal('--end', calls[2].argv[9])
      assert.are.equal('2026-10-28T10:00:00' .. offset_suffix(), calls[2].argv[10])
      assert.are.same({ 'calendar', 'events', 'list' }, { calls[3].argv[1], calls[3].argv[2], calls[3].argv[3] })
      assert.are.equal(calls[1].argv[5], calls[3].argv[5])
      assert.are.same({ message = '予定を作成しました', level = vim.log.levels.INFO }, notifications[1])

      local stored = read_json(state_path)
      assert.are.equal(1, #stored.items)
      assert.are.equal('定例', stored.items[1].summary)
      assert.are.equal('2026-10-28T09:00:00' .. offset_suffix(), stored.items[1].start.dateTime)

      local rows = assert(virt_lines(5))
      assert.are.equal(1, #rows)
      assert.are.equal(row('', '', '', ' 09:00 定例', '', '', ''), chunks_text(rows[1]))
      assert.is_nil(virt_lines(1))
    end
  )
end)
