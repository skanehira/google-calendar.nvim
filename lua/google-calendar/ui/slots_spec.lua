---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local notify = require('google-calendar.notify')
local slots_ui = require('google-calendar.ui.slots')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local original_deps
local original_has
local original_columns
local original_lines
local fetches
local copied
local notifications

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function lines_of(name)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows[name]), 0, -1, false)
end

local function title_of(name)
  local title = vim.api.nvim_win_get_config(state.windows[name]).title
  return title[1][1]
end

local function topline_of(name)
  return vim.api.nvim_win_call(state.windows[name], function()
    return vim.fn.winsaveview().topline
  end)
end

local function timed(id, summary, start, finish, extra)
  return vim.tbl_extend('force', {
    id = id,
    summary = summary,
    calendar_id = 'primary',
    start = { dateTime = start },
    ['end'] = { dateTime = finish },
  }, extra or {})
end

local conditions = {
  time_range = { start = '09:00', finish = '18:00' },
  duration = 60,
  dates = { '2026-11-16', '2026-11-17' },
}

local function close_all()
  for index = #state.stack, 1, -1 do
    window.close(state.stack[index].name)
  end
end

describe('ui.slots.build_timeline', function()
  before_each(function()
    config.setup({})
  end)

  it(
    '予定を 30 分 1 行のブロックで描き、重なる予定を候補と同じ幅の中で横に並べ、終日予定を winbar に置く',
    function()
      local events = {
        timed('a', 'ホンダ朝会', '2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00'),
        timed('b', 'daily', '2026-11-16T10:00:00+09:00', '2026-11-16T10:30:00+09:00'),
        timed('c', '定例', '2026-11-16T15:00:00+09:00', '2026-11-16T16:00:00+09:00'),
        timed(
          'd',
          '辞退',
          '2026-11-16T16:00:00+09:00',
          '2026-11-16T17:00:00+09:00',
          { transparency = 'transparent' }
        ),
        {
          id = 'e',
          summary = '出張',
          calendar_id = 'primary',
          start = { date = '2026-11-16' },
          ['end'] = { date = '2026-11-17' },
        },
      }

      local timeline = slots_ui.build_timeline('2026-11-16', events, nil, 37, '+0900')

      assert.are.equal(48, #timeline.lines)
      -- 終日予定のラベルも、候補と同じ列から右端までの 30 列に広げる
      assert.are.equal(
        '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarCalendarBg1#出張' .. string.rep(' ', 26) .. '%*',
        timeline.winbar
      )
      assert.are.same(
        { '00:00 │' .. string.rep(' ', 30), '      │' .. string.rep(' ', 30) },
        vim.list_slice(timeline.lines, 1, 2)
      )
      -- 内容の幅は 37 - 7 = 30。候補のブロックも 30 列なので、予定も右端を 30 列目に揃える
      assert.are.same({
        '10:00 │ホンダ朝会     daily 10:00~10…',
        '      │10:00~11:00' .. string.rep(' ', 19),
        '11:00 │' .. string.rep(' ', 30),
      }, vim.list_slice(timeline.lines, 21, 23))
      assert.are.same({
        '15:00 │定例' .. string.rep(' ', 26),
        '      │15:00~16:00' .. string.rep(' ', 19),
        '16:00 │' .. string.rep(' ', 30),
      }, vim.list_slice(timeline.lines, 31, 33))
    end
  )

  it('時刻の右の縦線を、すべての行で薄いグレーのハイライトにする', function()
    local timeline = slots_ui.build_timeline('2026-11-16', {}, nil, 27, '+0900')

    local rulers = {}
    for _, highlight in ipairs(timeline.highlights) do
      if highlight.group == 'GoogleCalendarSlotRuler' then
        table.insert(rulers, { highlight.line, highlight.start_col, highlight.end_col })
      end
    end
    local expected = {}
    for row = 0, 47 do
      table.insert(expected, { row, #'00:00 ', #'00:00 │' })
    end
    assert.are.same(expected, rulers)
  end)

  it(
    '各時間の最後の行のうち、予定と候補のブロックが無い部分にだけ横線を引く',
    function()
      local events = {
        timed('a', 'ホンダ朝会', '2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00'),
        timed('b', 'daily', '2026-11-16T10:00:00+09:00', '2026-11-16T10:30:00+09:00'),
        timed('c', 'qss定例', '2026-11-16T14:00:00+09:00', '2026-11-16T15:00:00+09:00'),
      }
      local candidate = { date = '2026-11-16', start = '16:00', finish = '17:00' }

      local timeline = slots_ui.build_timeline('2026-11-16', events, candidate, 37, '+0900')

      local hour_lines = {}
      for _, highlight in ipairs(timeline.highlights) do
        if highlight.group == 'GoogleCalendarSlotHourLine' then
          table.insert(hour_lines, { highlight.line, highlight.start_col, highlight.end_col })
        end
      end
      local label = #'      │'
      local expected = {}
      for row = 1, 47, 2 do
        if row == 21 then
          -- 10:30 の行は左の列だけ予定が続き、隙間と右の列が空いている
          table.insert(expected, { row, label + 14, label + 30 })
        elseif row ~= 29 and row ~= 33 then
          -- 14:30 の行は予定、16:30 の行は候補のブロックなので引かない
          table.insert(expected, { row, label, label + 30 })
        end
      end
      assert.are.same(expected, hour_lines)
    end
  )

  it(
    '終日予定がなければ winbar に なし と表示し、タイトルの % をエスケープする',
    function()
      local all_day = {
        id = 'e',
        summary = '100% 出張',
        calendar_id = 'primary',
        start = { date = '2026-11-15' },
        ['end'] = { date = '2026-11-17' },
      }

      assert.are.equal(
        '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarDetailMuted#なし%*',
        slots_ui.build_timeline('2026-11-17', { all_day }, nil, 27, '+0900').winbar
      )
      assert.are.equal(
        '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarCalendarBg1#100%% 出張' .. string.rep(' ', 11) .. '%*',
        slots_ui.build_timeline('2026-11-16', { all_day }, nil, 27, '+0900').winbar
      )
    end
  )

  it(
    '今いるウィンドウの幅に関係なく、終日予定のラベルを内容の幅ぴったりに埋める',
    function()
      -- 幅 30 のウィンドウでは、このタイトルの「準」が行末をまたぐ。折り返しを数える幅の測り方だと 1 列多く数えてしまう
      local narrow = vim.api.nvim_open_win(
        vim.api.nvim_create_buf(false, true),
        true,
        { relative = 'editor', width = 30, height = 3, row = 0, col = 0 }
      )
      local title = 'kintailyの現状整理&お試しの下準備'
      local all_day = {
        id = 'g',
        summary = title,
        calendar_id = 'primary',
        start = { date = '2026-11-16' },
        ['end'] = { date = '2026-11-17' },
      }

      local timeline = slots_ui.build_timeline('2026-11-16', { all_day }, nil, 47, '+0900')
      vim.api.nvim_win_close(narrow, true)

      assert.are.equal(
        '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarCalendarBg1#'
          .. title
          .. string.rep(' ', 40 - 33)
          .. '%*',
        timeline.winbar
      )
    end
  )

  it('終日予定が複数あるときは、列の間に 1 列空けて内容の幅を分け合う', function()
    local function all_day(id, summary, calendar_id)
      return {
        id = id,
        summary = summary,
        calendar_id = calendar_id,
        start = { date = '2026-11-16' },
        ['end'] = { date = '2026-11-17' },
      }
    end

    local timeline = slots_ui.build_timeline(
      '2026-11-16',
      { all_day('a', '出張', 'primary'), all_day('b', '祝日', 'primary') },
      nil,
      27,
      '+0900'
    )

    assert.are.equal(
      '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarCalendarBg1#出張'
        .. string.rep(' ', 5)
        .. '%* %#GoogleCalendarCalendarBg1#祝日'
        .. string.rep(' ', 6)
        .. '%*',
      timeline.winbar
    )
  end)

  it('候補を背景付きのブロックで描き、候補の開始行を返す', function()
    local candidate = { date = '2026-11-16', start = '13:00', finish = '14:00' }

    local timeline = slots_ui.build_timeline('2026-11-16', {}, candidate, 27, '+0900')

    assert.are.same(
      { '13:00 │候補 13:00~14:00    ', '      │' .. string.rep(' ', 20), '14:00 │' .. string.rep(' ', 20) },
      vim.list_slice(timeline.lines, 27, 29)
    )
    assert.are.equal(27, timeline.candidate_line)
    local candidate_highlights = vim.tbl_filter(function(highlight)
      return highlight.group == 'GoogleCalendarSlotCandidate'
    end, timeline.highlights)
    assert.are.same({
      {
        line = 26,
        start_col = #'13:00 │',
        end_col = #'13:00 │候補 13:00~14:00    ',
        group = 'GoogleCalendarSlotCandidate',
      },
      { line = 27, start_col = #'      │', end_col = #'      │' + 20, group = 'GoogleCalendarSlotCandidate' },
    }, candidate_highlights)
  end)
end)

describe('ui.slots', function()
  before_each(function()
    state.reset()
    notify.reset()
    fetches = {}
    copied = {}
    notifications = {}
    config.setup({
      calendars = { 'work@example.com' },
      notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end,
      clipboard = function(text)
        table.insert(copied, text)
      end,
    })

    original_columns = vim.o.columns
    original_lines = vim.o.lines
    vim.o.columns = 120
    vim.o.lines = 40

    original_has = vim.fn.has
    -- ホストの clipboard 対応に依存せず成功系を検証するため、has('clipboard') を 1 に固定する
    rawset(vim.fn, 'has', function(feature)
      if feature == 'clipboard' then
        return 1
      end
      return original_has(feature)
    end)

    original_deps = vim.deepcopy(slots_ui.deps)
    slots_ui.deps.fetch_events = function(calendar_ids, time_min, time_max, callback)
      table.insert(
        fetches,
        { calendar_ids = calendar_ids, time_min = time_min, time_max = time_max, callback = callback }
      )
    end
    slots_ui.deps.now = function()
      return '2026-11-15 12:00'
    end
    slots_ui.deps.local_offset = '+0900'

    -- 条件選択の代わりの親ウィンドウ
    window.open('slot_filter', { relative = 'editor', width = 20, height = 5, row = 1, col = 1 })
  end)

  after_each(function()
    close_all()
    slots_ui.deps = original_deps
    rawset(vim.fn, 'has', original_has)
    vim.o.columns = original_columns
    vim.o.lines = original_lines
  end)

  it(
    '取得中は読み込み中を表示し、全カレンダーの前後 1 日を含む範囲から取得した予定で候補を並べる',
    function()
      slots_ui.open(conditions)

      assert.are.same({ '読み込み中...' }, lines_of('slots'))
      assert.are.equal(1, #fetches)
      assert.are.same({ 'primary', 'work@example.com' }, fetches[1].calendar_ids)
      assert.are.equal('2026-11-15T00:00:00', fetches[1].time_min:sub(1, 19))
      assert.are.equal('2026-11-19T00:00:00', fetches[1].time_max:sub(1, 19))

      fetches[1].callback({
        timed('a', '朝会', '2026-11-16T12:00:00+09:00', '2026-11-16T13:00:00+09:00'),
        timed('b', '終日会議', '2026-11-17T08:00:00+09:00', '2026-11-17T19:00:00+09:00'),
      }, nil)

      assert.are.same({ '>2026/11/16 09:00 ~ 11:00', ' 2026/11/16 14:00 ~ 18:00' }, lines_of('slots'))
      assert.are.equal(' 2026/11/16(月) ', title_of('slots_timeline'))
      assert.are.equal(vim.api.nvim_get_current_win(), state.windows.slots)
    end
  )

  it(
    'j/k で候補を選ぶと > が移り、タイムラインが候補の 2 時間前から見えるようにスクロールする',
    function()
      slots_ui.open(conditions)
      fetches[1].callback({ timed('a', '朝会', '2026-11-16T12:00:00+09:00', '2026-11-16T13:00:00+09:00') }, nil)
      assert.are.equal(15, topline_of('slots_timeline'))

      feed('j')

      assert.are.same({
        ' 2026/11/16 09:00 ~ 11:00',
        '>2026/11/16 14:00 ~ 18:00',
        ' 2026/11/17 09:00 ~ 18:00',
      }, lines_of('slots'))
      -- 4 行前 (25 行目) からだと末尾が余るため、ウィンドウが埋まる位置まで戻す
      local height = vim.fn.winheight(state.windows.slots_timeline)
      assert.are.equal(48 - height + 1, topline_of('slots_timeline'))
      assert.are.equal('14:00 │候補 14:00~18:00', vim.trim(lines_of('slots_timeline')[29]))

      feed('j')
      assert.are.equal(' 2026/11/17(火) ', title_of('slots_timeline'))

      feed('jk')
      assert.are.equal('>2026/11/16 14:00 ~ 18:00', lines_of('slots')[2])
      assert.are.equal(' 2026/11/16(月) ', title_of('slots_timeline'))
    end
  )

  it('y で表示中のすべての候補を番号なしでコピーして件数を通知する', function()
    slots_ui.open(conditions)
    fetches[1].callback({ timed('a', '朝会', '2026-11-16T12:00:00+09:00', '2026-11-16T13:00:00+09:00') }, nil)

    feed('y')

    assert.are.same({
      '2026/11/16 09:00 ~ 11:00\n2026/11/16 14:00 ~ 18:00\n2026/11/17 09:00 ~ 18:00',
    }, copied)
    assert.are.same({ { msg = 'Copied 3 slots', level = vim.log.levels.INFO } }, notifications)
  end)

  it(
    'タイムラインがウィンドウより短いときは、時刻の縦線をウィンドウの下端まで伸ばし、終日予定を winbar に出す',
    function()
      vim.o.lines = 80
      slots_ui.open(conditions)
      fetches[1].callback({
        {
          id = 'e',
          summary = '出張',
          calendar_id = 'primary',
          start = { date = '2026-11-16' },
          ['end'] = { date = '2026-11-17' },
        },
      }, nil)

      local win = state.windows.slots_timeline
      local lines = lines_of('slots_timeline')
      assert.is_true(vim.fn.winheight(win) > 48)
      assert.are.equal(vim.fn.winheight(win), #lines)
      local blank = string.rep(' ', vim.api.nvim_win_get_width(win) - 7)
      assert.are.same({ '23:00 │' .. blank, '      │' .. blank, '      │' }, vim.list_slice(lines, 47, 49))
      assert.are.equal('      │', lines[#lines])
      -- winbar の背景を本文と同じ float の背景にする (WinBar はカラースキームによって本体の背景で塗られる)
      local winhl = vim.wo[win].winhl
      assert.is_truthy(vim.tbl_contains(vim.split(winhl, ','), 'WinBar:NormalFloat'))
      assert.is_truthy(vim.tbl_contains(vim.split(winhl, ','), 'WinBarNC:NormalFloat'))
      -- 下端まで足した行の縦線も、時刻の行と同じ色にする
      local buf = vim.api.nvim_win_get_buf(win)
      local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { #lines - 1, 0 }, { #lines - 1, -1 }, { details = true })
      assert.are.same(
        { { #'      ', 'GoogleCalendarSlotRuler', #'      │' } },
        vim.tbl_map(function(mark)
          return { mark[3], mark[4].hl_group, mark[4].end_col }
        end, marks)
      )
      local content_width = vim.api.nvim_win_get_width(win) - 7
      assert.are.equal(
        '終日  %#GoogleCalendarSlotRuler#│%*%#GoogleCalendarCalendarBg1#出張'
          .. string.rep(' ', content_width - 4)
          .. '%*',
        vim.wo[win].winbar
      )
    end
  )

  it(
    '候補一覧を開いたまま再検索すると、左右とも開いたまま新しい要求の応答だけを表示する',
    function()
      slots_ui.open(conditions)
      slots_ui.open(vim.tbl_extend('force', conditions, { dates = { '2026-11-17' } }))
      -- 前の候補一覧を閉じたときに予約された処理を流す
      vim.wait(50)

      fetches[1].callback({}, nil)
      assert.are.same({ '読み込み中...' }, lines_of('slots'))

      fetches[2].callback({}, nil)
      assert.are.same({ '>2026/11/17 09:00 ~ 18:00' }, lines_of('slots'))
      assert.are.equal(' 2026/11/17(火) ', title_of('slots_timeline'))
    end
  )

  it(
    'クリップボードへの書き込みが失敗したら失敗を通知し、コピーしたとは通知しない',
    function()
      config.get().clipboard = function()
        error('clipboard provider failed')
      end
      slots_ui.open(conditions)
      fetches[1].callback({}, nil)

      feed('y')

      assert.are.same({ { msg = 'Could not copy to clipboard', level = vim.log.levels.ERROR } }, notifications)
    end
  )

  it('候補がなければ空き枠なしと表示し、y ではコピーせずに通知する', function()
    slots_ui.open(vim.tbl_extend('force', conditions, { dates = { '2026-11-17' } }))
    fetches[1].callback({ timed('b', '終日会議', '2026-11-17T08:00:00+09:00', '2026-11-17T19:00:00+09:00') }, nil)

    feed('y')

    assert.are.same({ '空き枠なし' }, lines_of('slots'))
    assert.are.same({ '' }, lines_of('slots_timeline'))
    assert.are.same({}, copied)
    assert.are.same({ { msg = 'No slots to copy', level = vim.log.levels.WARN } }, notifications)
  end)

  it('クリップボードが使えなければ失敗を通知する', function()
    rawset(vim.fn, 'has', function(feature)
      if feature == 'clipboard' then
        return 0
      end
      return original_has(feature)
    end)
    slots_ui.open(conditions)
    fetches[1].callback({}, nil)

    feed('y')

    assert.are.same({}, copied)
    assert.are.same({ { msg = 'Could not copy to clipboard', level = vim.log.levels.ERROR } }, notifications)
  end)

  it(
    'q で左右の候補一覧を閉じて条件選択に戻り、閉じた後に届いた応答は捨てる',
    function()
      slots_ui.open(conditions)

      feed('q')

      assert.is_nil(state.windows.slots)
      assert.is_nil(state.windows.slots_timeline)
      assert.are.equal(state.windows.slot_filter, vim.api.nvim_get_current_win())

      fetches[1].callback({}, nil)
      assert.is_nil(state.windows.slots)
    end
  )

  it('取得に失敗したらエラーを通知し、候補一覧を閉じて条件選択に戻る', function()
    slots_ui.open(conditions)

    fetches[1].callback(nil, { kind = 'network' })

    assert.are.same({ { msg = notify.message({ kind = 'network' }), level = vim.log.levels.ERROR } }, notifications)
    assert.is_nil(state.windows.slots)
    assert.is_nil(state.windows.slots_timeline)
    assert.are.equal(state.windows.slot_filter, vim.api.nvim_get_current_win())
  end)
end)

describe('ui.slots.fetch_events', function()
  local original_gws

  before_each(function()
    original_gws = package.loaded['google-calendar.gws']
  end)

  after_each(function()
    package.loaded['google-calendar.gws'] = original_gws
  end)

  local function fetch_with(responses)
    local requested = {}
    package.loaded['google-calendar.gws'] = {
      list_events = function(opts, callback)
        table.insert(requested, opts)
        local response = responses[opts.calendar_id]
        callback(response.events, response.err)
      end,
    }
    local results = {}
    slots_ui.fetch_events({ 'primary', 'work@example.com' }, 'min', 'max', function(events, err)
      table.insert(results, { events = events, err = err })
    end)
    -- 応答が揃う前に途中経過で呼ばれていないことも見るため、すべての応答を流してから呼び出し回数を数える
    vim.wait(100)
    return results, requested
  end

  it('すべてのカレンダーの応答を待ってから予定を合算して返す', function()
    local results, requested = fetch_with({
      primary = { events = { { id = 'a' } } },
      ['work@example.com'] = { events = { { id = 'b' }, { id = 'c' } } },
    })

    assert.are.same({
      { calendar_id = 'primary', time_min = 'min', time_max = 'max' },
      { calendar_id = 'work@example.com', time_min = 'min', time_max = 'max' },
    }, requested)
    assert.are.same({ { events = { { id = 'a' }, { id = 'b' }, { id = 'c' } } } }, results)
  end)

  it('どれかのカレンダーの取得に失敗したらエラーを返す', function()
    local results = fetch_with({
      primary = { events = { { id = 'a' } } },
      ['work@example.com'] = { err = { kind = 'network' } },
    })

    assert.are.same({ { err = { kind = 'network' } } }, results)
  end)
end)
