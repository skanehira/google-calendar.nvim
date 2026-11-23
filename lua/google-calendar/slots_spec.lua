---@diagnostic disable: undefined-field
local slots = require('google-calendar.slots')

local function timed(start, finish, extra)
  return vim.tbl_extend('force', {
    id = start,
    summary = 'busy',
    start = { dateTime = start },
    ['end'] = { dateTime = finish },
  }, extra or {})
end

local function find(events, overrides)
  return slots.find(
    events,
    vim.tbl_extend('force', {
      dates = { '2026-11-16' },
      time_range = { start = '09:00', finish = '18:00' },
      duration = 60,
      buffer = 60,
      now = '2026-11-15 08:00',
      local_offset = '+0900',
    }, overrides or {})
  )
end

describe('slots.is_busy', function()
  local cases = {
    {
      name = '時刻指定の予定',
      item = timed('2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00'),
      busy = true,
    },
    {
      name = '終日予定',
      item = { start = { date = '2026-11-16' }, ['end'] = { date = '2026-11-17' } },
      busy = false,
    },
    {
      name = '取り消された予定',
      item = timed('2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00', { status = 'cancelled' }),
      busy = false,
    },
    {
      name = '「空き時間」表示の予定',
      item = timed('2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00', { transparency = 'transparent' }),
      busy = false,
    },
    {
      name = '自分が辞退した予定',
      item = timed('2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00', {
        attendees = {
          { email = 'other@example.com', responseStatus = 'accepted' },
          { email = 'me@example.com', self = true, responseStatus = 'declined' },
        },
      }),
      busy = false,
    },
    {
      name = '他のゲストだけが辞退した予定',
      item = timed('2026-11-16T10:00:00+09:00', '2026-11-16T11:00:00+09:00', {
        attendees = {
          { email = 'other@example.com', responseStatus = 'declined' },
          { email = 'me@example.com', self = true, responseStatus = 'accepted' },
        },
      }),
      busy = true,
    },
  }

  for _, case in ipairs(cases) do
    it(case.name .. 'は埋まっている=' .. tostring(case.busy), function()
      assert.are.equal(case.busy, slots.is_busy(case.item))
    end)
  end
end)

describe('slots.find', function()
  it('予定がない日は時間帯全体を 1 件の候補にする', function()
    assert.are.same({ { date = '2026-11-16', start = '09:00', finish = '18:00' } }, find({}))
  end)

  it('埋まっている予定の前後 buffer 分を除いた空き時間を候補にする', function()
    local events = { timed('2026-11-16T12:00:00+09:00', '2026-11-16T13:00:00+09:00') }

    assert.are.same({
      { date = '2026-11-16', start = '09:00', finish = '11:00' },
      { date = '2026-11-16', start = '14:00', finish = '18:00' },
    }, find(events))
  end)

  it('空き時間が所要時間ちょうどなら候補にし、短ければ候補にしない', function()
    local events = {
      timed('2026-11-16T09:00:00+09:00', '2026-11-16T10:00:00+09:00'),
      timed('2026-11-16T13:00:00+09:00', '2026-11-16T14:00:00+09:00'),
      timed('2026-11-16T16:00:00+09:00', '2026-11-16T17:30:00+09:00'),
    }

    assert.are.same({ { date = '2026-11-16', start = '11:00', finish = '12:00' } }, find(events))
    assert.are.same({}, find(events, { duration = 90 }))
  end)

  it('前後の予定の buffer が接して空きが 0 分なら候補にしない', function()
    local events = {
      timed('2026-11-16T08:00:00+09:00', '2026-11-16T10:00:00+09:00'),
      timed('2026-11-16T12:00:00+09:00', '2026-11-16T17:00:00+09:00'),
    }

    assert.are.same({}, find(events, { duration = 30 }))
  end)

  it('予定の端数を丸めずに候補の端にする', function()
    local events = { timed('2026-11-16T09:30:00+09:00', '2026-11-16T10:15:00+09:00') }

    assert.are.same({ { date = '2026-11-16', start = '11:15', finish = '18:00' } }, find(events))
  end)

  it('埋まっていない予定は空き時間を塞がない', function()
    local events = {
      timed('2026-11-16T12:00:00+09:00', '2026-11-16T13:00:00+09:00', { transparency = 'transparent' }),
      { start = { date = '2026-11-16' }, ['end'] = { date = '2026-11-17' } },
    }

    assert.are.same({ { date = '2026-11-16', start = '09:00', finish = '18:00' } }, find(events))
  end)

  it('前日から続く予定は翌日の時間帯も塞ぐ', function()
    local events = { timed('2026-11-15T20:00:00+09:00', '2026-11-16T09:30:00+09:00') }

    assert.are.same({ { date = '2026-11-16', start = '10:30', finish = '18:00' } }, find(events))
  end)

  it('ローカルと異なるオフセットの予定をローカル時刻に直して判定する', function()
    local events = { timed('2026-11-16T03:00:00Z', '2026-11-16T04:00:00Z') }

    assert.are.same({
      { date = '2026-11-16', start = '09:00', finish = '11:00' },
      { date = '2026-11-16', start = '14:00', finish = '18:00' },
    }, find(events))
  end)

  it(
    '今日は現在時刻を 30 分単位に切り上げた時刻より前を除き、過去の日は対象にしない',
    function()
      local result = find({}, {
        dates = { '2026-11-15', '2026-11-16', '2026-11-17' },
        now = '2026-11-16 10:10',
      })

      assert.are.same({
        { date = '2026-11-16', start = '10:30', finish = '18:00' },
        { date = '2026-11-17', start = '09:00', finish = '18:00' },
      }, result)
    end
  )

  it('現在時刻がちょうど 30 分単位ならその時刻から候補にする', function()
    local result = find({}, { now = '2026-11-16 13:00' })

    assert.are.same({ { date = '2026-11-16', start = '13:00', finish = '18:00' } }, result)
  end)

  it('複数の日を日付順に並べる', function()
    local events = { timed('2026-11-17T09:00:00+09:00', '2026-11-17T17:00:00+09:00') }

    local result = find(events, { dates = { '2026-11-18', '2026-11-16', '2026-11-17' } })

    assert.are.same({
      { date = '2026-11-16', start = '09:00', finish = '18:00' },
      { date = '2026-11-18', start = '09:00', finish = '18:00' },
    }, result)
  end)

  it('時間帯の終了 24:00 を 24:00 として返す', function()
    local result = find({}, { time_range = { start = '21:00', finish = '24:00' } })

    assert.are.same({ { date = '2026-11-16', start = '21:00', finish = '24:00' } }, result)
  end)
end)

