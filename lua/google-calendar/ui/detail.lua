local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

-- 更新フォーム・削除確認・Meet URL コピーの実処理は別機能が持つため、キー処理からは opener 経由で呼ぶ
M.openers = {
  edit = function(item, opts)
    require('google-calendar.ui.form').open_edit(item, opts)
  end,
  delete = function(item, opts)
    require('google-calendar.ui.confirm').open(item, {
      on_finished = function()
        window.close('detail')
        if opts ~= nil and opts.on_changed ~= nil then
          opts.on_changed()
        end
      end,
    })
  end,
  copy_meet = function(item)
    M.copy_meet(item)
  end,
  help = function(screen)
    require('google-calendar.ui.help').open(screen)
  end,
}

local current_item = nil
local guests_expanded = true
local current_opts = {}

local GUESTS_COLLAPSE_THRESHOLD = 5
local WEEKDAYS = { '日', '月', '火', '水', '木', '金', '土' }
local ICON_CALENDAR = '▣'
local ICON_LOCATION = '⌖'
local ICON_GUESTS = '☷'
local ICON_NOTES = '☰'
local ICON_MEET = '↗'

local function date_label(date)
  local year, month, day = calendar.date_parts(date)
  if year == nil then
    return date
  end
  year, month, day = assert(year), assert(month), assert(day)
  local weekday = tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 })))
  return string.format('%d月%d日 (%s曜日)', month, day, WEEKDAYS[weekday + 1])
end

local function format_when(item)
  local date = event.start_date(item)
  if date == nil then
    return nil
  end

  local label = date_label(date)
  if event.is_all_day(item) then
    return label
  end

  local start_time = event.start_time(item)
  if start_time == nil then
    return label
  end
  local end_time = event.end_time(item)
  if end_time == nil then
    return label .. '・' .. start_time
  end
  return label .. '・' .. start_time .. '〜' .. end_time
end

local function wrap_text(text, width)
  local lines = {}
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
  for _, paragraph in ipairs(vim.split(text, '\n', { plain = true })) do
    if paragraph == '' then
      table.insert(lines, '')
    else
      local current = ''
      for index = 0, vim.fn.strchars(paragraph) - 1 do
        local char = vim.fn.strcharpart(paragraph, index, 1)
        if vim.fn.strdisplaywidth(current .. char) > width then
          table.insert(lines, current)
          current = char
        else
          current = current .. char
        end
      end
      if current ~= '' then
        table.insert(lines, current)
      end
    end
  end
  return lines
end

local function attendee_status(attendee)
  local status = attendee.responseStatus
  if status == 'accepted' then
    return '✓', 'GoogleCalendarDetailAccepted'
  end
  if status == 'declined' then
    return '✕', 'GoogleCalendarDetailDeclined'
  end
  if status == 'tentative' then
    return '?', 'GoogleCalendarDetailPending'
  end
  return '○', 'GoogleCalendarDetailPending'
end

local function is_organizer(attendee, organizer)
  if attendee.organizer == true then
    return true
  end
  return type(organizer) == 'table' and organizer.email ~= nil and attendee.email == organizer.email
end

