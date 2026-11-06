---@diagnostic disable: undefined-field
local calendar_store = require('google-calendar.calendar_store')

describe('calendar_store', function()
  before_each(function()
    calendar_store.reset()
  end)

  after_each(function()
    calendar_store.reset()
  end)

  it('primary をメールアドレスと名前に整形する', function()
    calendar_store.set({
      {
        id = 'me@example.com',
        summary = 'My Calendar',
        primary = true,
      },
      {
        id = 'work@example.com',
        summary = 'Work',
      },
    })

    assert.are.equal('me@example.com (My Calendar)', calendar_store.label('primary'))
    assert.are.equal('work@example.com (Work)', calendar_store.label('work@example.com'))
  end)

  it('summaryOverride を名前に使い、名前がメールアドレスと同じなら重複させない', function()
    calendar_store.set({
      {
        id = 'me@example.com',
        summary = 'Default Name',
        summaryOverride = 'Override Name',
        primary = true,
      },
      {
        id = 'same@example.com',
        summary = 'same@example.com',
      },
    })

    assert.are.equal('me@example.com (Override Name)', calendar_store.label('primary'))
    assert.are.equal('same@example.com', calendar_store.label('same@example.com'))
  end)

  it('カレンダーが見つからない場合は ID をそのまま返す', function()
    calendar_store.set({})

    assert.are.equal('primary', calendar_store.label('primary'))
    assert.are.equal('unknown@example.com', calendar_store.label('unknown@example.com'))
    assert.is_nil(calendar_store.label(nil))
  end)

  it('ensure_loaded はカレンダー一覧を一度だけ取得する', function()
    local original_gws = package.loaded['google-calendar.gws']
    local calls = 0
    package.loaded['google-calendar.gws'] = {
      list_calendars = function(callback)
        calls = calls + 1
        callback({
          {
            id = 'me@example.com',
            summary = 'My Calendar',
            primary = true,
          },
        }, nil)
      end,
    }

    local loaded = false
    calendar_store.ensure_loaded(function(ok)
      loaded = ok
    end)
    calendar_store.ensure_loaded(function() end)

    assert.is_true(loaded)
    assert.are.equal(1, calls)
    assert.is_true(calendar_store.is_loaded())
    assert.are.equal('me@example.com (My Calendar)', calendar_store.label('primary'))

    package.loaded['google-calendar.gws'] = original_gws
  end)
end)
