---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local gws = require('google-calendar.gws')

local repo_root = vim.fn.getcwd()
local fake_gws = repo_root .. '/tests/fixtures/fake-gws.py'
local cache_dir = vim.fn.stdpath('cache') .. '/google-calendar.nvim'

local env_keys = {
  'FAKE_GWS_STATE',
  'FAKE_GWS_CWD_LOG',
  'FAKE_GWS_CALL_LOG',
  'FAKE_GWS_PAGE_SIZE',
  'FAKE_GWS_ERROR_FIXTURE',
  'FAKE_GWS_RESPONSE_FILE',
}

local tmp_root
local state_path
local cwd_log
local call_log
local messages
local saved_env
local saved_tz

local timed_event = {
  id = 'evt-timed-1',
  summary = '定例',
  start = { dateTime = '2026-10-27T09:00:00+09:00' },
  ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
}

local all_day_event = {
  id = 'evt-all-day-1',
  summary = '終日',
  start = { date = '2026-10-28' },
  ['end'] = { date = '2026-10-29' },
}

local meet_event = {
  id = 'evt-meet-1',
  summary = 'Meet 付き',
  start = { dateTime = '2026-10-29T13:00:00+09:00' },
  ['end'] = { dateTime = '2026-10-29T14:00:00+09:00' },
  hangoutLink = 'https://meet.google.com/abc-defg-hij',
}

local function new_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function write_text(path, text)
  local file = assert(io.open(path, 'w'))
  file:write(text)
  file:close()
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  write_text(path, vim.json.encode(value))
end

local function read_json(path)
  local file = assert(io.open(path, 'r'))
  local content = file:read('*a')
  file:close()
  return vim.json.decode(content)
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

local function write_script(path, lines)
  vim.fn.writefile(lines, path)
  vim.fn.setfperm(path, 'rwxr-xr-x')
end

local function capture(message, level)
  table.insert(messages, { msg = message, level = level })
end

local function setup_config(opts)
  opts = opts or {}
  opts.gws_cmd = opts.gws_cmd or fake_gws
  opts.notify = opts.notify or capture
  config.setup(opts)
end

local function await(call)
  local done = false
  local value, err
  call(function(result, error_value)
    value = result
    err = error_value
    done = true
  end)
  assert.is_true(vim.wait(10000, function()
    return done
  end, 10))
  return value, err
end

local function normalized(raw, calendar_id)
  local model = vim.deepcopy(raw)
  model.hangoutLink = nil
  if raw.hangoutLink ~= nil then
    model.hangout_link = raw.hangoutLink
  end
  model.calendar_id = calendar_id or 'primary'
  return model
end

local function list_params(page_token)
  local params = {
    calendarId = 'primary',
    singleEvents = true,
    maxResults = 2500,
    timeMin = '2026-10-01T00:00:00+09:00',
    timeMax = '2026-11-01T00:00:00+09:00',
  }
  if page_token ~= nil then
    params.pageToken = page_token
  end
  return params
end

