---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local notify_module = require('google-calendar.notify')
local plugin = require('google-calendar')
local slots = require('google-calendar.slots')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local state_path = assert(vim.env.FAKE_GWS_STATE)

local function feed(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'x', false)
end

local function list_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.windows.slots), 0, -1, false)
end

describe('e2e slots', function()
  local copied
  local original_has

  before_each(function()
    vim.cmd('runtime! plugin/google-calendar.lua')
    state.reset()
    notify_module.reset()
    copied = {}
    original_has = vim.fn.has
    -- headless の Neovim はクリップボードを持たないため、コピーの成功系だけを再現する
    rawset(vim.fn, 'has', function(feature)
      if feature == 'clipboard' then
        return 1
      end
      return original_has(feature)
    end)
    plugin.setup({
      gws_cmd = 'gws',
      notify = function() end,
      clipboard = function(text)
        table.insert(copied, text)
      end,
    })
  end)

  after_each(function()
    for index = #state.stack, 1, -1 do
      window.close(state.stack[index].name)
    end
    rawset(vim.fn, 'has', original_has)
    config.setup({})
  end)

  it(
    ':GoogleCalendar slots で来週を選び、予定の前後 1 時間を避けた候補をコピーできる',
    function()
      local next_week = slots.week_options(calendar.today(), config.get().week_start, 2)[2]
      local busy_date = calendar.add_days(next_week.start_date, 1)
      vim.fn.writefile({
        vim.json.encode({
          items = {
            {
              id = 'evt-busy',
              summary = '定例',
              start = { dateTime = calendar.rfc3339(busy_date, '12:00') },
              ['end'] = { dateTime = calendar.rfc3339(busy_date, '13:00') },
            },
          },
        }),
      }, state_path)

      vim.cmd('GoogleCalendar slots')
      -- 今週の選択を外し、来週を選ぶ
      feed('jjjjjj<Space>j<Space><CR>')
      assert.is_true(vim.wait(5000, function()
        return state.windows.slots ~= nil and list_lines()[1] ~= '読み込み中...'
      end, 20))

      feed('y')

      local expected = {}
      for offset = 0, 6 do
        local date = calendar.add_days(next_week.start_date, offset)
        if date == busy_date then
          table.insert(expected, { date = date, start = '09:00', finish = '11:00' })
          table.insert(expected, { date = date, start = '14:00', finish = '18:00' })
        else
          table.insert(expected, { date = date, start = '09:00', finish = '18:00' })
        end
      end
      assert.are.same({ table.concat(slots.format(expected), '\n') }, copied)
    end
  )
end)
