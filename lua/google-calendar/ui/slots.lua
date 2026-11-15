local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local notify = require('google-calendar.notify')
local slots = require('google-calendar.slots')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')
local calendar_color = require('google-calendar.ui.calendar_color')

local M = {}

local LIST = 'slots'
local TIMELINE = 'slots_timeline'
local LIST_WIDTH = 30
local LABEL_WIDTH = 7
local ROWS_PER_DAY = 48
local MINUTES_PER_ROW = 30
local CONTEXT_ROWS = 4
local FOOTER_ITEMS = {
  { action = 'copy', label = 'コピー' },
  { action = 'close', label = '戻る' },
}

function M.fetch_events(calendar_ids, time_min, time_max, callback)
  local gws = require('google-calendar.gws')
  local collected = {}
  local remaining = #calendar_ids
  local first_error = nil

  for _, calendar_id in ipairs(calendar_ids) do
    gws.list_events({ calendar_id = calendar_id, time_min = time_min, time_max = time_max }, function(events, err)
      vim.schedule(function()
        if err ~= nil then
          first_error = first_error or err
        else
          vim.list_extend(collected, events or {})
        end
        remaining = remaining - 1
        if remaining == 0 then
          if first_error ~= nil then
            callback(nil, first_error)
          else
            callback(collected, nil)
          end
        end
      end)
    end)
  end
end

M.deps = {
  fetch_events = function(...)
    M.fetch_events(...)
  end,
  now = function()
    return tostring(os.date('%Y-%m-%d %H:%M'))
  end,
  -- nil のときはローカルのオフセットで表示する
  local_offset = nil,
}

M.openers = {
  help = function(screen)
    require('google-calendar.ui.help').open(screen)
  end,
}

local request_seq = 0
local current = { events = {}, found = nil, selected = 1 }

local function clock_minutes(time)
  local hour, minute = time:match('^(%d%d):(%d%d)$')
  return tonumber(hour) * 60 + tonumber(minute)
end

local function pad(text, width)
  return text .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(text)))
end

local function time_label(item, local_offset)
  return (event.start_time(item, local_offset) or '') .. '~' .. (event.end_time(item, local_offset) or '')
end

local function all_day_on(item, date)
  if not event.is_all_day(item) or item.status == 'cancelled' then
    return false
  end
  local start_date = item.start.date
  local end_date = (type(item['end']) == 'table' and item['end'].date) or calendar.add_days(start_date, 1)
  return start_date <= date and date < end_date
end

local function busy_blocks(date, events, local_offset)
  local day_start = slots.day_start_minutes(date)
  local blocks = {}
  for _, item in ipairs(events) do
    if slots.is_busy(item) then
      local start, finish = slots.event_minutes(item, local_offset)
      if start ~= nil and finish ~= nil then
        start = math.max(start, day_start)
        finish = math.min(finish, day_start + ROWS_PER_DAY * MINUTES_PER_ROW)
        if finish > start then
          table.insert(blocks, {
            item = item,
            first = math.floor((start - day_start) / MINUTES_PER_ROW),
            last = math.ceil((finish - day_start) / MINUTES_PER_ROW) - 1,
          })
        end
      end
    end
  end
  table.sort(blocks, function(a, b)
    if a.first ~= b.first then
      return a.first < b.first
    end
    return a.last > b.last
  end)
  return blocks
end

-- 日全体の最大の重なり数で幅を割ると、重ならない予定まで細くなるため、重なるまとまりごとに列数を決める
local function assign_lanes(blocks)
  local cluster = {}
  local lanes = {}
  local cluster_last = -1

  local function close_cluster()
    for _, block in ipairs(cluster) do
      block.lane_count = #lanes
    end
    cluster = {}
    lanes = {}
  end

  for _, block in ipairs(blocks) do
    if block.first > cluster_last then
      close_cluster()
    end
    for index, last in ipairs(lanes) do
      if last < block.first then
        lanes[index] = block.last
        block.lane = index
        break
      end
    end
    if block.lane == nil then
      table.insert(lanes, block.last)
      block.lane = #lanes
    end
    cluster_last = math.max(cluster_last, block.last)
    table.insert(cluster, block)
  end
  close_cluster()
end

local function block_text(block, row, local_offset)
  local title = event.display_title(block.item)
  local time = time_label(block.item, local_offset)
  if row == block.first then
    if block.first == block.last then
      return title .. ' ' .. time
    end
    return title
  end
  if row == block.first + 1 then
    return time
  end
  return ''
end

-- タイムラインの先頭行に置くと、候補までスクロールしたときに画面外へ出るため、固定表示の winbar に置く
local function all_day_winbar(date, events)
  local chips = {}
  for _, item in ipairs(events) do
    if all_day_on(item, date) then
      local title = event.display_title(item):gsub('%%', '%%%%')
      table.insert(chips, '%#' .. calendar_color.bar_group(item.calendar_id) .. '# ' .. title .. ' %*')
    end
  end
  if #chips == 0 then
    return ' %#GoogleCalendarDetailMuted#終日予定なし%*'
  end
  return ' 終日 ' .. table.concat(chips, ' ')
