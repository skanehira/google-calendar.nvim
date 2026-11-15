local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local slots = require('google-calendar.slots')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

M.openers = {
  search = function(conditions)
    require('google-calendar.ui.slots').open(conditions)
  end,
  help = function(screen)
    require('google-calendar.ui.help').open(screen)
  end,
}

local SCREEN = 'slot_filter'
local FOOTER_ITEMS = {
  { action = 'toggle', label = '選択' },
  { action = 'search', label = '検索' },
  { action = 'esc_close', label = '閉じる' },
  { action = 'close', label = '隠す' },
}

local rows = {}
local cursor = 1
local selection = {}

local function selectable_rows()
  local result = {}
  for index, row in ipairs(rows) do
    if row.kind ~= 'header' then
      table.insert(result, index)
    end
  end
  return result
end

local function build_rows(today)
  local cfg = config.get()
  rows = { { kind = 'header', label = '時間帯' } }
  for _, value in ipairs(cfg.slots.time_ranges) do
    local range = assert(slots.parse_time_range(value))
    table.insert(rows, { kind = 'time_range', value = value, label = range.start .. ' ~ ' .. range.finish })
  end
  table.insert(rows, { kind = 'header', label = '所要時間' })
  for _, minutes in ipairs(cfg.slots.durations) do
    table.insert(rows, { kind = 'duration', value = minutes, label = slots.duration_label(minutes) })
  end
  table.insert(rows, { kind = 'header', label = '週' })
  for _, week in ipairs(slots.week_options(today, cfg.week_start, cfg.slots.weeks)) do
    table.insert(rows, { kind = 'week', value = week.start_date, week = week, label = week.label })
  end
end

local function is_selected(row)
  if row.kind == 'week' then
    return selection.weeks[row.value] == true
  end
  return selection[row.kind] == row.value
end

local function build_lines()
  local lines = {}
  local highlights = {}
  local current = selectable_rows()[cursor]
  for index, row in ipairs(rows) do
    if row.kind == 'header' then
      table.insert(lines, ' ' .. row.label)
      table.insert(highlights, { line = index - 1, start_col = 1, end_col = -1, group = 'GoogleCalendarHeader' })
    else
      local mark = is_selected(row) and '●' or '○'
      table.insert(lines, (index == current and '>' or ' ') .. mark .. ' ' .. row.label)
      if is_selected(row) then
        table.insert(
          highlights,
          { line = index - 1, start_col = 1, end_col = 1 + #mark, group = 'GoogleCalendarSelected' }
        )
      end
    end
  end
  return lines, highlights
end

local function footer()
  local parts = {}
  for _, item in ipairs(FOOTER_ITEMS) do
    local key = config.resolve(SCREEN, item.action)
    if key ~= nil then
      table.insert(parts, key .. ':' .. item.label)
    end
  end
  return ' ' .. table.concat(parts, ' ') .. ' '
end

local function window_opts(lines)
  local width = math.max(window.max_display_width(lines) + 2, vim.fn.strdisplaywidth(footer()))
  width = math.max(1, math.min(width, vim.o.columns - 2))
  local height = math.max(1, math.min(#lines, vim.o.lines - 2))
  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - (height + 2)) / 2)),
    col = math.max(0, math.floor((vim.o.columns - (width + 2)) / 2)),
    title = ' 空き枠を探す ',
    footer = footer(),
  }
end

local function render()
  local win = state.windows[SCREEN]
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local lines, highlights = build_lines()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace('google-calendar-slot-filter')
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, highlight in ipairs(highlights) do
    local end_col = highlight.end_col
    if end_col < 0 then
      end_col = #lines[highlight.line + 1]
    end
    vim.api.nvim_buf_set_extmark(buf, ns, highlight.line, highlight.start_col, {
      end_col = end_col,
      hl_group = highlight.group,
    })
  end

  vim.api.nvim_win_set_cursor(win, { selectable_rows()[cursor], 0 })
end

local function move(delta)
  cursor = math.min(#selectable_rows(), math.max(1, cursor + delta))
  render()
end

local function toggle()
  local row = rows[selectable_rows()[cursor]]
  if row.kind == 'week' then
    selection.weeks[row.value] = not selection.weeks[row.value] or nil
  else
    selection[row.kind] = row.value
  end
  render()
end

local function search()
  local weeks = {}
  for _, row in ipairs(rows) do
    if row.kind == 'week' and selection.weeks[row.value] then
      table.insert(weeks, row.week)
    end
  end
  if #weeks == 0 then
    config.get().notify('Select at least one week', vim.log.levels.WARN)
    return
  end

  M.openers.search({
    time_range = slots.parse_time_range(selection.time_range),
    duration = selection.duration,
    dates = slots.target_dates(weeks, config.get().slots.weekdays),
  })
end

local function close()
  window.close(SCREEN)
end

local key_actions = {
  next = function()
    move(1)
  end,
  prev = function()
    move(-1)
  end,
  toggle = toggle,
  search = search,
  help = function()
    M.openers.help(SCREEN)
  end,
  close = window.hide_all,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve(SCREEN, action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

---@param opts? { today?: string }
function M.open(opts)
  opts = opts or {}
  local today = opts.today or calendar.today()
  local cfg = config.get()

  build_rows(today)
  cursor = 1
  selection = {
    time_range = cfg.slots.default_time_range,
    duration = cfg.slots.default_duration,
    weeks = {},
  }
  for _, row in ipairs(rows) do
    if row.kind == 'week' then
      selection.weeks[row.value] = true
      break
    end
  end

  local lines = build_lines()
  local win = state.windows[SCREEN]
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, window_opts(lines))
    vim.api.nvim_set_current_win(win)
  else
    win = window.open(SCREEN, window_opts(lines))
  end
  vim.wo[win].winhl = 'FloatBorder:GoogleCalendarBorder,FloatTitle:GoogleCalendarHeader'
  vim.wo[win].cursorline = true

  set_keymaps(vim.api.nvim_win_get_buf(win))
  render()
  return win
end

return M
