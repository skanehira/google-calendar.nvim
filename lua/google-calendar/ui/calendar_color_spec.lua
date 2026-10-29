---@diagnostic disable: undefined-field
local calendar_color = require('google-calendar.ui.calendar_color')
local config = require('google-calendar.config')

describe('ui.calendar_color', function()
  before_each(function()
    config.setup({ calendars = { 'primary', 'work@example.com', 'third@example.com' } })
  end)

  it('calendars の順に色を割り当てる', function()
    assert.are.equal('GoogleCalendarCalendarColor1', calendar_color.dot_group('primary'))
    assert.are.equal('GoogleCalendarCalendarColor2', calendar_color.dot_group('work@example.com'))
    assert.are.equal('GoogleCalendarCalendarColor3', calendar_color.dot_group('third@example.com'))
    assert.are.equal('GoogleCalendarCalendarBg1', calendar_color.bar_group('primary'))
    assert.are.equal('GoogleCalendarCalendarBg2', calendar_color.bar_group('work@example.com'))
    assert.are.equal('GoogleCalendarCalendarBg3', calendar_color.bar_group('third@example.com'))
  end)

  it('12 件目以降は先頭の色に戻る', function()
    local calendars = {}
    for index = 1, 12 do
      table.insert(calendars, 'calendar' .. index .. '@example.com')
    end
    config.setup({ calendars = calendars })

    assert.are.equal('GoogleCalendarCalendarColor11', calendar_color.dot_group(calendars[11]))
    assert.are.equal('GoogleCalendarCalendarColor1', calendar_color.dot_group(calendars[12]))
  end)

  it('未設定のカレンダーは同じ ID に対して安定した色を返す', function()
    local first = calendar_color.dot_group('unknown@example.com')
    local second = calendar_color.dot_group('unknown@example.com')

    assert.are.equal(first, second)
    assert.are.equal((first:gsub('CalendarColor', 'CalendarBg')), calendar_color.bar_group('unknown@example.com'))
  end)
end)
