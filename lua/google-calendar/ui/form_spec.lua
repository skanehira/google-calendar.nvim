---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local form = require('google-calendar.ui.form')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local original_columns
local original_lines
local original_gws
local original_today
local original_local_datetime

local notifications = {}
local created
local created_call
local updated_call
local get_call
local create_handler
local update_handler

local fake_gws = {
  create_event = function(fields, callback)
    created_call = fields
    create_handler(fields, callback)
  end,
  update_event = function(fields, callback)
    updated_call = fields
    update_handler(fields, callback)
  end,
  get_event = function(id, callback)
    get_call = id
    callback({
      id = id,
      summary = '更新前',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      calendar_id = 'primary',
    }, nil)
  end,
}

local function notify(message, level)
  table.insert(notifications, { message = message, level = level })
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function feed_save()
  local key = config.resolve('form', 'save') or ':w'
  if key == ':w' then
    feed(':w<CR>')
  else
    feed(key)
  end
end

local function form_lines()
  local win = state.windows.form
  assert.is_true(win ~= nil and vim.api.nvim_win_is_valid(win))
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function editor_lines()
  local win = state.windows.form_editor
  assert.is_true(win ~= nil and vim.api.nvim_win_is_valid(win))
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function select_line(line)
  vim.api.nvim_set_current_win(state.windows.form)
  vim.api.nvim_win_set_cursor(state.windows.form, { line, 0 })
end

local function set_editor(lines)
  local win = state.windows.form_editor
  assert.is_true(win ~= nil and vim.api.nvim_win_is_valid(win))
  vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(win), 0, -1, false, lines)
end

local function open_editor(line)
  select_line(line)
  feed('<CR>')
  assert.is_true(vim.api.nvim_win_is_valid(state.windows.form_editor))
end

local function edit_summary(value)
  open_editor(1)
  set_editor({ value })
  feed_save()
end

local function edit_datetime(start_value, end_value, all_day)
  open_editor(4)
  set_editor({
    '開始: ' .. start_value,
    '終了: ' .. end_value,
    '終日: ' .. (all_day and 'on' or 'off'),
  })
  feed_save()
end

local function edit_location(value)
  open_editor(7)
  set_editor({ value })
  feed_save()
end

local function edit_description(value)
  open_editor(8)
  set_editor(vim.split(value, '\n', { plain = true }))
  feed_save()
end

local function save()
  feed_save()
end

local function wait_closed()
  assert.is_true(vim.wait(10000, function()
    return state.windows.form == nil
  end, 10))
end

local function wait_error()
  assert.is_true(vim.wait(1000, function()
    local lines = form_lines()
    return lines[11] ~= nil and lines[11]:match('^エラー:') ~= nil
  end, 10))
end

local function default_create_handler(fields, callback)
  local start_value = fields.start.date or fields.start.dateTime
  local end_value = fields['end'].date or fields['end'].dateTime
  callback({
    id = 'created-1',
    summary = fields.summary,
    start = fields.start,
    ['end'] = fields['end'],
    hangout_link = fields.meet and 'https://meet.google.com/abc-defg-hij' or nil,
    calendar_id = 'primary',
    start_value = start_value,
    end_value = end_value,
  }, nil)
end

local function default_update_handler(fields, callback)
  callback({
    id = fields.id,
    summary = fields.summary,
    start = fields.start,
    ['end'] = fields['end'],
    calendar_id = fields.calendar_id,
  }, nil)
end

