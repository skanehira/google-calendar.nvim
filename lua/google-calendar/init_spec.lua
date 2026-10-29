---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local state = require('google-calendar.state')
local notify = require('google-calendar.notify')

local repo_root = vim.fn.getcwd()

local month_view_open_calls
local month_view_stub = {
  open = function()
    month_view_open_calls = month_view_open_calls + 1
    return true
  end,
}

local previous_month_view = package.loaded['google-calendar.ui.month_view']
package.loaded['google-calendar.ui.month_view'] = month_view_stub
local plugin = require('google-calendar')
package.loaded['google-calendar.ui.month_view'] = previous_month_view

describe('init', function()
  local notifications

  local function capture(message, level)
    table.insert(notifications, { message = message, level = level })
  end

  before_each(function()
    notifications = {}
    month_view_open_calls = 0
    state.reset()
    notify.reset()
    vim.cmd('runtime! plugin/google-calendar.lua')
  end)

  after_each(function()
    config.setup({})
    notify.reset()
    state.reset()
  end)

  it(
    'gws が PATH にない状態で :GoogleCalendar を実行すると、インストール方法を含む通知を出し、月表示を開かない',
    function()
      plugin.setup({ gws_cmd = '/nonexistent/google-calendar/gws', notify = capture })

      vim.cmd('GoogleCalendar')

      assert.are.same({
        {
          message = 'gws was not found. Install gws by following the setup instructions in README.md.',
          level = vim.log.levels.ERROR,
        },
      }, notifications)
      assert.are.equal(0, month_view_open_calls)
      assert.is_nil(state.windows.month)
      assert.are.equal(0, #state.stack)
    end
  )

  it(
    'gws が見つからない状態で :GoogleCalendar を繰り返しても、同じ通知は 1 回だけ出す',
    function()
      plugin.setup({ gws_cmd = '/nonexistent/google-calendar/gws', notify = capture })

      vim.cmd('GoogleCalendar')
      vim.cmd('GoogleCalendar')

      assert.are.equal(1, #notifications)
      assert.are.equal(0, month_view_open_calls)
    end
  )

  it('gws が PATH にある場合は月表示を開く', function()
    plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })

    vim.cmd('GoogleCalendar')

    assert.are.equal(1, month_view_open_calls)
    assert.are.equal(0, #notifications)
  end)
end)
