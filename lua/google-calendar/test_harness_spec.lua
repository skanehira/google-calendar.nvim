---@diagnostic disable: undefined-field
local repo_root = vim.fn.getcwd()
local fake_gws = repo_root .. '/tests/fixtures/fake-gws.py'

local tmp_root
local state_path

local function new_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local file = assert(io.open(path, 'w'))
  file:write(vim.json.encode(value))
  file:close()
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

local function write_text(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local file = assert(io.open(path, 'w'))
  file:write(text)
  file:close()
end

local function read_text(path)
  local file = assert(io.open(path, 'r'))
  local content = file:read('*a')
  file:close()
  return content
end

local function plenary_path()
  return os.getenv('PLENARY_PATH') or (os.getenv('HOME') .. '/.local/share/nvim/lazy/plenary.nvim')
end

local function run_fake(args, opts)
  opts = opts or {}
  local env = vim.fn.environ()
  env.FAKE_GWS_STATE = opts.state or state_path
  for key, value in pairs(opts.env or {}) do
    env[key] = value
  end

  local command = { 'python3', fake_gws }
  vim.list_extend(command, args)
  return vim.system(command, { cwd = opts.cwd or tmp_root, env = env, text = true }):wait()
end

local function run_make(args, env)
  local merged = vim.fn.environ()
  merged.PLENARY_PATH = plenary_path()
  merged.XDG_STATE_HOME = tmp_root .. '/xdg-state'
  -- 親の plenary が設定する PLENARY_TEST_TIMEOUT (文字列) を子の make test に
  -- 引き継ぐと、非空ディレクトリの nested 実行が失敗するため落とす。
  merged.PLENARY_TEST_TIMEOUT = nil
  for key, value in pairs(env or {}) do
    merged[key] = value
  end

  local command = { 'make' }
  vim.list_extend(command, args)
  -- env をそのまま渡すと vim.system が現在の env とマージして
  -- PLENARY_TEST_TIMEOUT が復活するため、clear_env で完全に置き換える。
  return vim.system(command, { cwd = repo_root, env = merged, clear_env = true, text = true }):wait()
end

local function run_nvim(args, env)
  local merged = vim.fn.environ()
  merged.PLENARY_PATH = plenary_path()
  merged.XDG_STATE_HOME = tmp_root .. '/xdg-state'
  for key, value in pairs(env or {}) do
    merged[key] = value
  end

  local command = { vim.v.progpath, '--headless', '-u', 'tests/minimal_init.lua' }
  vim.list_extend(command, args)
  return vim.system(command, { cwd = repo_root, env = merged, text = true }):wait()
end

local timed_event = {
  id = 'evt-1',
  summary = '定例',
  start = { dateTime = '2026-10-27T09:00:00+09:00' },
  ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
}

local all_day_event = {
  id = 'evt-2',
  summary = '終日',
  start = { date = '2026-10-30' },
  ['end'] = { date = '2026-10-31' },
}

describe('test harness', function()
  before_each(function()
    tmp_root = new_tmp_dir()
    state_path = tmp_root .. '/state.json'
  end)

  after_each(function()
    vim.fn.delete(tmp_root, 'rf')
  end)

  it('偽 gws の events list が状態ファイルの予定を期間で絞って返す', function()
    write_json(state_path, {
      items = {
        timed_event,
        all_day_event,
        {
          id = 'evt-3',
          summary = '範囲外',
          start = { dateTime = '2026-11-05T09:00:00+09:00' },
          ['end'] = { dateTime = '2026-11-05T10:00:00+09:00' },
        },
      },
    })

    local result = run_fake({
      'calendar',
      'events',
      'list',
      '--params',
      '{"calendarId":"primary","timeMin":"2026-10-01T00:00:00+09:00","timeMax":"2026-11-01T00:00:00+09:00"}',
      '--format',
      'json',
    })

    assert.are.equal(0, result.code)
    assert.are.same({ items = { timed_event, all_day_event } }, vim.json.decode(result.stdout))
  end)

  it('偽 gws の calendar +insert --meet が予定を追加し、id と hangoutLink を返す', function()
    local result = run_fake({
      'calendar',
      '+insert',
      '--summary',
      'test',
      '--start',
      '2026-10-27T09:00:00+09:00',
      '--end',
      '2026-10-27T10:00:00+09:00',
      '--meet',
      '--format',
      'json',
    })

    assert.are.equal(0, result.code)
    local body = vim.json.decode(result.stdout)
    assert.is_truthy(body.id)
    assert.is_truthy(body.hangoutLink:match('^https://meet%.google%.com/[a-z%-]+$'))

    local normalized = vim.deepcopy(body)
    normalized.id = '<id>'
    normalized.hangoutLink = '<meet>'
    assert.are.same({
      id = '<id>',
      summary = 'test',
      start = { dateTime = '2026-10-27T09:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T10:00:00+09:00' },
      hangoutLink = '<meet>',
    }, normalized)

    local state = read_json(state_path)
    assert.are.equal(1, #state.items)
    assert.are.equal(body.id, state.items[1].id)
    assert.are.equal(body.hangoutLink, state.items[1].hangoutLink)
  end)

  it('偽 gws の events insert が終日予定を追加し、id を返す', function()
    local result = run_fake({
      'calendar',
      'events',
      'insert',
      '--params',
      '{"calendarId":"primary"}',
      '--json',
      '{"summary":"all-day","start":{"date":"2026-10-27"},"end":{"date":"2026-10-28"}}',
      '--format',
      'json',
    })

    assert.are.equal(0, result.code)
    local body = vim.json.decode(result.stdout)
    local normalized = vim.deepcopy(body)
    normalized.id = '<id>'
    assert.are.same({
      id = '<id>',
      summary = 'all-day',
      start = { date = '2026-10-27' },
      ['end'] = { date = '2026-10-28' },
    }, normalized)
    assert.are.equal(1, #read_json(state_path).items)
  end)

  it('偽 gws の events get が予定を返し、存在しない ID では 404 を返す', function()
    write_json(state_path, { items = { timed_event } })

    local found = run_fake({
      'calendar',
      'events',
      'get',
      '--params',
      '{"calendarId":"primary","eventId":"evt-1"}',
      '--format',
      'json',
    })
    assert.are.equal(0, found.code)
    assert.are.same(timed_event, vim.json.decode(found.stdout))

    local missing = run_fake({
      'calendar',
      'events',
      'get',
      '--params',
      '{"calendarId":"primary","eventId":"evt-404"}',
      '--format',
      'json',
    })
    assert.are.equal(1, missing.code)
    assert.are.same({
      error = { code = 404, message = 'Not Found', reason = 'notFound' },
    }, vim.json.decode(missing.stdout))
  end)

  it('偽 gws の events update が予定を置換して返す', function()
    write_json(state_path, { items = { timed_event } })

    local result = run_fake({
      'calendar',
      'events',
      'update',
      '--params',
      '{"calendarId":"primary","eventId":"evt-1"}',
      '--json',
      '{"summary":"更新後",'
        .. '"start":{"dateTime":"2026-10-27T11:00:00+09:00"},'
        .. '"end":{"dateTime":"2026-10-27T12:00:00+09:00"}}',
      '--format',
      'json',
    })

    local expected = {
      id = 'evt-1',
      summary = '更新後',
      start = { dateTime = '2026-10-27T11:00:00+09:00' },
      ['end'] = { dateTime = '2026-10-27T12:00:00+09:00' },
    }
    assert.are.equal(0, result.code)
    assert.are.same(expected, vim.json.decode(result.stdout))
    assert.are.same({ items = { expected } }, read_json(state_path))
  end)

  it(
    '偽 gws の events delete が予定を削除し、cwd に download.html を生成して cwd を記録する',
    function()
      write_json(state_path, { items = { timed_event } })
      local cwd = tmp_root .. '/delete-cwd'
      vim.fn.mkdir(cwd, 'p')
      local cwd_log = tmp_root .. '/cwd.log'

      local result = run_fake({
        'calendar',
        'events',
        'delete',
        '--params',
        '{"calendarId":"primary","eventId":"evt-1"}',
        '--format',
        'json',
      }, { cwd = cwd, env = { FAKE_GWS_CWD_LOG = cwd_log } })

      assert.are.equal(0, result.code)
      assert.are.same({ status = 'success' }, vim.json.decode(result.stdout))
      assert.are.equal(0, vim.fn.getfsize(cwd .. '/download.html'))
      local lines = read_lines(cwd_log)
      assert.are.equal(1, #lines)
      assert.are.equal(vim.fn.resolve(cwd), vim.fn.resolve(lines[1]))
      assert.are.same({ items = {} }, read_json(state_path))
    end
  )

  it('偽 gws は認証エラー fixture を返し、終了コード 2 で終了する', function()
    local result = run_fake({
      'calendar',
      'events',
      'list',
      '--params',
      '{"calendarId":"primary"}',
      '--format',
      'json',
    }, { env = { FAKE_GWS_ERROR_FIXTURE = repo_root .. '/tests/fixtures/auth-error.json' } })

    assert.are.equal(2, result.code)
    assert.are.same({
      error = { code = 401, message = 'Request had invalid authentication credentials.', reason = 'authError' },
    }, vim.json.decode(result.stdout))
  end)

  it('偽 gws の events list は pageToken で次ページを返し、2 ページ分を取得できる', function()
    local events = {
      timed_event,
      all_day_event,
      {
        id = 'evt-3',
        summary = '3 件目',
        start = { dateTime = '2026-10-28T09:00:00+09:00' },
        ['end'] = { dateTime = '2026-10-28T10:00:00+09:00' },
      },
    }
    write_json(state_path, { items = events })

    local params =
      '{"calendarId":"primary","timeMin":"2026-10-01T00:00:00+09:00","timeMax":"2026-11-01T00:00:00+09:00"}'
    local first = run_fake({
      'calendar',
      'events',
      'list',
      '--params',
      params,
      '--format',
      'json',
    }, { env = { FAKE_GWS_PAGE_SIZE = '2' } })
    assert.are.equal(0, first.code)
    local first_body = vim.json.decode(first.stdout)
    assert.are.equal(2, #first_body.items)
    assert.are.equal('2', first_body.nextPageToken)

    local second_params = vim.json.encode(vim.tbl_extend('force', vim.json.decode(params), {
      pageToken = first_body.nextPageToken,
    }))
    local second = run_fake({
      'calendar',
      'events',
      'list',
      '--params',
      second_params,
      '--format',
      'json',
    }, { env = { FAKE_GWS_PAGE_SIZE = '2' } })
    assert.are.equal(0, second.code)
    local second_body = vim.json.decode(second.stdout)
    assert.are.equal(1, #second_body.items)
    assert.is_nil(second_body.nextPageToken)

    local combined = vim.list_extend(vim.deepcopy(first_body.items), second_body.items)
    assert.are.same(events, combined)
  end)

  it('spec が 0 件のディレクトリで PlenaryBustedDirectory を実行すると非 0 で終了する', function()
    local empty = tmp_root .. '/empty-spec'
    vim.fn.mkdir(empty, 'p')

    local result = run_nvim({
      '-c',
      string.format("PlenaryBustedDirectory %s {minimal_init = 'tests/minimal_init.lua'}", empty),
    })

    assert.is_true(result.code ~= 0)
    assert.is_truthy(result.stderr:match('spec が 0 件'))
  end)

  it('spec が 0 件のとき make test は失敗する', function()
    local empty = tmp_root .. '/empty-spec'
    vim.fn.mkdir(empty, 'p')

    local env = vim.fn.environ()
    env.PLENARY_PATH = plenary_path()
    env.XDG_STATE_HOME = tmp_root .. '/xdg-state'

    local result = vim
      .system({ 'make', 'test', 'TEST_DIR=' .. empty }, {
        cwd = repo_root,
        env = env,
        text = true,
      })
      :wait()

    assert.is_true(result.code ~= 0)
    assert.is_truthy((result.stdout .. result.stderr):match('spec が 0 件'))
  end)

  it('make test が TEST_DIR の spec を plenary の busted harness で実行する', function()
    local spec_dir = tmp_root .. '/marker-spec'
    local marker = tmp_root .. '/marker-ran.txt'
    vim.fn.mkdir(spec_dir, 'p')
    write_text(
      spec_dir .. '/marker_spec.lua',
      string.format(
        [[
describe('marker', function()
  it('marker spec が実行される', function()
    local file = assert(io.open(%q, 'w'))
    file:write('marker ran')
    file:close()
  end)
end)
]],
        marker
      )
    )

    local result = run_make({ 'test', 'TEST_DIR=' .. spec_dir })

    assert.are.equal(0, result.code)
    assert.are.equal('marker ran', read_text(marker))
    assert.is_truthy(result.stderr:match('Success: 1, Failed: 0, Errors: 0'))
  end)

  it('make test が lua/ 配下の spec を実行する', function()
    local result = run_make({ 'test', 'TEST_DIR=lua/google-calendar/ui' })

    assert.are.equal(0, result.code)
    assert.is_truthy(result.stdout:find(repo_root .. '/lua/google-calendar/ui/window_spec.lua', 1, true))
    assert.is_truthy(result.stderr:match('Success: [1-9]%d*, Failed: 0, Errors: 0'))
  end)

  it('make check が lint / format-check / typecheck / test を順に実行する', function()
    local result = vim.system({ 'make', '-n', 'check' }, { cwd = repo_root, text = true }):wait()

    assert.are.equal(0, result.code)
    assert.are.same({
      'luacheck lua/ plugin/ tests/',
      'stylua --check lua/ plugin/ tests/',
      'scripts/typecheck.sh',
      'scripts/test.sh',
    }, vim.split(result.stdout, '\n', { trimempty = true }))
  end)

  it(
    'XDG_STATE_HOME を指定しないとき harness が書き込み可能なディレクトリを設定してテストを実行する',
    function()
      local spec_dir = tmp_root .. '/xdg-spec'
      local probe = tmp_root .. '/xdg-state-home.txt'
      vim.fn.mkdir(spec_dir, 'p')
      write_text(
        spec_dir .. '/xdg_state_spec.lua',
        string.format(
          [[
describe('xdg state', function()
  it('XDG_STATE_HOME が設定され、nvim の state ディレクトリがその配下になる', function()
    assert.is_truthy(vim.env.XDG_STATE_HOME)
    assert.are.equal(vim.env.XDG_STATE_HOME .. '/nvim', vim.fn.stdpath('state'))
    local file = assert(io.open(%q, 'w'))
    file:write(vim.env.XDG_STATE_HOME)
    file:close()
  end)
end)
]],
          probe
        )
      )

      local env = vim.fn.environ()
      env.PLENARY_PATH = plenary_path()
      env.PLENARY_TEST_TIMEOUT = nil
      env.XDG_STATE_HOME = nil

      local result = vim
        .system({ 'make', 'test', 'TEST_DIR=' .. spec_dir }, {
          cwd = repo_root,
          env = env,
          clear_env = true,
          text = true,
        })
        :wait()

      assert.are.equal(0, result.code)
      assert.are.equal(repo_root .. '/.tmp-state', read_text(probe))
    end
  )
end)
