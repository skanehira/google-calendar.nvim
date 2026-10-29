---@diagnostic disable: undefined-field
describe('e2e smoke', function()
  before_each(function()
    if vim.env.FAKE_GWS_STATE then
      os.remove(vim.env.FAKE_GWS_STATE)
    end
  end)

  it('偽 gws が PATH の先頭にあり、実カレンダーを使わない', function()
    local executable = vim.fn.exepath('gws')
    assert.is_truthy(executable)

    local state_dir = vim.fn.fnamemodify(vim.env.FAKE_GWS_STATE, ':h')
    assert.are.equal(vim.fn.resolve(state_dir), vim.fn.resolve(vim.fn.fnamemodify(executable, ':h:h')))
  end)

  it('偽 gws の events list が空の items を返す', function()
    local result = vim
      .system({
        'gws',
        'calendar',
        'events',
        'list',
        '--params',
        '{"calendarId":"primary","timeMin":"2026-10-01T00:00:00+09:00","timeMax":"2026-11-01T00:00:00+09:00"}',
        '--format',
        'json',
      }, { text = true })
      :wait()

    assert.are.equal(0, result.code)
    assert.are.same({ items = {} }, vim.json.decode(result.stdout))
  end)

  it('偽 gws の +insert が予定を追加し、list に反映される', function()
    local insert = vim
      .system({
        'gws',
        'calendar',
        '+insert',
        '--summary',
        'smoke',
        '--start',
        '2026-10-27T09:00:00+09:00',
        '--end',
        '2026-10-27T10:00:00+09:00',
        '--format',
        'json',
      }, { text = true })
      :wait()

    assert.are.equal(0, insert.code)
    assert.is_truthy(vim.json.decode(insert.stdout).id)

    local list = vim
      .system({
        'gws',
        'calendar',
        'events',
        'list',
        '--params',
        '{"calendarId":"primary","timeMin":"2026-10-01T00:00:00+09:00","timeMax":"2026-11-01T00:00:00+09:00"}',
        '--format',
        'json',
      }, { text = true })
      :wait()

    assert.are.equal(0, list.code)
    local body = vim.json.decode(list.stdout)
    assert.are.equal(1, #body.items)
    assert.are.equal('smoke', body.items[1].summary)
  end)

  it(':GoogleCalendar が登録されている', function()
    vim.cmd('runtime! plugin/google-calendar.lua')

    assert.are.equal(2, vim.fn.exists(':GoogleCalendar'))
  end)

  it('setup が上書きを反映し、setup() で既定値に戻る', function()
    local plugin = require('google-calendar')
    plugin.setup({ gws_cmd = 'gws', keymaps = { form = { save = '<A-s>' } } })

    local config = require('google-calendar.config').get()
    assert.are.equal('gws', config.gws_cmd)
    assert.are.equal('<A-s>', config.keymaps.form.save)

    plugin.setup()

    config = require('google-calendar.config').get()
    assert.are.equal(':w', config.keymaps.form.save)
  end)
end)