describe('ui.form', function()
  before_each(function()
    state.reset()
    config.setup({
      notify = notify,
      calendars = { 'primary' },
    })

    notifications = {}
    created = nil
    created_call = nil
    updated_call = nil
    get_call = nil
    create_handler = default_create_handler
    update_handler = default_update_handler

    original_gws = package.loaded['google-calendar.gws']
    package.loaded['google-calendar.gws'] = fake_gws

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 120
    vim.o.lines = 40

    original_today = rawget(calendar, 'today')
    rawset(calendar, 'today', function()
      return '2026-10-28'
    end)

    original_local_datetime = rawget(event, 'local_datetime')
    rawset(event, 'local_datetime', function(value)
      return value:sub(1, 10), value:sub(12, 16)
    end)

    state.selected_date = '2026-10-28'
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
    state.reset()
    package.loaded['google-calendar.gws'] = original_gws
    rawset(calendar, 'today', original_today)
    rawset(event, 'local_datetime', original_local_datetime)
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it('Google カレンダー風の登録フォームを開く', function()
    local win = form.open_create({
      on_created = function(item)
        created = item
      end,
    })

    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal('form', state.stack[#state.stack].name)
    local lines = form_lines()
    assert.are.equal('タイトルと日時を追加', lines[1])
    assert.are.equal('◷ 10月28日 (水曜日)・09:00〜10:00  [終日]', lines[4])
    assert.are.equal('◉ ゲストを追加', lines[5])
    assert.are.equal('▶ Google Meet のビデオ会議を追加  [off]', lines[6])
    assert.are.equal('⌖ 場所を追加', lines[7])
    assert.is_true(lines[8]:match('^☰ *説明または Google ドライブの添付ファイルを追加$') ~= nil)
    assert.are.equal('▣ primary', lines[9])
    assert.are.equal('', lines[10])
    assert.is_true(lines[11]:match('^その他のオプション') ~= nil)
    assert.are.equal(1, vim.api.nvim_win_get_cursor(win)[1])
  end)

  local function text_start_column(line)
    local icon = vim.fn.strcharpart(line, 0, 1)
    local rest = line:sub(#icon + 1)
    local spaces = rest:match('^ *') or ''
    return vim.fn.strdisplaywidth(icon) + #spaces
  end

  it('アイコンと説明文の列を揃える', function()
    form.open_create()
    local lines = form_lines()
    for _, line_number in ipairs({ 4, 5, 6, 7, 8, 9 }) do
      assert.are.equal(2, text_start_column(lines[line_number]))
    end
  end)

  it('<Tab> / <S-Tab> で行を移動する', function()
    form.open_create()

    feed('<Tab>')
    assert.are.equal(4, vim.api.nvim_win_get_cursor(state.windows.form)[1])
    feed('<Tab>')
    assert.are.equal(5, vim.api.nvim_win_get_cursor(state.windows.form)[1])
    feed('<S-Tab>')
    assert.are.equal(4, vim.api.nvim_win_get_cursor(state.windows.form)[1])
    feed('<S-Tab>')
    assert.are.equal(1, vim.api.nvim_win_get_cursor(state.windows.form)[1])
  end)

  it('タイトル行から別ウィンドウでタイトルを編集する', function()
    form.open_create()
    edit_summary('テスト予定')

    assert.is_nil(state.windows.form_editor)
    assert.are.equal('テスト予定', form_lines()[1])
    assert.are.equal(1, vim.api.nvim_win_get_cursor(state.windows.form)[1])
  end)

  it('日時行から別ウィンドウで開始・終了・終日を編集する', function()
    form.open_create()
    edit_datetime('2026-10-28 10:00', '2026-10-28 11:00', false)

    assert.are.equal('◷ 10月28日 (水曜日)・10:00〜11:00  [終日]', form_lines()[4])
    assert.is_nil(state.windows.form_editor)

    select_line(4)
    feed('<Space>')
    assert.are.equal('◷ 10月28日 (水曜日) – 10月28日 (水曜日)  [時間を追加]', form_lines()[4])

    open_editor(4)
    assert.are.same({
      '開始: 2026-10-28',
      '終了: 2026-10-29',
      '終日: on',
    }, editor_lines())
  end)

  it('場所と説明を別ウィンドウで編集する', function()
    form.open_create()
    edit_location('会議室A')
    edit_description('議題1\n議題2')

    assert.are.equal('⌖ 会議室A', form_lines()[7])
    assert.is_true(form_lines()[8]:match('^☰ *議題1$') ~= nil)
  end)

  it('説明エディタはメインのコンポーザーと同じサイズで開く', function()
    form.open_create()
    local main_config = vim.api.nvim_win_get_config(state.windows.form)

    open_editor(8)
    local editor_config = vim.api.nvim_win_get_config(state.windows.form_editor)

    assert.are.equal(main_config.width, editor_config.width)
    assert.are.equal(main_config.height, editor_config.height)
  end)

  it('Meet 行を <Space> で切り替える', function()
    form.open_create()
    select_line(6)
    feed('<Space>')
    assert.are.equal('▶ Google Meet のビデオ会議を追加  [on]', form_lines()[6])
    feed('<Space>')
    assert.are.equal('▶ Google Meet のビデオ会議を追加  [off]', form_lines()[6])
  end)

  it('ゲスト行から別ウィンドウでゲストを追加する', function()
    form.open_create()
    select_line(5)
    feed('<CR>')
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form_editor))
    assert.are.same({ '' }, editor_lines())

    set_editor({ 'alice@example.com', 'bob@example.com' })
    feed_save()

    assert.are.equal('◉ 2人のゲスト', form_lines()[5])
    assert.is_nil(state.windows.form_editor)
  end)

  it('入力して :w で予定を作成する', function()
    form.open_create({
      on_created = function(item)
        created = item
      end,
    })
    edit_summary('テスト予定')
    edit_location('会議室A')
    edit_description('説明')
    select_line(5)
    feed('<CR>')
    set_editor({ 'alice@example.com', 'bob@example.com' })
    feed_save()
    select_line(6)
    feed('<Space>')
    save()

    wait_closed()
    assert.is_not_nil(created_call)
    assert.are.equal('テスト予定', created_call.summary)
    assert.are.equal('会議室A', created_call.location)
    assert.are.equal('説明', created_call.description)
    assert.is_true(created_call.meet)
    assert.are.same({ 'alice@example.com', 'bob@example.com' }, created_call.attendees)
    assert.are.equal('created-1', created.id)
    assert.are.same({ { message = '予定を作成しました', level = vim.log.levels.INFO } }, notifications)
  end)

  it('タイトルが空の場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    save()

    wait_error()
    assert.is_nil(created_call)
    assert.is_true(form_lines()[11]:match('タイトルを入力してください') ~= nil)
  end)

  it('開始日時の形式が不正な場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_summary('テスト')
    edit_datetime('invalid', '2026-10-28 10:00', false)
    save()

    wait_error()
    assert.is_nil(created_call)
    assert.is_true(form_lines()[11]:match('開始日時は YYYY%-MM%-DD HH:MM 形式') ~= nil)
  end)

  it('<Esc> でフォームを閉じ、予定を作成しない', function()
    form.open_create()
    feed('<Esc>')

    assert.is_nil(state.windows.form)
    assert.is_nil(created_call)
  end)

  it('エディタの <Esc> はエディタだけを閉じ、フォームは残る', function()
    form.open_create()
    open_editor(1)
    feed('<Esc>')

    assert.is_nil(state.windows.form_editor)
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
  end)

  it('更新フォームに現在の値を表示する', function()
    local item = {
      id = 'evt-1',
      summary = '定例',
      location = '会議室A',
      description = '議題',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      calendar_id = 'primary',
    }

    form.open_edit(item)
    local lines = form_lines()
    assert.are.equal('定例', lines[1])
    assert.are.equal('◷ 10月28日 (水曜日)・09:00〜10:00  [終日]', lines[4])
    assert.are.equal('⌖ 会議室A', lines[7])
    assert.is_true(lines[8]:match('^☰ *議題$') ~= nil)
    assert.are.equal('▶ Google Meet のビデオ会議を追加  [固定]', lines[6])
  end)

  it('更新フォームで値を変えずに :w を押すと、gws を呼ばず閉じる', function()
    local item = {
      id = 'evt-1',
      summary = '定例',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      calendar_id = 'primary',
    }

    form.open_edit(item)
    save()

    wait_closed()
    assert.is_nil(get_call)
    assert.is_nil(updated_call)
  end)

  it('更新フォームでタイトルを変えると get / update を呼ぶ', function()
    local item = {
      id = 'evt-1',
      summary = '定例',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      calendar_id = 'primary',
    }

    form.open_edit(item)
    edit_summary('更新後')
    save()

    wait_closed()
    assert.are.equal('evt-1', get_call)
    assert.are.equal('更新後', updated_call.summary)
    assert.are.same({ { message = '予定を更新しました', level = vim.log.levels.INFO } }, notifications)
  end)

  it('更新フォームでゲストを追加すると attendees を更新する', function()
    local item = {
      id = 'evt-1',
      summary = '定例',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      attendees = {
        { email = 'alice@example.com', responseStatus = 'accepted' },
      },
      calendar_id = 'primary',
    }

    form.open_edit(item)
    assert.are.equal('◉ 1人のゲスト', form_lines()[5])

    select_line(5)
    feed('<CR>')
    assert.are.same({ 'alice@example.com' }, editor_lines())
    set_editor({ 'alice@example.com', 'bob@example.com' })
    feed_save()
    save()

    wait_closed()
    assert.is_not_nil(updated_call)
    assert.are.same({
      { email = 'alice@example.com', responseStatus = 'accepted' },
      { email = 'bob@example.com' },
    }, updated_call.attendees)
  end)

  it('保存中は連打しても gws を 1 回だけ呼ぶ', function()
    local callback
    create_handler = function(fields, cb)
      created_call = fields
      callback = cb
    end

    form.open_create()
    edit_summary('テスト')
    save()
    save()

    assert.are.equal(0, #notifications)
    assert.is_true(form_lines()[11]:match('^保存中%.%.%.') ~= nil)
    callback(
      { id = 'created-1', summary = 'テスト', start = { date = '2026-10-28' }, ['end'] = { date = '2026-10-29' } },
      nil
    )
    wait_closed()
  end)

  it('終日で作成すると start.date / end.date を送る', function()
    form.open_create()
    edit_summary('終日予定')
    select_line(4)
    feed('<Space>')
    save()

    wait_closed()
    assert.is_not_nil(created_call)
    assert.are.equal('2026-10-28', created_call.start)
    assert.are.equal('2026-10-29', created_call['end'])
    assert.is_true(created_call.all_day)
  end)

  it('終了が開始以前の場合はエラーを表示し、gws を呼ばない', function()
    form.open_create()
    edit_summary('テスト')
    edit_datetime('2026-10-28 10:00', '2026-10-28 09:00', false)
    save()

    wait_error()
    assert.is_nil(created_call)
    assert.is_true(form_lines()[11]:match('終了は開始より後にしてください') ~= nil)
  end)

  it('場所が 1024 文字を超える場合はエラーを表示する', function()
    form.open_create()
    edit_summary('テスト')
    edit_location(string.rep('あ', 1025))
    save()

    wait_error()
    assert.is_nil(created_call)
    assert.is_true(form_lines()[11]:match('場所は 1024 文字以内') ~= nil)
  end)

  it('説明が 8192 文字を超える場合はエラーを表示する', function()
    form.open_create()
    edit_summary('テスト')
    edit_description(string.rep('あ', 8193))
    save()

    wait_error()
    assert.is_nil(created_call)
    assert.is_true(form_lines()[11]:match('説明は 8192 文字以内') ~= nil)
  end)

  it('? でフォームのヘルプを開き、閉じるとフォームに戻る', function()
    form.open_create()
    feed('?')

    assert.is_true(vim.api.nvim_win_is_valid(state.windows.help))
    feed('q')
    assert.is_nil(state.windows.help)
    assert.is_true(vim.api.nvim_win_is_valid(state.windows.form))
  end)

  it('setup() で変更した保存キーを使う', function()
    config.setup({
      notify = notify,
      keymaps = { form = { save = '<F5>' } },
    })
    form.open_create()
    edit_summary('テスト')
    feed('<F5>')

    wait_closed()
    assert.is_not_nil(created_call)
  end)
end)
