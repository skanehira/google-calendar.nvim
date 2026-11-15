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

  it(':GoogleCalendar の補完が slots と YYYY-MM の候補を返す', function()
    local candidates = vim.fn.getcompletion('GoogleCalendar ', 'cmdline')

    assert.are.equal('slots', candidates[1])
    assert.are.equal(26, #candidates)
    for index = 2, #candidates do
      assert.is_truthy(candidates[index]:match('^%d%d%d%d%-%d%d$'))
    end
  end)

  it(':GoogleCalendar の補完が入力中の文字列で候補を絞る', function()
    assert.are.same({ 'slots' }, vim.fn.getcompletion('GoogleCalendar sl', 'cmdline'))
  end)

  it('init.setup が config に設定を反映する', function()
    require('google-calendar').setup({ week_start = 'monday', gws_cmd = 'fake-gws' })

    local cfg = config.get()
    assert.are.equal('monday', cfg.week_start)
    assert.are.equal('fake-gws', cfg.gws_cmd)
  end)
end)
