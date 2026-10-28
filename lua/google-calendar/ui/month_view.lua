local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local notify = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local namespace_name = 'google-calendar-month'
local request_seq = 0

local function center(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  local left = math.floor((width - text_width) / 2)
  local right = width - text_width - left
  return string.rep(' ', left) .. text .. string.rep(' ', right)
end

local function cell_highlights(cell, today, selected_date)
  local highlights = {}
  if not cell.in_month then
    table.insert(highlights, { hl = 'GoogleCalendarOtherMonth', priority = 10 })
  elseif cell.weekday == 0 then
    table.insert(highlights, { hl = 'GoogleCalendarSunday', priority = 10 })
  elseif cell.weekday == 6 then
    table.insert(highlights, { hl = 'GoogleCalendarSaturday', priority = 10 })
  end

  if cell.date == today then
    table.insert(highlights, { hl = 'GoogleCalendarToday', priority = 20 })
  end
  if cell.date == selected_date then
    table.insert(highlights, { hl = 'GoogleCalendarSelected', priority = 30, full_cell = true })
  end

  return highlights
end

local function chip_chunks(item, cell_w)
  local prefix, title = event.chip_parts(item, cell_w - 1)
  local chunks = { { ' ' .. prefix, 'GoogleCalendarEventTime' } }
  if title ~= '' then
    table.insert(chunks, { title, 'GoogleCalendarEvent' })
  end

  local used = 1 + vim.fn.strdisplaywidth(prefix) + vim.fn.strdisplaywidth(title)
  table.insert(chunks, { string.rep(' ', cell_w - used), 'GoogleCalendarEvent' })
  return chunks
end

local function overflow_chunks(count, cell_w)
  local text = '+' .. count
  local used = 1 + vim.fn.strdisplaywidth(text)
  return {
    { ' ' .. text, 'GoogleCalendarEvent' },
    { string.rep(' ', cell_w - used), 'GoogleCalendarEvent' },
  }
end

local function blank_chunks(cell_w)
  return { { string.rep(' ', cell_w) } }
end

local function build_event_rows(week, events_by_date, max_events, cell_w, selected_date)
  local lists = {}
  local rows = 0
  for index, cell in ipairs(week) do
    lists[index] = events_by_date[cell.date] or {}
    local shown = math.min(#lists[index], max_events)
    if #lists[index] > max_events then
      shown = shown + 1
    end
    if shown > rows then
      rows = shown
    end
  end

  local result = {}
  for row_index = 1, rows do
    local chunks = {}
    for index = 1, 7 do
      if index > 1 then
        table.insert(chunks, { '│' })
      end

      local list = lists[index]
      local cell_chunks
      if row_index <= math.min(#list, max_events) then
        cell_chunks = chip_chunks(list[row_index], cell_w)
      elseif row_index == rows and #list > max_events then
        cell_chunks = overflow_chunks(#list - max_events, cell_w)
      else
        cell_chunks = blank_chunks(cell_w)
      end

      -- 選択中の日は、日付行だけでなく予定行も含めたセル全体をハイライトする
      if week[index].date == selected_date then
        for _, chunk in ipairs(cell_chunks) do
          chunk[2] = 'GoogleCalendarSelected'
        end
      end

      for _, chunk in ipairs(cell_chunks) do
        table.insert(chunks, chunk)
      end
    end
    result[row_index] = chunks
  end

  return result
end

function M.compute_layout(columns, lines, cfg)
  local max_width = math.min(120, math.floor(columns * cfg.width))
  local cell_w = math.floor((max_width - 6) / 7)
  -- 7 セル + 6 本の区切り線に合わせて幅を丸め、右側に余白を残さない
  local win_width = 7 * cell_w + 6
  local win_height = math.min(40, math.floor(lines * cfg.height))

  return {
    win_width = win_width,
    win_height = win_height,
    cell_w = cell_w,
    row = math.floor((lines - win_height) / 2),
    col = math.floor((columns - win_width) / 2),
  }
end

function M.build_view(grid, events_by_date, cfg, today, selected_date, cell_w)
  local header_cells = {}
  for index, label in ipairs(calendar.weekday_labels(cfg.week_start)) do
    header_cells[index] = center(label, cell_w)
  end

  local weeks = {}
  for week_index, week in ipairs(grid.weeks) do
    local date_cells = {}
    local cells = {}
    for index, cell in ipairs(week) do
      local day_text = tostring(cell.day)
      date_cells[index] = string.rep(' ', cell_w - #day_text) .. day_text

      local col = (index - 1) * (cell_w + 3) + (cell_w - #day_text)
      local cell_start = (index - 1) * (cell_w + 3)
      cells[index] = {
        col = col,
        end_col = col + #day_text,
        cell_col = cell_start,
        cell_end_col = cell_start + cell_w,
        highlights = cell_highlights(cell, today, selected_date),
      }
    end

    weeks[week_index] = {
      date_line = table.concat(date_cells, '│'),
      cells = cells,
      event_rows = build_event_rows(week, events_by_date, cfg.max_events_per_cell, cell_w, selected_date),
    }
  end

  return {
    header = table.concat(header_cells, '│'),
    weeks = weeks,
  }
end

local function month_title(loading)
  local title = ' Google Calendar — ' .. calendar.format_month_title(state.year, state.month)
  if state.selected_date ~= nil then
    title = title .. ' — 選択: ' .. tostring(state.selected_date):sub(6)
  end
  if loading then
    title = title .. ' — 読み込み中...'
  end
  return title .. ' '
end

function M.render(win, view)
  local buf = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_create_namespace(namespace_name)

  local lines = { view.header }
  for _, week in ipairs(view.weeks) do
    table.insert(lines, week.date_line)
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_col = #view.header,
    hl_group = 'GoogleCalendarHeader',
  })

  for week_index, week in ipairs(view.weeks) do
    local line = week_index
    for _, cell in ipairs(week.cells) do
      for _, highlight in ipairs(cell.highlights) do
        local start_col = highlight.full_cell and cell.cell_col or cell.col
        local end_col = highlight.full_cell and cell.cell_end_col or cell.end_col
        vim.api.nvim_buf_set_extmark(buf, ns, line, start_col, {
          end_col = end_col,
          hl_group = highlight.hl,
          priority = highlight.priority,
        })
      end
    end

    if #week.event_rows > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
        virt_lines = week.event_rows,
      })
    end
  end

  vim.bo[buf].modifiable = false

  -- 日付行・予定行の実数に合わせて高さを詰め、下部に空白を残さない
  local content_height = 1
  for _, week in ipairs(view.weeks) do
    content_height = content_height + 1 + #week.event_rows
  end
  window.resize(win, vim.fn.strdisplaywidth(view.header), content_height)
end

local function render()
  local win = state.windows.month
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_win_set_config(win, { title = month_title(state.loading) })

  local cfg = config.get()
  local cell_w = math.floor((vim.api.nvim_win_get_width(win) - 6) / 7)
  if cell_w < 7 then
    cfg.notify('ウィンドウが狭すぎます', vim.log.levels.ERROR)
    window.close('month')
    return
  end

  local grid = calendar.month_grid(state.year, state.month, cfg.week_start)
  local view = M.build_view(grid, state.events_by_date, cfg, calendar.today(), state.selected_date, cell_w)
  M.render(win, view)
end

local function event_date(events_by_date, event_id)
  local dates = vim.tbl_keys(events_by_date)
  table.sort(dates)
  for _, date in ipairs(dates) do
    for _, item in ipairs(events_by_date[date]) do
      if item.id == event_id then
        return date
      end
    end
  end
end

local function fetch(initial, selected_event_id)
  local cfg = config.get()
  local start_date, end_date, time_min, time_max = calendar.fetch_range(state.year, state.month, cfg.week_start)
  request_seq = request_seq + 1
  local request_id = request_seq

  local gws = require('google-calendar.gws')
  gws.list_events({
    calendar_id = cfg.calendars[1],
    time_min = time_min,
    time_max = time_max,
  }, function(events, err)
    vim.schedule(function()
      if request_id ~= request_seq then
        return
      end

      if state.windows.month == nil or not vim.api.nvim_win_is_valid(state.windows.month) then
        state.loading = false
        return
      end

      if err ~= nil then
        state.loading = false
        notify.error(err)
        if initial then
          window.close('month')
        else
          render()
        end
        return
      end

      state.loading = false
      notify.reset()
      state.events_by_date = event.events_by_date(events or {}, start_date, calendar.add_days(end_date, -1))
      if selected_event_id ~= nil then
        local date = event_date(state.events_by_date, selected_event_id)
        if date ~= nil then
          state.selected_date = date
        end
      end
      render()
      require('google-calendar.ui.agenda').refresh(selected_event_id)
    end)
  end)
end

local function move_days(delta)
  if state.loading then
    return
  end

  local date = calendar.add_days(state.selected_date, delta)
  local year, month = calendar.date_parts(date)
  state.selected_date = date

  if year ~= state.year or month ~= state.month then
    state.year, state.month = year, month
    state.loading = true
    render()
    fetch(false)
  else
    render()
  end
end

local function shift_month(delta)
  if state.loading then
    return
  end

  local year, month = calendar.add_months(state.year, state.month, delta)
  local _, _, day = calendar.date_parts(state.selected_date)
  state.year, state.month = year, month
  state.selected_date = string.format('%04d-%02d-%02d', year, month, calendar.clamp_day(year, month, day))
  state.loading = true
  render()
  fetch(false)
end

local function go_today()
  if state.loading then
    return
  end

  local today = calendar.today()
  local year, month = calendar.date_parts(today)
  state.year, state.month = year, month
  state.selected_date = today
  state.loading = true
  render()
  fetch(false)
end

local function refresh(changed_event)
  if state.loading then
    return false
  end

  local win = state.windows.month
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local selected_event_id
  if type(changed_event) == 'table' then
    selected_event_id = changed_event.id
  end

  state.loading = true
  render()
  fetch(false, selected_event_id)
  return true
end

function M.refresh()
  return refresh(nil)
end

local function close()
  if state.loading then
    return
  end

  window.close('month')
end

local function open_agenda()
  if state.loading then
    return
  end

  require('google-calendar.ui.agenda').open({ on_changed = refresh })
end

local function open_create()
  if state.loading then
    return
  end

  require('google-calendar.ui.form').open_create({ on_created = M.refresh })
end

local function open_help()
  if state.loading then
    return
  end

  require('google-calendar.ui.help').open('month')
end

local key_actions = {
  prev_day = function()
    move_days(-1)
  end,
  next_day = function()
    move_days(1)
  end,
  prev_week = function()
    move_days(-7)
  end,
  next_week = function()
    move_days(7)
  end,
  prev_month = function()
    shift_month(-1)
  end,
  next_month = function()
    shift_month(1)
  end,
  today = go_today,
  agenda = open_agenda,
  create = open_create,
  refresh = M.refresh,
  help = open_help,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve('month', action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

function M.open()
  local cfg = config.get()
  local win = state.windows.month
  local initial = false

  if win == nil or not vim.api.nvim_win_is_valid(win) then
    local layout = M.compute_layout(vim.o.columns, vim.o.lines, cfg)
    if layout.cell_w < 7 then
      cfg.notify('ウィンドウが狭すぎます', vim.log.levels.ERROR)
      return false
    end

    -- 初回は日付行 6 週分だけの高さで開き、取得後に内容へ合わせて広げる
    local initial_height = math.min(7, layout.win_height)
    win = window.open('month', {
      width = layout.win_width,
      height = initial_height,
      row = math.floor((vim.o.lines - initial_height) / 2),
      col = layout.col,
      title = month_title(true),
      border = 'rounded',
    })
    initial = true
  else
    vim.api.nvim_set_current_win(win)
  end

  local buf = vim.api.nvim_win_get_buf(win)
  vim.bo[buf].modifiable = false
  vim.wo[win].winhl = 'FloatBorder:GoogleCalendarBorder,FloatTitle:GoogleCalendarHeader'
  set_keymaps(buf)

  state.loading = true
  render()
  fetch(initial)

  return true
end

return M
