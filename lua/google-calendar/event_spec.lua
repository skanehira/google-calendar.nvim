---@diagnostic disable: undefined-field
local event = require('google-calendar.event')

local function build_event(id, summary, start, finish)
  return { id = id, summary = summary, start = start, ['end'] = finish }
end

local function timed_event(id, summary, date_time)
  return build_event(id, summary, { dateTime = date_time }, { dateTime = date_time })
end

local function ids_by_date(events_by_date)
  local result = {}
  for date, events in pairs(events_by_date) do
    result[date] = vim.tbl_map(function(item)
      return item.id
    end, events)
  end
  return result
end

describe('event', function()
  describe('local_datetime', function()
    it('イベントのオフセットを考慮してローカル時刻へ変換する', function()
      local date, time = event.local_datetime('2026-10-27T09:00:00+09:00', '+0900')

      assert.are.equal('2026-10-27', date)
      assert.are.equal('09:00', time)
    end)

    it('UTC の予定をローカル時刻へ変換する', function()
      local date, time = event.local_datetime('2026-10-27T00:00:00Z', '+0900')

      assert.are.equal('2026-10-27', date)
      assert.are.equal('09:00', time)
    end)

    it('日付をまたぐオフセットをローカル時刻へ変換する', function()
      local date, time = event.local_datetime('2026-10-27T20:00:00-04:00', '+0900')

      assert.are.equal('2026-10-28', date)
      assert.are.equal('09:00', time)
    end)

    it('小数秒付きの RFC3339 を変換する', function()
      local date, time = event.local_datetime('2026-10-27T09:00:00.123+09:00', '+0900')

      assert.are.equal('2026-10-27', date)
      assert.are.equal('09:00', time)
    end)
  end)

  describe('is_all_day', function()
    it('start.date を持つ予定を終日予定として扱う', function()
      assert.is_true(event.is_all_day(build_event('a', nil, { date = '2026-10-28' })))
      assert.is_false(event.is_all_day(timed_event('b', nil, '2026-10-28T09:00:00+09:00')))
    end)
  end)

  describe('start_date / start_time', function()
    it('時刻付き予定の開始日と開始時刻をローカル時刻で返す', function()
      local item = timed_event('evt-1', '定例', '2026-10-27T09:00:00+09:00')

      assert.are.equal('2026-10-27', event.start_date(item, '+0900'))
      assert.are.equal('09:00', event.start_time(item, '+0900'))
    end)

    it('終日予定の開始日を返し、開始時刻は nil を返す', function()
      local item = build_event('evt-2', nil, { date = '2026-10-28' }, { date = '2026-10-29' })

      assert.are.equal('2026-10-28', event.start_date(item, '+0900'))
      assert.is_nil(event.start_time(item, '+0900'))
    end)
  end)

  describe('events_by_date', function()
    it(
      '終日予定は開始日から終了日の前日まで各日に載せ、時刻付きは開始日に載せる',
      function()
        local events = {
          build_event('all-day', nil, { date = '2026-10-27' }, { date = '2026-10-30' }),
          timed_event('timed-09', nil, '2026-10-27T09:00:00+09:00'),
          timed_event('timed-08', nil, '2026-10-27T08:00:00+09:00'),
          timed_event('timed-28', nil, '2026-10-28T07:00:00+09:00'),
          timed_event('outside', nil, '2026-11-10T09:00:00+09:00'),
        }

        local by_date = event.events_by_date(events, '2026-09-27', '2026-11-07', '+0900')

        assert.are.same({
          ['2026-10-27'] = { 'all-day', 'timed-08', 'timed-09' },
          ['2026-10-28'] = { 'all-day', 'timed-28' },
          ['2026-10-29'] = { 'all-day' },
        }, ids_by_date(by_date))
      end
    )

    it('時刻付きの複数日予定は開始日から終了日まで各日に載せる', function()
      local events = {
        build_event(
          'timed-multiday',
          nil,
          { dateTime = '2026-10-27T12:00:00+09:00' },
          { dateTime = '2026-10-29T13:00:00+09:00' }
        ),
      }

      local by_date = event.events_by_date(events, '2026-10-01', '2026-10-31', '+0900')

      assert.are.same({
        ['2026-10-27'] = { 'timed-multiday' },
        ['2026-10-28'] = { 'timed-multiday' },
        ['2026-10-29'] = { 'timed-multiday' },
      }, ids_by_date(by_date))
    end)

    it('取得範囲の外にある終日予定の日を切り捨てる', function()
      local events = {
        build_event('clipped', nil, { date = '2026-10-30' }, { date = '2026-11-02' }),
      }

      local by_date = event.events_by_date(events, '2026-10-01', '2026-10-31', '+0900')

      assert.are.same({ ['2026-10-30'] = { 'clipped' }, ['2026-10-31'] = { 'clipped' } }, ids_by_date(by_date))
    end)

    it('同時刻の予定は入力順を保つ', function()
      local events = {
        timed_event('first', nil, '2026-10-27T09:00:00+09:00'),
        timed_event('second', nil, '2026-10-27T09:00:00+09:00'),
      }

      local by_date = event.events_by_date(events, '2026-10-27', '2026-10-27', '+0900')

      assert.are.same({ ['2026-10-27'] = { 'first', 'second' } }, ids_by_date(by_date))
    end)
  end)

  describe('chip', function()
    it('時刻付き予定を HH:MM タイトル の形式にする', function()
      local item = timed_event('evt-1', '定例', '2026-10-27T09:00:00+09:00')

      assert.are.equal('09:00 定例', event.chip(item, 20, '+0900'))
    end)

    it('終日予定を 終日 タイトル の形式にする', function()
      local item = build_event('evt-2', '休み', { date = '2026-10-28' })

      assert.are.equal('終日 休み', event.chip(item, 20, '+0900'))
    end)

    it('タイトルを表示幅に合わせて … で切り詰める', function()
      local item = timed_event('evt-1', '定例ミーティング', '2026-10-27T09:00:00+09:00')

      assert.are.equal('09:00 定…', event.chip(item, 10, '+0900'))
      assert.are.equal('09:00 定例…', event.chip(item, 12, '+0900'))
    end)

    it('終日予定のタイトルも表示幅に合わせて切り詰める', function()
      local item = build_event('evt-2', '定例会議', { date = '2026-10-28' })

      assert.are.equal('終日 定…', event.chip(item, 8, '+0900'))
    end)

    it('タイトルの改行を空白に置き換える', function()
      local item = build_event('evt-3', '1行目\n2行目', { date = '2026-10-28' })

      assert.are.equal('終日 1行目 2行目', event.chip(item, 30, '+0900'))
    end)
  end)

  describe('time_range', function()
    it('時刻付き予定を開始時刻と終了時刻の範囲にする', function()
      local item = build_event(
        'evt-1',
        '定例',
        { dateTime = '2026-10-27T09:00:00+09:00' },
        { dateTime = '2026-10-27T10:30:00+09:00' }
      )

      assert.are.equal('09:00-10:30', event.time_range(item, '+0900'))
    end)

    it('終日予定を終日にする', function()
      local item = build_event('evt-2', '休み', { date = '2026-10-28' }, { date = '2026-10-29' })

      assert.are.equal('終日', event.time_range(item, '+0900'))
    end)
  end)

  describe('display_datetime', function()
    it('時刻付きの日時を YYYY-MM-DD HH:MM の形式にする', function()
      assert.are.equal('2026-10-27 09:00', event.display_datetime({ dateTime = '2026-10-27T09:00:00+09:00' }, '+0900'))
    end)

    it('終日予定の日付をそのまま返す', function()
      assert.are.equal('2026-10-28', event.display_datetime({ date = '2026-10-28' }, '+0900'))
    end)

    it('時刻を持たない値には nil を返す', function()
      assert.is_nil(event.display_datetime(nil, '+0900'))
      assert.is_nil(event.display_datetime({}, '+0900'))
    end)
  end)

  describe('description_lines', function()
    it('説明の改行をそのまま行の配列にする', function()
      assert.are.same({ '1行目', '2行目' }, event.description_lines('1行目\n2行目', 5))
    end)

    it('最大行数を超える説明は末尾に … を付けて切り詰める', function()
      assert.are.same({ '1', '2', '3', '4', '5…' }, event.description_lines('1\n2\n3\n4\n5\n6\n7', 5))
    end)

    it('説明が空または無い場合は nil を返す', function()
      assert.is_nil(event.description_lines('', 5))
      assert.is_nil(event.description_lines(nil, 5))
    end)
  end)

  describe('meet_url', function()
    it('hangout_link を優先し、なければ conferenceData の video entryPoint を使う', function()
      assert.are.equal(
        'https://meet.google.com/primary-url',
        event.meet_url({
          hangout_link = 'https://meet.google.com/primary-url',
          conferenceData = {
            entryPoints = { { entryPointType = 'video', uri = 'https://meet.google.com/fallback-url' } },
          },
        })
      )
      assert.are.equal(
        'https://meet.google.com/fallback-url',
        event.meet_url({
          conferenceData = {
            entryPoints = {
              { entryPointType = 'phone', uri = 'tel:+1-555-0100' },
              { entryPointType = 'video', uri = 'https://meet.google.com/fallback-url' },
            },
          },
        })
      )
    end)

    it('空文字または未設定の Meet URL は nil を返す', function()
      assert.is_nil(event.meet_url({ hangout_link = '' }))
      assert.is_nil(event.meet_url({}))
    end)
  end)
end)