describe('gws adapter', function()
  before_each(function()
    tmp_root = new_tmp_dir()
    state_path = tmp_root .. '/state.json'
    cwd_log = tmp_root .. '/cwd.log'
    call_log = tmp_root .. '/call.log'
    messages = {}
    saved_env = {}
    for _, key in ipairs(env_keys) do
      saved_env[key] = vim.env[key]
      vim.env[key] = nil
    end
    saved_tz = vim.env.TZ
    vim.env.TZ = 'Asia/Tokyo'
    vim.env.FAKE_GWS_STATE = state_path
    vim.env.FAKE_GWS_CALL_LOG = call_log
    setup_config()
    vim.fn.delete(cache_dir .. '/download.html')
    vim.fn.delete(repo_root .. '/download.html')
  end)

  after_each(function()
    for _, key in ipairs(env_keys) do
      vim.env[key] = saved_env[key]
    end
    vim.env.TZ = saved_tz
    config.setup({})
    vim.fn.delete(cache_dir .. '/download.html')
    vim.fn.delete(tmp_root, 'rf')
  end)

  it(
    'gws calendar events list の JSON から予定モデルを組み立て、nextPageToken がある限りページを取得して items を結合する',
    function()
      write_json(state_path, { items = { timed_event, all_day_event, meet_event } })
      vim.env.FAKE_GWS_PAGE_SIZE = '2'

      local events, err = await(function(callback)
        gws.list_events({
          calendar_id = 'primary',
          time_min = '2026-10-01T00:00:00+09:00',
          time_max = '2026-11-01T00:00:00+09:00',
        }, callback)
      end)

      assert.is_nil(err)
      assert.are.same({
        normalized(timed_event),
        normalized(all_day_event),
        normalized(meet_event),
      }, events)

      local calls = read_lines(call_log)
      assert.are.equal(2, #calls)
      local first = vim.json.decode(calls[1])
      local second = vim.json.decode(calls[2])
      assert.are.same({ 'calendar', 'events', 'list' }, { first.argv[1], first.argv[2], first.argv[3] })
      assert.are.equal('--params', first.argv[4])
      assert.are.same(list_params(), vim.json.decode(first.argv[5]))
      assert.are.same({ '--format', 'json' }, { first.argv[6], first.argv[7] })
      assert.are.equal(vim.fn.resolve(cache_dir), vim.fn.resolve(first.cwd))
      assert.are.same({ 'calendar', 'events', 'list' }, { second.argv[1], second.argv[2], second.argv[3] })
      assert.are.equal('--params', second.argv[4])
      assert.are.same(list_params('2'), vim.json.decode(second.argv[5]))
      assert.are.same({ '--format', 'json' }, { second.argv[6], second.argv[7] })
      assert.are.equal(vim.fn.resolve(cache_dir), vim.fn.resolve(second.cwd))
    end
  )

  it(
    '偽 gws のページネーション fixture で、2 ページ分の予定が結合されることを検証する',
    function()
      write_json(state_path, { items = { timed_event, all_day_event } })
      vim.env.FAKE_GWS_PAGE_SIZE = '1'

      local events, err = await(function(callback)
        gws.list_events({
          calendar_id = 'primary',
          time_min = '2026-10-01T00:00:00+09:00',
          time_max = '2026-11-01T00:00:00+09:00',
        }, callback)
      end)

      assert.is_nil(err)
      assert.are.same({ normalized(timed_event), normalized(all_day_event) }, events)
      assert.are.equal(2, #read_lines(call_log))
    end
  )

  it('nextPageToken が null（vim.NIL）のときにページ取得を終了する', function()
    local response_path = tmp_root .. '/nil-token.json'
    write_text(
      response_path,
      '{"items":[{"id":"evt-nil","summary":"1 件",'
        .. '"start":{"date":"2026-10-28"},"end":{"date":"2026-10-29"}}],'
        .. '"nextPageToken":null}'
    )
    local script_path = tmp_root .. '/nil-token-gws'
    write_script(script_path, {
      '#!/bin/sh',
      'echo call >> "$FAKE_GWS_CALL_LOG"',
      'cat "$FAKE_GWS_RESPONSE_FILE"',
    })
    vim.env.FAKE_GWS_RESPONSE_FILE = response_path
    setup_config({ gws_cmd = script_path })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(err)
    assert.are.same({
      {
        id = 'evt-nil',
        summary = '1 件',
        start = { date = '2026-10-28' },
        ['end'] = { date = '2026-10-29' },
        calendar_id = 'primary',
      },
    }, events)
    assert.are.equal(1, #read_lines(call_log))
  end)

  it('10 ページを超える取得は打ち切り、警告を出す', function()
    local items = {}
    for index = 1, 11 do
      table.insert(items, {
        id = 'evt-' .. index,
        summary = '予定 ' .. index,
        start = { date = '2026-10-01' },
        ['end'] = { date = '2026-10-02' },
      })
    end
    write_json(state_path, { items = items })
    vim.env.FAKE_GWS_PAGE_SIZE = '1'

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(err)
    assert.are.equal(10, #events)
    for index, item in ipairs(events) do
      assert.are.equal('予定 ' .. index, item.summary)
    end
    assert.are.same({
      {
        msg = 'google-calendar.nvim: Stopped fetching events after more than 10 pages.',
        level = vim.log.levels.WARN,
      },
    }, messages)
    assert.are.equal(10, #read_lines(call_log))
  end)

  it('終了コード 2 かつ error.reason == authError の応答を認証エラーとして分類する', function()
    vim.env.FAKE_GWS_ERROR_FIXTURE = repo_root .. '/tests/fixtures/auth-error.json'

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({
      kind = 'auth',
      message = 'Request had invalid authentication credentials.',
    }, err)
  end)

  it('終了コード非 0 で error を持つ応答を API エラーとして分類する', function()
    vim.env.FAKE_GWS_ERROR_FIXTURE = repo_root .. '/tests/fixtures/api-error.json'

    local event_model, err = await(function(callback)
      gws.get_event('evt-404', callback)
    end)

    assert.is_nil(event_model)
    assert.are.same({
      kind = 'api',
      code = 404,
      message = 'Not Found',
      reason = 'notFound',
    }, err)
  end)

  it('gws が見つからないときに未インストールとして分類する', function()
    local missing = tmp_root .. '/missing-gws'
    setup_config({ gws_cmd = missing })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({ kind = 'not_found', command = missing }, err)
  end)

  it('実行ファイルの起動に失敗したときも未インストールとして分類する', function()
    local broken = tmp_root .. '/broken-gws'
    -- Linux では execvp が ENOEXEC のテキストファイルを /bin/sh で実行してしまうため、
    -- 存在しないインタプリタを指す shebang にして起動自体を失敗させる。
    write_text(broken, '#!/nonexistent/interpreter\n')
    vim.fn.setfperm(broken, 'rwxr-xr-x')
    setup_config({ gws_cmd = broken })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({ kind = 'not_found', command = broken }, err)
  end)

  it('終了コード 0 だが stdout が JSON でない応答を invalid_output として分類する', function()
    local script_path = tmp_root .. '/invalid-output-gws'
    write_script(script_path, { '#!/bin/sh', 'echo not-json' })
    setup_config({ gws_cmd = script_path })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({ kind = 'invalid_output', output = 'not-json\n', stderr = '' }, err)
  end)

  it('タイムアウトした実行をネットワークエラーとして分類する', function()
    local body, err = gws.classify({ code = 124, signal = 15, stdout = '', stderr = '' })

    assert.is_nil(body)
    assert.are.same({ kind = 'network', message = 'timeout' }, err)
  end)

  it(
    'gws calendar events delete をキャッシュディレクトリで実行し、偽 gws の cwd ログがキャッシュディレクトリであることを assert する',
    function()
      write_json(state_path, { items = { timed_event } })
      vim.env.FAKE_GWS_CWD_LOG = cwd_log

      local ok, err = await(function(callback)
        gws.delete_event('evt-timed-1', callback)
      end)

      assert.is_nil(err)
      assert.is_true(ok)
      local lines = read_lines(cwd_log)
      assert.are.equal(1, #lines)
      assert.are.equal(vim.fn.resolve(cache_dir), vim.fn.resolve(lines[1]))
      assert.are.equal(0, vim.fn.getfsize(cache_dir .. '/download.html'))
      assert.are.equal(0, vim.fn.filereadable(repo_root .. '/download.html'))
      assert.are.same({ items = {} }, read_json(state_path))

      local call = vim.json.decode(read_lines(call_log)[1])
      assert.are.same({ 'calendar', 'events', 'delete' }, { call.argv[1], call.argv[2], call.argv[3] })
      assert.are.same({
        calendarId = 'primary',
        eventId = 'evt-timed-1',
      }, vim.json.decode(call.argv[5]))
    end
  )

  it('dateTime をローカル時刻へ変換し、終日予定は date のまま扱う', function()
    local timed = event.normalize({
      id = 'evt-timed',
      summary = '定例',
      start = { dateTime = '2026-10-01T08:00:00Z', timeZone = 'Asia/Tokyo' },
      ['end'] = { dateTime = '2026-10-01T09:00:00Z', timeZone = 'Asia/Tokyo' },
    }, { calendar_id = 'primary' })

    assert.are.same({
      id = 'evt-timed',
      summary = '定例',
      start = { dateTime = '2026-10-01T17:00:00+09:00', timeZone = 'Asia/Tokyo' },
      ['end'] = { dateTime = '2026-10-01T18:00:00+09:00', timeZone = 'Asia/Tokyo' },
      calendar_id = 'primary',
    }, timed)

    local all_day = event.normalize({
      id = 'evt-all-day',
      summary = '終日',
      start = { date = '2026-10-27' },
      ['end'] = { date = '2026-10-28' },
    }, { calendar_id = 'primary' })

    assert.are.same({
      id = 'evt-all-day',
      summary = '終日',
      start = { date = '2026-10-27' },
      ['end'] = { date = '2026-10-28' },
      calendar_id = 'primary',
    }, all_day)
  end)

  it('calendar +insert --meet の応答から hangoutLink を取り出す', function()
    local created, err = await(function(callback)
      gws.create_event({
        summary = 'Meet 付き',
        start = '2026-10-27T09:00:00+09:00',
        ['end'] = '2026-10-27T10:00:00+09:00',
        meet = true,
      }, callback)
    end)

    assert.is_nil(err)
    assert.is_truthy(created.id:match('^evt%-%x+$'))
    assert.is_truthy(created.hangout_link:match('^https://meet%.google%.com/[a-z%-]+$'))

    local expected = vim.deepcopy(created)
    expected.id = '<id>'
    expected.hangout_link = '<meet>'
    assert.are.same({
      id = '<id>',
      summary = 'Meet 付き',
      start = { dateTime = '2026-10-27T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
      hangout_link = '<meet>',
      calendar_id = 'primary',
    }, expected)

    local state = read_json(state_path)
    assert.are.equal(1, #state.items)
    assert.are.equal(created.id, state.items[1].id)
    assert.are.equal(created.hangout_link, state.items[1].hangoutLink)
  end)

  it('hangoutLink が無い場合は conferenceData の video entryPoint から URL を取り出す', function()
    local raw = {
      conferenceData = {
        entryPoints = {
          { entryPointType = 'phone', uri = 'tel:+1-555-0100' },
          { entryPointType = 'video', uri = 'https://meet.google.com/fallback-url' },
        },
      },
    }

    assert.are.equal('https://meet.google.com/fallback-url', event.extract_hangout_link(raw))
    assert.are.equal(
      'https://meet.google.com/primary-url',
      event.extract_hangout_link({
        hangoutLink = 'https://meet.google.com/primary-url',
        conferenceData = raw.conferenceData,
      })
    )
  end)

  it('create_event が時刻付き予定を location / description 付きで +insert する', function()
    local created, err = await(function(callback)
      gws.create_event({
        summary = '定例',
        start = '2026-10-27T09:00:00+09:00',
        ['end'] = '2026-10-27T10:00:00+09:00',
        location = '会議室A',
        description = '週次の進捗確認',
      }, callback)
    end)

    assert.is_nil(err)
    assert.is_truthy(created.id)

    local calls = read_lines(call_log)
    assert.are.equal(1, #calls)
    local call = vim.json.decode(calls[1])
    assert.are.same({
      'calendar',
      '+insert',
      '--calendar',
      'primary',
      '--summary',
      '定例',
      '--start',
      '2026-10-27T09:00:00+09:00',
      '--end',
      '2026-10-27T10:00:00+09:00',
      '--location',
      '会議室A',
      '--description',
      '週次の進捗確認',
      '--format',
      'json',
    }, call.argv)
    assert.are.equal(vim.fn.resolve(cache_dir), vim.fn.resolve(call.cwd))
  end)

  it('create_event が終日予定を events insert で作成する', function()
    local created, err = await(function(callback)
      gws.create_event({
        summary = '終日',
        start = '2026-10-27',
        ['end'] = '2026-10-28',
        all_day = true,
      }, callback)
    end)

    assert.is_nil(err)
    assert.is_truthy(created.id:match('^evt%-%x+$'))
    assert.is_nil(created.hangout_link)
    local expected = vim.deepcopy(created)
    expected.id = '<id>'
    assert.are.same({
      id = '<id>',
      summary = '終日',
      start = { date = '2026-10-27' },
      ['end'] = { date = '2026-10-28' },
      calendar_id = 'primary',
    }, expected)
    assert.are.equal(1, #read_json(state_path).items)

    local call = vim.json.decode(read_lines(call_log)[1])
    assert.are.same({ 'calendar', 'events', 'insert' }, { call.argv[1], call.argv[2], call.argv[3] })
    assert.are.equal('--params', call.argv[4])
    assert.are.same({ calendarId = 'primary' }, vim.json.decode(call.argv[5]))
    assert.are.equal('--json', call.argv[6])
    assert.are.same({
      summary = '終日',
      start = { date = '2026-10-27' },
      ['end'] = { date = '2026-10-28' },
    }, vim.json.decode(call.argv[7]))
    assert.are.same({ '--format', 'json' }, { call.argv[8], call.argv[9] })
  end)

  it('update_event が編集可能フィールドを保持して events update を実行する', function()
    local raw = {
      id = 'evt-update-1',
      summary = '更新前',
      start = { dateTime = '2026-10-27T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
      conferenceData = {
        entryPoints = {
          { entryPointType = 'video', uri = 'https://meet.google.com/keep-me' },
        },
      },
      attendees = { { email = 'member@example.com' } },
      reminders = { useDefault = true },
      colorId = '5',
      visibility = 'default',
      transparency = 'opaque',
    }
    write_json(state_path, { items = { raw } })

    local fields = {
      id = 'evt-update-1',
      summary = '更新後',
      location = '会議室B',
      description = '',
      start = { dateTime = '2026-10-27T11:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T12:00:00+09:00' },
      conferenceData = raw.conferenceData,
      attendees = raw.attendees,
      reminders = raw.reminders,
      colorId = '5',
      visibility = 'default',
      transparency = 'opaque',
    }

    local updated, err = await(function(callback)
      gws.update_event(fields, callback)
    end)

    assert.is_nil(err)
    assert.are.same({
      id = 'evt-update-1',
      summary = '更新後',
      location = '会議室B',
      description = '',
      start = { dateTime = '2026-10-27T11:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T12:00:00+09:00' },
      hangout_link = 'https://meet.google.com/keep-me',
      calendar_id = 'primary',
      conferenceData = raw.conferenceData,
      attendees = raw.attendees,
      reminders = raw.reminders,
      colorId = '5',
      visibility = 'default',
      transparency = 'opaque',
    }, updated)

    local calls = read_lines(call_log)
    assert.are.equal(1, #calls)
    local call = vim.json.decode(calls[1])
    assert.are.same({ 'calendar', 'events', 'update' }, { call.argv[1], call.argv[2], call.argv[3] })
    assert.are.equal('--params', call.argv[4])
    assert.are.same({
      calendarId = 'primary',
      eventId = 'evt-update-1',
      conferenceDataVersion = 1,
    }, vim.json.decode(call.argv[5]))
    assert.are.equal('--json', call.argv[6])
    assert.are.same({
      summary = '更新後',
      location = '会議室B',
      description = '',
      start = { dateTime = '2026-10-27T11:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T12:00:00+09:00' },
      conferenceData = raw.conferenceData,
      attendees = raw.attendees,
      reminders = raw.reminders,
      colorId = '5',
      visibility = 'default',
      transparency = 'opaque',
    }, vim.json.decode(call.argv[7]))
    assert.are.same({ '--format', 'json' }, { call.argv[8], call.argv[9] })
  end)
  it('execute が vim.system に timeout=30000 を渡す', function()
    local original_system = vim.system
    local captured
    rawset(vim, 'system', function(_, opts)
      captured = opts
      return {}
    end)
    gws.get_event('evt-timeout', function() end)
    rawset(vim, 'system', original_system)

    assert.are.equal(30000, captured.timeout)
  end)

  it('get_event が予定を取得し、calendarId / eventId の argv を渡す', function()
    write_json(state_path, { items = { timed_event } })

    local item, err = await(function(callback)
      gws.get_event('evt-timed-1', callback)
    end)

    assert.is_nil(err)
    assert.are.same(normalized(timed_event), item)

    local call = vim.json.decode(read_lines(call_log)[1])
    assert.are.same({ 'calendar', 'events', 'get' }, { call.argv[1], call.argv[2], call.argv[3] })
    assert.are.equal('--params', call.argv[4])
    assert.are.same({
      calendarId = 'primary',
      eventId = 'evt-timed-1',
    }, vim.json.decode(call.argv[5]))
    assert.are.same({ '--format', 'json' }, { call.argv[6], call.argv[7] })
  end)

  it('list で時間範囲を指定しないとき params に timeMin/timeMax を含めない', function()
    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(err)
    assert.are.same({}, events)

    local call = vim.json.decode(read_lines(call_log)[1])
    assert.are.same({
      calendarId = 'primary',
      singleEvents = true,
      maxResults = 2500,
    }, vim.json.decode(call.argv[5]))
  end)

  it('items が無い応答を 0 件として扱う', function()
    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(err)
    assert.are.same({}, events)
  end)

  it('終了コード非 0 かつ error を持たない応答を invalid_output として分類する', function()
    local script_path = tmp_root .. '/no-error-gws'
    write_script(script_path, { '#!/bin/sh', 'echo boom', 'exit 1' })
    setup_config({ gws_cmd = script_path })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({ kind = 'invalid_output', output = 'boom\n', stderr = '' }, err)
  end)

  it('+09:00 の dateTime をローカル時刻としてそのまま扱う', function()
    local item = event.normalize({
      id = 'evt-plus9',
      summary = '定例',
      start = { dateTime = '2026-10-01T17:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-01T18:00:00+09:00' },
    }, { calendar_id = 'primary' })

    assert.are.equal('2026-10-01T17:00:00+09:00', item.start.dateTime)
    assert.are.equal('2026-10-01T18:00:00+09:00', item['end'].dateTime)
  end)

  it('update_event が conferenceData を含めず、指定したフィールドだけを送る', function()
    local raw = {
      id = 'evt-update-2',
      summary = '更新前',
      start = { dateTime = '2026-10-27T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
    }
    write_json(state_path, { items = { raw } })

    local updated, err = await(function(callback)
      gws.update_event({
        id = 'evt-update-2',
        summary = '更新後',
        start = raw.start,
        ['end'] = raw['end'],
      }, callback)
    end)

    assert.is_nil(err)
    assert.are.equal('更新後', updated.summary)

    local call = vim.json.decode(read_lines(call_log)[1])
    assert.are.same({
      calendarId = 'primary',
      eventId = 'evt-update-2',
    }, vim.json.decode(call.argv[5]))
    local body = vim.json.decode(call.argv[7])
    assert.are.equal('更新後', body.summary)
    assert.is_nil(body.conferenceData)
    assert.is_nil(body.attendees)
    assert.is_nil(body.reminders)
    assert.is_nil(body.colorId)
    assert.is_nil(body.visibility)
    assert.is_nil(body.transparency)
  end)

  it('normalize が不正な raw_time を nil として扱う', function()
    local item = event.normalize({
      id = 'evt-bad-time',
      summary = '不正',
      start = { foo = 'bar' },
      ['end'] = { date = '2026-10-29' },
    }, { calendar_id = 'primary' })

    assert.is_nil(item.start)
    assert.are.same({ date = '2026-10-29' }, item['end'])
  end)

  it('終了コード 2 で authError 以外の非 table 応答を invalid_output として分類する', function()
    local body, err = gws.classify({ code = 2, stdout = 'plain', stderr = 'err' })

    assert.is_nil(body)
    assert.are.same({ kind = 'invalid_output', output = 'plain', stderr = 'err' }, err)
  end)

  it('list の 2 ページ目でエラーになったとき、そのエラーを返す', function()
    local count_file = tmp_root .. '/page-count'
    local script_path = tmp_root .. '/two-page-gws'
    write_script(script_path, {
      '#!/bin/sh',
      'count=$(cat "$FAKE_GWS_COUNT_FILE" 2>/dev/null || echo 0)',
      'count=$((count + 1))',
      'echo "$count" > "$FAKE_GWS_COUNT_FILE"',
      'if [ "$count" -eq 1 ]; then',
      'echo \'{"items":[{"id":"e1","summary":"a","start":{"date":"2026-10-01"},'
        .. '"end":{"date":"2026-10-02"}}],"nextPageToken":"2"}\'',
      'else',
      'echo \'{"error":{"code":500,"message":"boom","reason":"backendError"}}\'',
      'exit 1',
      'fi',
    })
    vim.env.FAKE_GWS_COUNT_FILE = count_file
    setup_config({ gws_cmd = script_path })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({
      kind = 'api',
      code = 500,
      message = 'boom',
      reason = 'backendError',
    }, err)
  end)

  it('list のコールバックが 1 回だけ呼ばれる', function()
    local count = 0
    gws.list_events({ calendar_id = 'primary' }, function()
      count = count + 1
    end)

    assert.is_true(vim.wait(10000, function()
      return count > 0
    end, 10))
    vim.wait(100)
    assert.are.equal(1, count)
  end)

  it('終日予定の timeZone は落とし、時刻付きで timeZone が無い場合は補わない', function()
    local all_day = event.normalize({
      id = 'evt-tz-all-day',
      summary = '終日',
      start = { date = '2026-10-28', timeZone = 'Asia/Tokyo' },
      ['end'] = { date = '2026-10-29' },
    }, { calendar_id = 'primary' })

    assert.is_nil(all_day.start.timeZone)

    local timed = event.normalize({
      id = 'evt-tz-timed',
      summary = '定例',
      start = { dateTime = '2026-10-28T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
    }, { calendar_id = 'primary' })

    assert.is_nil(timed.start.timeZone)
  end)

  it('items が配列でない invalid_output にも stderr を含める', function()
    local script_path = tmp_root .. '/items-not-array-gws'
    write_script(script_path, {
      '#!/bin/sh',
      'echo \'{"items":"oops"}\'',
      'echo diag >&2',
      'exit 0',
    })
    setup_config({ gws_cmd = script_path })

    local events, err = await(function(callback)
      gws.list_events({ calendar_id = 'primary' }, callback)
    end)

    assert.is_nil(events)
    assert.are.same({
      kind = 'invalid_output',
      output = '{"items":"oops"}',
      stderr = 'diag\n',
    }, err)
  end)

  it('status を予定モデルへ引き継ぐ', function()
    local item = event.normalize({
      id = 'evt-status',
      summary = '定例',
      status = 'confirmed',
      start = { date = '2026-10-28' },
      ['end'] = { date = '2026-10-29' },
    }, { calendar_id = 'primary' })

    assert.are.equal('confirmed', item.status)
  end)
end)