describe('slots.week_options', function()
  it('日曜始まりで今日を含む週から指定した数の週を並べる', function()
    assert.are.same({
      { start_date = '2026-11-15', end_date = '2026-11-21', label = '11/15(日)~11/21(土)' },
      { start_date = '2026-11-22', end_date = '2026-11-28', label = '11/22(日)~11/28(土)' },
    }, slots.week_options('2026-11-18', 'sunday', 2))
  end)

  it('月曜始まりでは日曜の今日を前の月曜から始まる週に含める', function()
    assert.are.same({
      { start_date = '2026-11-09', end_date = '2026-11-15', label = '11/09(月)~11/15(日)' },
      { start_date = '2026-11-16', end_date = '2026-11-22', label = '11/16(月)~11/22(日)' },
    }, slots.week_options('2026-11-15', 'monday', 2))
  end)
end)

describe('slots.target_dates', function()
  it('選んだ週の日付のうち指定した曜日だけを日付順に返す', function()
    local weeks = {
      { start_date = '2026-11-29', end_date = '2026-12-05' },
      { start_date = '2026-11-15', end_date = '2026-11-21' },
    }

    assert.are.same(
      { '2026-11-16', '2026-11-20', '2026-11-30', '2026-12-04' },
      slots.target_dates(weeks, { 'monday', 'friday' })
    )
  end)
end)

describe('slots.format', function()
  it('候補を番号なしの yyyy/mm/dd hh:mm ~ hh:mm 形式にする', function()
    local lines = slots.format({
      { date = '2026-11-16', start = '09:00', finish = '10:00' },
      { date = '2026-12-01', start = '13:30', finish = '24:00' },
    })

    assert.are.same({ '2026/11/16 09:00 ~ 10:00', '2026/12/01 13:30 ~ 24:00' }, lines)
  end)

  it('weekday を指定すると日付に曜日を付ける', function()
    local lines = slots.format({
      { date = '2026-11-16', start = '09:00', finish = '10:00' },
      { date = '2026-12-01', start = '13:30', finish = '24:00' },
    }, { weekday = true })

    assert.are.same({ '2026/11/16(月) 09:00 ~ 10:00', '2026/12/01(火) 13:30 ~ 24:00' }, lines)
  end)
end)

describe('slots.parse_time_range', function()
  local cases = {
    { input = '09:00-18:00', expected = { start = '09:00', finish = '18:00' } },
    { input = '00:00-24:00', expected = { start = '00:00', finish = '24:00' } },
    { input = '18:00-09:00', expected = nil },
    { input = '09:00-24:30', expected = nil },
    { input = '9:00-18:00', expected = nil },
    { input = '09:60-18:00', expected = nil },
  }

  for _, case in ipairs(cases) do
    it(case.input .. ' を解釈する', function()
      assert.are.same(case.expected, slots.parse_time_range(case.input))
    end)
  end
end)

describe('slots.duration_label', function()
  local cases = { { 30, '30分' }, { 60, '1時間' }, { 90, '1時間30分' }, { 120, '2時間' } }

  for _, case in ipairs(cases) do
    it(case[1] .. ' 分を ' .. case[2] .. ' と表記する', function()
      assert.are.equal(case[2], slots.duration_label(case[1]))
    end)
  end
end)
