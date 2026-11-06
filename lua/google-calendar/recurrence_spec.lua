---@diagnostic disable: undefined-field, need-check-nil
local recurrence = require('google-calendar.recurrence')

describe('recurrence', function()
  it('開始日からプリセットのラベルと RRULE を作る', function()
    local presets = recurrence.presets('2026-11-13 14:00')
    local labels = {}
    for _, preset in ipairs(presets) do
      table.insert(labels, preset.label)
    end

    assert.are.same({
      '繰り返さない',
      '毎日',
      '毎週 金曜日',
      '毎月 第2金曜日',
      '毎年 11月13日',
      '毎週平日（月〜金）',
      'カスタム...',
    }, labels)
    assert.are.equal('FREQ=WEEKLY;BYDAY=FR', recurrence.key(presets[3].config))
    assert.are.equal('FREQ=MONTHLY;BYDAY=2FR', recurrence.key(presets[4].config))
    assert.are.equal('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', recurrence.key(presets[6].config))
  end)

  it('RRULE を解析してラベル・終了条件を復元する', function()
    local config = recurrence.parse({
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T235959Z',
    })

    assert.are.equal('WEEKLY', config.freq)
    assert.are.equal(2, config.interval)
    assert.are.same({ 'MO', 'WE' }, config.byday)
    assert.are.equal('until', config.end_type)
    assert.are.equal('2026-12-31', config.until_date)
    assert.are.equal('2週ごと 月・水曜日（2026-12-31 まで）', recurrence.label(config, '2026-11-13'))
    assert.are.same({
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T235959Z',
    }, recurrence.to_api(config))
    assert.are.same({
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231',
    }, recurrence.to_api(config, true))
  end)

  it('COUNT と月次・年次のラベルを扱う', function()
    local monthly = recurrence.parse({ 'RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=5' })
    assert.are.equal('毎月 最終金曜日（5 回）', recurrence.label(monthly, '2026-11-13'))
    assert.are.equal('FREQ=MONTHLY;BYDAY=-1FR;COUNT=5', recurrence.key(monthly))

    local yearly = recurrence.parse({ 'RRULE:FREQ=YEARLY' })
    assert.are.equal('毎年 11月13日', recurrence.label(yearly, '2026-11-13'))
  end)

  it('曜日テキストを RRULE の曜日コードへ変換する', function()
    assert.are.same({ 'MO', 'WE' }, recurrence.parse_weekday_text('月,水', '2026-11-13'))
    assert.are.same({ 'FR' }, recurrence.parse_weekday_text('', '2026-11-13'))
    assert.are.equal('月,水', recurrence.weekday_text({ 'WE', 'MO' }))
  end)

  it('終了日・回数・間隔を検証する', function()
    assert.is_false(recurrence.validate({
      freq = 'WEEKLY',
      interval = 0,
      byday = { 'FR' },
    }, '2026-11-13'))
    assert.is_false(recurrence.validate({
      freq = 'WEEKLY',
      interval = 1,
      byday = {},
    }, '2026-11-13'))
    assert.is_false(recurrence.validate({
      freq = 'DAILY',
      interval = 1,
      end_type = 'until',
      until_date = '2026-11-13',
    }, '2026-11-13'))
    assert.is_true(recurrence.validate({
      freq = 'DAILY',
      interval = 1,
      end_type = 'count',
      count = 10,
    }, '2026-11-13'))
  end)

  it('プリセットに一致しない設定はカスタムとして扱う', function()
    local custom = recurrence.parse({ 'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR' })
    assert.are.equal('custom', recurrence.preset_key(custom, '2026-11-13'))
    assert.are.equal('weekly', recurrence.preset_key(recurrence.parse({ 'RRULE:FREQ=WEEKLY;BYDAY=FR' }), '2026-11-13'))
    assert.are.equal('none', recurrence.preset_key(nil, '2026-11-13'))
  end)
end)
