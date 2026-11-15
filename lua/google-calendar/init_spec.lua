---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local state = require('google-calendar.state')
local notify = require('google-calendar.notify')
local window = require('google-calendar.ui.window')

local repo_root = vim.fn.getcwd()

local month_view_open_calls
local month_view_stub = {
  open = function()
    month_view_open_calls = month_view_open_calls + 1
    return true
  end,
}

local slot_filter_open_calls
local slot_filter_stub = {
  open = function()
    slot_filter_open_calls = slot_filter_open_calls + 1
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
    slot_filter_open_calls = 0
    package.loaded['google-calendar.ui.slot_filter'] = slot_filter_stub
    state.reset()
    notify.reset()
    vim.cmd('runtime! plugin/google-calendar.lua')
  end)

  after_each(function()
    window.close_all()
    package.loaded['google-calendar.ui.slot_filter'] = nil
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
  it(':GoogleCalendar slots は月表示ではなく空き枠の条件選択を開く', function()
    plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })

    vim.cmd('GoogleCalendar slots')

    assert.are.equal(1, slot_filter_open_calls)
    assert.are.equal(0, month_view_open_calls)
    assert.are.same({}, notifications)
  end)

  it(
    'gws が見つからない状態で :GoogleCalendar slots を実行すると通知し、条件選択を開かない',
    function()
      plugin.setup({ gws_cmd = '/nonexistent/google-calendar/gws', notify = capture })

      vim.cmd('GoogleCalendar slots')

      assert.are.same({
        {
          message = 'gws was not found. Install gws by following the setup instructions in README.md.',
          level = vim.log.levels.ERROR,
        },
      }, notifications)
      assert.are.equal(0, slot_filter_open_calls)
    end
  )

  local float_opts = { relative = 'editor', width = 20, height = 5, row = 1, col = 1 }

  local function is_hidden(win)
    return vim.api.nvim_win_get_config(win).hide == true
  end

  it(
    '隠している間に引数なしの :GoogleCalendar を実行すると、隠した画面をそのまま表示する',
    function()
      plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })
      state.year, state.month, state.selected_date = 2025, 1, '2025-01-15'
      window.open('month', float_opts)
      local agenda_win = window.open('agenda', float_opts)
      window.hide_all()

      vim.cmd('GoogleCalendar')

      assert.is_false(is_hidden(agenda_win))
      assert.are.equal(agenda_win, vim.api.nvim_get_current_win())
      assert.are.same({ 2025, 1, '2025-01-15' }, { state.year, state.month, state.selected_date })
      assert.are.equal(0, month_view_open_calls)
    end
  )

  for _, case in ipairs({
    { args = '2026-12', month_calls = 1, slot_calls = 0 },
    { args = 'slots', month_calls = 0, slot_calls = 1 },
  }) do
    it(
      '隠している間に :GoogleCalendar '
        .. case.args
        .. ' を実行すると、隠した画面を閉じてから開く',
      function()
        plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })
        local month_win = window.open('month', float_opts)
        window.hide_all()

        vim.cmd('GoogleCalendar ' .. case.args)

        assert.is_false(vim.api.nvim_win_is_valid(month_win))
        assert.are.equal(0, #state.stack)
        assert.are.same({ case.month_calls, case.slot_calls }, { month_view_open_calls, slot_filter_open_calls })
      end
    )
  end

  it(
    'toggle() は表示中の画面を隠し、隠した画面を表示し、何も開いていなければ月表示を開く',
    function()
      plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })
      local original = vim.api.nvim_get_current_win()
      local month_win = window.open('month', float_opts)

      plugin.toggle()
      assert.is_true(is_hidden(month_win))
      assert.are.equal(original, vim.api.nvim_get_current_win())

      plugin.toggle()
      assert.is_false(is_hidden(month_win))
      assert.are.equal(month_win, vim.api.nvim_get_current_win())

      window.close_all()
      plugin.toggle()
      assert.are.equal(1, month_view_open_calls)
    end
  )

  it('toggle() は :q で閉じた月表示を開いていないものとして扱い、月表示を開く', function()
    plugin.setup({ gws_cmd = repo_root .. '/tests/fixtures/fake-gws.py', notify = capture })
    local month_win = window.open('month', float_opts)
    vim.api.nvim_win_close(month_win, true)

    plugin.toggle()

    assert.are.equal(1, month_view_open_calls)
  end)
end)