local function build_lines(item, width)
  local lines = {}
  local highlights = {}

  local function add(text, spans)
    table.insert(lines, text)
    local line = #lines - 1
    for _, span in ipairs(spans or {}) do
      table.insert(highlights, { line = line, start_col = span[1], end_col = span[2], group = span[3] })
    end
  end

  local function add_icon_line(icon, text, text_group)
    local line = icon .. ' ' .. text
    local spans = { { 0, #icon, 'GoogleCalendarDetailIcon' } }
    if text ~= '' and text_group ~= nil then
      table.insert(spans, { #icon + 1, #line, text_group })
    end
    add(line, spans)
  end

  local function add_muted(text)
    add(text, { { 0, #text, 'GoogleCalendarDetailMuted' } })
  end

  local title = event.sanitize(item.summary or '')
  if title ~= '' then
    add_icon_line(ICON_CALENDAR, event.truncate(title, math.max(0, width - 2)), 'GoogleCalendarDetailTitle')
  end

  local when = format_when(item)
  if when ~= nil then
    add_muted('  ' .. event.truncate(when, math.max(0, width - 2)))
  end

  local meet = event.meet_url(item)
  if meet ~= nil then
    local text = ICON_MEET .. ' ' .. event.truncate(meet, math.max(0, width - 2))
    add(text, {
      { 0, #ICON_MEET, 'GoogleCalendarDetailIcon' },
      { #ICON_MEET + 1, #text, 'GoogleCalendarDetailMeet' },
    })
  end

  local location = event.sanitize(item.location or '')
  if location ~= '' then
    add('')
    add_icon_line(ICON_LOCATION, event.truncate(location, math.max(0, width - 2)))
  end

  local attendees = item.attendees
  if type(attendees) == 'table' and #attendees > 0 then
    add('')
    local fold_marker = guests_expanded and '▾' or '▸'
    add_icon_line(ICON_GUESTS, string.format('%d人のゲスト %s', #attendees, fold_marker))

    local accepted, pending, tentative, declined = 0, 0, 0, 0
    for _, attendee in ipairs(attendees) do
      local status = attendee.responseStatus
      if status == 'accepted' then
        accepted = accepted + 1
      elseif status == 'declined' then
        declined = declined + 1
      elseif status == 'tentative' then
        tentative = tentative + 1
      else
        pending = pending + 1
      end
    end
    if accepted > 0 then
      add_muted(string.format('  参加: %d人', accepted))
    end
    if pending > 0 then
      add_muted(string.format('  返答待ち: %d人', pending))
    end
    if tentative > 0 then
      add_muted(string.format('  仮: %d人', tentative))
    end
    if declined > 0 then
      add_muted(string.format('  辞退: %d人', declined))
    end

    local toggle_key = config.resolve('detail', 'toggle_guests')
    if toggle_key ~= nil then
      add_muted(string.format('  %s でゲストを%s', toggle_key, guests_expanded and '折り畳む' or '表示'))
    end

    if guests_expanded then
      for _, attendee in ipairs(attendees) do
        local status_icon, status_group = attendee_status(attendee)
        local email = attendee.email or ''
        local line = '  ' .. status_icon .. ' ' .. event.truncate(email, math.max(0, width - 4))
        add(line, { { 2, 2 + #status_icon, status_group } })

        local display_name = event.sanitize(attendee.displayName or '')
        if display_name ~= '' and display_name ~= attendee.email then
          add_muted('    ' .. event.truncate(display_name, math.max(0, width - 4)))
        end
        if is_organizer(attendee, item.organizer) then
          add_muted('    主催者')
        end
      end
    end
  end

  local description = item.description
  if description ~= nil and description ~= '' then
    add('')
    local description_lines = wrap_text(description, math.max(1, width - 2))
    for index, text in ipairs(description_lines) do
      if index == 1 then
        add_icon_line(ICON_NOTES, text)
      else
        add('  ' .. text)
      end
    end
  end

  local calendar_label
  if type(item.organizer) == 'table' and item.organizer.email ~= nil then
    calendar_label = item.organizer.email
  elseif item.calendar_id ~= nil and item.calendar_id ~= '' then
    calendar_label = item.calendar_id
  end
  if calendar_label ~= nil then
    add('')
    add_icon_line(ICON_CALENDAR, event.truncate(calendar_label, math.max(0, width - 2)), 'GoogleCalendarDetailMuted')
  end

  return lines, highlights
end

local function render(win, item)
  local cfg = config.get().detail
  local width, height = window.target_size(cfg.width, cfg.height)
  local max_width = math.max(1, width - 2)

  local buf = vim.api.nvim_win_get_buf(win)
  local lines, highlights = build_lines(item, max_width)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace('google-calendar-detail')
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, ns, highlight.line, highlight.start_col, {
      end_col = highlight.end_col,
      hl_group = highlight.group,
    })
  end

  window.resize(win, width, height)

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

local function toggle_guests()
  if current_item == nil then
    return
  end
  local attendees = current_item.attendees
  if type(attendees) ~= 'table' or #attendees == 0 then
    return
  end

  guests_expanded = not guests_expanded
  local win = state.windows.detail
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    render(win, current_item)
  end
end

local function notify(message, level)
  config.get().notify(event.truncate(message, vim.o.columns), level)
end

local function notify_copy_failure(url)
  notify('クリップボードにコピーできませんでした: ' .. url, vim.log.levels.ERROR)
end

function M.copy_meet(item)
  local url = event.meet_url(item)
  if url == nil then
    notify('この予定には Meet URL がありません', vim.log.levels.WARN)
    return
  end

  if vim.fn.has('clipboard') == 0 then
    notify_copy_failure(url)
    return
  end

  if not pcall(config.get().clipboard, url) then
    notify_copy_failure(url)
    return
  end

  notify('Meet URL をコピーしました: ' .. url, vim.log.levels.INFO)
end

local function open_edit()
  if current_item ~= nil then
    M.openers.edit(current_item, current_opts)
  end
end

local function open_delete()
  if current_item ~= nil then
    M.openers.delete(current_item, current_opts)
  end
end

local function copy_meet()
  if current_item ~= nil then
    M.openers.copy_meet(current_item)
  end
end

local function open_help()
  M.openers.help('detail')
end

local function close()
  window.close('detail')
end

local key_actions = {
  edit = open_edit,
  delete = open_delete,
  copy_meet = copy_meet,
  toggle_guests = toggle_guests,
  help = open_help,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve('detail', action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

function M.open(item, opts)
  local cfg = config.get().detail
  local width, height = window.target_size(cfg.width, cfg.height)
  local row = math.max(0, math.floor((vim.o.lines - (height + 2)) / 2))
  local col = math.max(0, math.floor((vim.o.columns - (width + 2)) / 2))
  local opts_win = { relative = 'editor', width = width, height = height, row = row, col = col }

  local win = state.windows.detail
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, opts_win)
  else
    win = window.open('detail', opts_win)
  end

  current_item = item
  current_opts = opts or {}
  local attendees = item.attendees
  guests_expanded = type(attendees) ~= 'table' or #attendees <= GUESTS_COLLAPSE_THRESHOLD
  render(win, item)
  set_keymaps(vim.api.nvim_win_get_buf(win))
  vim.api.nvim_set_current_win(win)

  return win
end

return M