end

-- 列の間に 1 列の隙間を置き、最後の列で端数を吸収して、右端を候補のブロックと揃える
local function lane_widths(content_width, lane_count)
  local available = math.max(0, content_width - (lane_count - 1))
  local base = math.floor(available / lane_count)
  local widths = {}
  for lane = 1, lane_count do
    widths[lane] = lane == lane_count and available - base * (lane_count - 1) or base
  end
  return widths
end

---@return { lines: string[], highlights: table[], candidate_line: integer|nil, winbar: string }
function M.build_timeline(date, events, candidate, width, local_offset)
  local content_width = math.max(0, width - LABEL_WIDTH)
  local lines = {}
  local highlights = {}

  local blocks = busy_blocks(date, events, local_offset)
  assign_lanes(blocks)
  local by_row = {}
  for _, block in ipairs(blocks) do
    for row = block.first, block.last do
      by_row[row] = by_row[row] or {}
      by_row[row][block.lane] = block
    end
  end

  local candidate_first, candidate_last
  if candidate ~= nil then
    candidate_first = math.floor(clock_minutes(candidate.start) / MINUTES_PER_ROW)
    candidate_last = math.ceil(clock_minutes(candidate.finish) / MINUTES_PER_ROW) - 1
  end

  for row = 0, ROWS_PER_DAY - 1 do
    local label = row % 2 == 0 and string.format('%02d:00 │', row / 2) or '      │'
    local line = label
    local line_index = row

    local function add_cell(text, cell_width, group)
      local cell = pad(event.truncate(text, cell_width), cell_width)
      table.insert(highlights, { line = line_index, start_col = #line, end_col = #line + #cell, group = group })
      line = line .. cell
    end

    local lanes = by_row[row]
    if lanes ~= nil then
      local any = next(lanes)
      local lane_count = lanes[any].lane_count
      local widths = lane_widths(content_width, lane_count)
      for lane = 1, lane_count do
        if lane > 1 then
          line = line .. ' '
        end
        local block = lanes[lane]
        if block ~= nil then
          local start_col = #line
          add_cell(block_text(block, row, local_offset), widths[lane], calendar_color.bar_group(block.item.calendar_id))
          if row == block.last then
            table.insert(highlights, {
              line = line_index,
              start_col = start_col,
              end_col = #line,
              group = 'GoogleCalendarSlotEventEnd',
            })
          end
        else
          line = line .. string.rep(' ', widths[lane])
        end
      end
    elseif candidate_first ~= nil and row >= candidate_first and row <= candidate_last then
      local text = row == candidate_first and ('候補 ' .. candidate.start .. '~' .. candidate.finish) or ''
      add_cell(text, content_width, 'GoogleCalendarSlotCandidate')
    end

    table.insert(lines, line)
  end

  return {
    lines = lines,
    highlights = highlights,
    candidate_line = candidate_first and (candidate_first + 1) or nil,
    winbar = all_day_winbar(date, events),
  }
end

local function footer()
  local parts = {}
  for _, item in ipairs(FOOTER_ITEMS) do
    local key = config.resolve(LIST, item.action)
    if key ~= nil then
      table.insert(parts, key .. ':' .. item.label)
    end
  end
  return ' ' .. table.concat(parts, ' ') .. ' '
end

local function layouts()
  local cfg = config.get().slots
  local width, height = window.target_size(cfg.width, cfg.height)
  local list_width = math.max(1, math.min(LIST_WIDTH, width - LABEL_WIDTH - 4))
  local timeline_width = math.max(1, width - list_width - 2)
  local row = math.max(0, math.floor((vim.o.lines - (height + 2)) / 2))
  local col = math.max(0, math.floor((vim.o.columns - (width + 2)) / 2))
  return {
    relative = 'editor',
    width = list_width,
    height = height,
    row = row,
    col = col,
    title = ' 空き枠 ',
    footer = footer(),
  }, {
    relative = 'editor',
    width = timeline_width,
    height = height,
    row = row,
    col = col + list_width + 2,
    title = ' タイムライン ',
  }
end

local function valid(name)
  local win = state.windows[name]
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function set_lines(win, lines)
  local buf = vim.api.nvim_win_get_buf(win)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  return buf
end

local function render_timeline()
  if not valid(TIMELINE) then
    return
  end
  local win = state.windows[TIMELINE]
  local candidate = current.found and current.found[current.selected]
  if candidate == nil then
    vim.wo[win].winbar = ''
    set_lines(win, {})
    vim.api.nvim_win_set_config(win, { title = ' タイムライン ' })
    return
  end

  local width = vim.api.nvim_win_get_width(win)
  local timeline = M.build_timeline(candidate.date, current.events, candidate, width, M.deps.local_offset)
  vim.wo[win].winbar = timeline.winbar
  -- winheight は winbar の行を除いた本文の行数を返す
  local text_height = vim.fn.winheight(win)
  local lines = timeline.lines
  while #lines < text_height do
    table.insert(lines, '      │')
  end
  local buf = set_lines(win, lines)
  local ns = vim.api.nvim_create_namespace('google-calendar-slots-timeline')
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, highlight in ipairs(timeline.highlights) do
    vim.api.nvim_buf_set_extmark(buf, ns, highlight.line, highlight.start_col, {
      end_col = highlight.end_col,
      hl_group = highlight.group,
    })
  end
  vim.api.nvim_win_set_config(win, { title = ' ' .. slots.date_label(candidate.date) .. ' ' })
  local last_topline = #lines - text_height + 1
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({
      lnum = timeline.candidate_line,
      col = 0,
      topline = math.max(1, math.min(timeline.candidate_line - CONTEXT_ROWS, last_topline)),
    })
  end)
end

local function render_list()
  if not valid(LIST) then
    return
  end
  local lines
  if current.found == nil then
    lines = { '読み込み中...' }
  elseif #current.found == 0 then
    lines = { '空き枠なし' }
  else
    lines = {}
    for index, line in ipairs(slots.format(current.found)) do
      table.insert(lines, (index == current.selected and '>' or ' ') .. line)
    end
  end
  local win = state.windows[LIST]
  set_lines(win, lines)
  vim.api.nvim_win_set_cursor(win, { math.min(current.selected, #lines), 0 })
end

local function close()
  request_seq = request_seq + 1
  window.close(TIMELINE)
  window.close(LIST)
end

local function move(delta)
  if current.found == nil or #current.found == 0 then
    return
  end
  current.selected = math.min(#current.found, math.max(1, current.selected + delta))
  render_list()
  render_timeline()
end

local function copy()
  local cfg = config.get()
  if current.found == nil or #current.found == 0 then
    cfg.notify('No slots to copy', vim.log.levels.WARN)
    return
  end

  local text = table.concat(slots.format(current.found), '\n')
  if vim.fn.has('clipboard') == 0 or not pcall(cfg.clipboard, text) then
    cfg.notify('Could not copy to clipboard', vim.log.levels.ERROR)
    return
  end
  cfg.notify(string.format('Copied %d slots', #current.found), vim.log.levels.INFO)
end

local key_actions = {
  next = function()
    move(1)
  end,
  prev = function()
    move(-1)
  end,
  copy = copy,
  help = function()
    M.openers.help(LIST)
  end,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve(LIST, action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

---@param conditions { time_range: { start: string, finish: string }, duration: integer, dates: string[] }
function M.open(conditions)
  if valid(LIST) or valid(TIMELINE) then
    close()
  end

  local list_opts, timeline_opts = layouts()
  -- window.open は開いたウィンドウへフォーカスを移すため、フォーカスを置きたい候補一覧を後に開く
  local timeline_win = window.open(TIMELINE, timeline_opts)
  local list_win = window.open(LIST, list_opts)
  for _, win in ipairs({ timeline_win, list_win }) do
    vim.wo[win].winhl = 'FloatBorder:GoogleCalendarBorder,FloatTitle:GoogleCalendarHeader'
  end
  vim.wo[list_win].cursorline = true
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(list_win),
    once = true,
    callback = function()
      vim.schedule(function()
        -- 再検索で開き直した後に走ると、名前だけで閉じると新しいタイムラインまで閉じるため、対で開いたものに限る
        if state.windows[TIMELINE] == timeline_win then
          window.close(TIMELINE)
        end
      end)
    end,
  })
  set_keymaps(vim.api.nvim_win_get_buf(list_win))

  current = { events = {}, found = nil, selected = 1 }
  render_list()
  render_timeline()

  request_seq = request_seq + 1
  local request_id = request_seq
  local dates = conditions.dates
  local calendar_ids = config.get().calendars
  if type(calendar_ids) ~= 'table' or #calendar_ids == 0 then
    calendar_ids = { 'primary' }
  end

  M.deps.fetch_events(
    calendar_ids,
    calendar.rfc3339(calendar.add_days(dates[1], -1)),
    calendar.rfc3339(calendar.add_days(dates[#dates], 2)),
    function(events, err)
      if request_id ~= request_seq or not valid(LIST) then
        return
      end
      if err ~= nil then
        notify.error(err)
        close()
        return
      end

      current.events = events or {}
      current.found = slots.find(current.events, {
        dates = dates,
        time_range = conditions.time_range,
        duration = conditions.duration,
        buffer = config.get().slots.buffer,
        now = M.deps.now(),
        local_offset = M.deps.local_offset,
      })
      render_list()
      render_timeline()
    end
  )

  return list_win
end

return M
