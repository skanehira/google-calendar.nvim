---@diagnostic disable: undefined-field
local config = require('google-calendar.config')

describe('plugin', function()
  before_each(function()
    vim.cmd('runtime! plugin/google-calendar.lua')
  end)

  it('plugin を読み込むと :GoogleCalendar が登録される', function()
    assert.are.equal(2, vim.fn.exists(':GoogleCalendar'))

    local commands = vim.api.nvim_get_commands({})
    assert.are.equal('?', commands.GoogleCalendar.nargs)
  end)

  it(':GoogleCalendar の補完が YYYY-MM の候補を返す', function()
    local candidates = vim.fn.getcompletion('GoogleCalendar ', 'cmdline')

    assert.is_true(#candidates > 0)
    for _, candidate in ipairs(candidates) do
      assert.is_truthy(candidate:match('^%d%d%d%d%-%d%d$'))
    end
  end)

  it('init.setup が config に設定を反映する', function()
    require('google-calendar').setup({ week_start = 'monday', gws_cmd = 'fake-gws' })

    local cfg = config.get()
    assert.are.equal('monday', cfg.week_start)
    assert.are.equal('fake-gws', cfg.gws_cmd)
  end)
end)
