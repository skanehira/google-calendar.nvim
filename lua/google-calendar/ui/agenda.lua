local config = require('google-calendar.config')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

-- 予定詳細とヘルプの実装は別機能が持つため、キー処理からは opener 経由で呼ぶ
M.openers = {
  open_detail = function(item)
    require('google-calendar.ui.detail').open(item)
  end,
  help = function(screen)
    require('google-calendar.ui.help').open(screen)
  end,
}

local selected_index = 1
local line_starts = {}

local function current_events()
  return state.events_by_date[state.selected_date] or {}
end

local function build_lines(events, width)
  if #events == 0 then
    return { '予定なし' }, {}
  end

  local lines = {}
  local starts = {}
  for index, item in ipairs(events) do
    local prefix = event.time_range(item) or ''
    local available = math.max(0, width - vim.fn.strdisplaywidth(prefix) - 1)
    local title = event.truncate(event.sanitize(item.summary), available)

    starts[index] = #lines + 1
    if title == '' then
      table.insert(lines, prefix)
    else
      table.insert(lines, prefix .. ' ' .. title)
    end

    if item.location ~= nil and item.location ~= '' then
      table.insert(lines, '@' .. event.truncate(event.sanitize(item.location), math.max(0, width - 1)))
    end
  end

  return lines, starts
end

local function window_size(count)
  local width = math.max(1, math.min(60, vim.o.columns - 8))
  local height = math.max(1, math.min(count + 4, 20))

  return width, height
end

local function window_position(width, height)
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  return row, col
end

local function place_cursor()
  local win = state.windows.agenda
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local line = line_starts[selected_index]
  if line ~= nil then
    vim.api.nvim_win_set_cursor(win, { line, 0 })
  end
end

local function render(win, events, width)
  local buf = vim.api.nvim_win_get_buf(win)
  local lines, starts = build_lines(events, width)
  line_starts = starts

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  place_cursor()
end

local function move(delta)
  local count = #current_events()
  if count == 0 then
    return
  end

  selected_index = math.min(count, math.max(1, selected_index + delta))
  place_cursor()
end

local function open_detail()
  local item = current_events()[selected_index]
  if item == nil then
    return
  end

  M.openers.open_detail(item)
end

local function open_help()
  M.openers.help('agenda')
end

local function close()
  window.close('agenda')
end

local key_actions = {
  next = function()
    move(1)
  end,
  prev = function()
    move(-1)
  end,
  open = open_detail,
  help = open_help,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve('agenda', action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

function M.refresh()
  local win = state.windows.agenda
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local events = current_events()
  selected_index = math.max(1, math.min(#events, selected_index))
  render(win, events, vim.api.nvim_win_get_width(win))

  return true
end

function M.open()
  local events = current_events()
  local width, height = window_size(#events)
  local row, col = window_position(width, height)
  local opts = { relative = 'editor', width = width, height = height, row = row, col = col }

  local win = state.windows.agenda
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, opts)
  else
    win = window.open('agenda', opts)
  end

  selected_index = 1
  render(win, events, width)
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  set_keymaps(vim.api.nvim_win_get_buf(win))
  vim.api.nvim_set_current_win(win)

  return win
end

return M
