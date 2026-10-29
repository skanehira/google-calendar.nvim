local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local notify_adapter = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local namespace_name = 'google-calendar-form'
local TITLE_LIMIT = 1024
local LOCATION_LIMIT = 1024
local DESCRIPTION_LIMIT = 8192
local FORM_WIDTH_MAX = 80
local FORM_HEIGHT = 11

local WEEKDAYS = { '日', '月', '火', '水', '木', '金', '土' }
local ICON_CALENDAR = '▣'
local ICON_CLOCK = '◷'
local ICON_GUESTS = '◉'
local ICON_MEET = '▶'
local ICON_LOCATION = '⌖'
local ICON_NOTES = '☰'

local ROWS = {
  { key = 'summary', line = 1, kind = 'summary' },
  { key = 'datetime', line = 4, kind = 'datetime' },
  { key = 'guests', line = 5, kind = 'guests' },
  { key = 'meet', line = 6, kind = 'toggle' },
  { key = 'location', line = 7, kind = 'text' },
  { key = 'description', line = 8, kind = 'text' },
  { key = 'calendar', line = 9, kind = 'calendar' },
}

---@class GoogleCalendarForm
---@field active boolean
---@field mode string
---@field event_id string|nil
---@field initial_values table|nil
---@field on_changed function|nil
---@field win integer
---@field buf integer
---@field width integer
---@field selected integer
---@field saving boolean
---@field error string|nil
---@field error_field string|nil
---@field on_created function|nil
---@field values table

---@type GoogleCalendarForm
local form = {
  active = false,
  mode = 'create',
  event_id = nil,
  initial_values = nil,
  on_changed = nil,
  win = 0,
  buf = 0,
  width = 60,
  selected = 1,
  saving = false,
  error = nil,
  error_field = nil,
  on_created = nil,
  values = {},
}

local editor = {
  win = 0,
  buf = 0,
  kind = nil,
  selected = 1,
}

local function notify(message, level)
  config.get().notify(message, level)
end

local function date_label(date)
  local year, month, day = calendar.date_parts(date)
  if year == nil then
    return date
  end
  year, month, day = assert(year), assert(month), assert(day)
  local weekday = tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 })))
  return string.format('%d月%d日 (%s曜日)', month, day, WEEKDAYS[weekday + 1])
end

local function format_when(values)
  local start_date = values.start:sub(1, 10)
  if values.all_day then
    local end_date = values['end']
    if calendar.parse_date(end_date) ~= nil then
      end_date = calendar.add_days(end_date, -1)
    end
    return date_label(start_date) .. ' – ' .. date_label(end_date)
  end

  local start_time = values.start:sub(12, 16)
  local end_time = values['end']:sub(12, 16)
  return date_label(start_date) .. '・' .. start_time .. '〜' .. end_time
end

local function row_line(key)
  for _, row in ipairs(ROWS) do
    if row.key == key then
      return row.line
    end
  end
  return nil
end

local function error_line()
  if form.error_field == nil then
    return nil
  end
  return row_line(form.error_field)
end

local function footer_text()
  if form.saving then
    return 'Saving...'
  end
  if form.error ~= nil then
    return 'Error: ' .. form.error
  end

  local save_key = config.resolve('form', 'save')
  local next_key = config.resolve('form', 'next_field')
  local prev_key = config.resolve('form', 'prev_field')
  local parts = { 'その他のオプション', '[保存]' }
  if save_key ~= nil then
    table.insert(parts, save_key .. ':保存')
  end
  if next_key ~= nil or prev_key ~= nil then
    local keys = {}
    if next_key ~= nil then
      table.insert(keys, next_key)
    end
    if prev_key ~= nil then
      table.insert(keys, prev_key)
    end
    table.insert(parts, table.concat(keys, '/') .. ':移動')
  end
  table.insert(parts, '?:ヘルプ')
  return table.concat(parts, '  ')
end

local function icon_prefix(icon)
  local pad = math.max(0, 2 - vim.fn.strdisplaywidth(icon))
  return icon .. string.rep(' ', pad)
end

local function add_icon_line(add, icon, text, text_group)
  local prefix = icon_prefix(icon)
  local line = prefix .. text
  local spans = { { 0, #icon, 'GoogleCalendarFormIcon' } }
  if text ~= '' and text_group ~= nil then
    table.insert(spans, { #prefix, #line, text_group })
  end
  add(line, spans)
end

local function render()
  local width = math.max(1, form.width)
  local lines = {}
  local highlights = {}

  local function add(text, spans)
    table.insert(lines, text)
    local line = #lines - 1
    for _, span in ipairs(spans or {}) do
      table.insert(highlights, { line = line, start_col = span[1], end_col = span[2], group = span[3] })
    end
  end

  local title = vim.trim(form.values.summary or '')
  if title == '' then
    add('タイトルと日時を追加', { { 0, #'タイトルと日時を追加', 'GoogleCalendarFormMuted' } })
  else
    add(event.truncate(title, width), { { 0, #event.truncate(title, width), 'GoogleCalendarFormTitle' } })
  end

  add(string.rep('─', width), { { 0, width, 'GoogleCalendarFormSeparator' } })
  add('')

  local when = format_when(form.values)
  local button = form.values.all_day and '[時間を追加]' or '[終日]'
  local date_text = icon_prefix(ICON_CLOCK) .. event.truncate(when, math.max(1, width - #button - 3))
  add(date_text .. '  ' .. button, {
    { 0, #ICON_CLOCK, 'GoogleCalendarFormIcon' },
    { #date_text + 2, #date_text + 2 + #button, 'GoogleCalendarFormButton' },
  })

  local attendees = form.values.attendees or {}
  local guest_text
  if #attendees > 0 then
    guest_text = string.format('%d人のゲスト', #attendees)
  else
    guest_text = 'ゲストを追加'
  end
  add_icon_line(add, ICON_GUESTS, event.truncate(guest_text, math.max(1, width - 2)))

  local meet_text = 'Google Meet のビデオ会議を追加'
  local meet_state = form.values.meet and 'on' or 'off'
  if form.mode == 'edit' then
    meet_state = '固定'
  end
  add_icon_line(add, ICON_MEET, event.truncate(meet_text, math.max(1, width - 12)) .. '  [' .. meet_state .. ']')

  local location = vim.trim(form.values.location or '')
  if location == '' then
    add_icon_line(add, ICON_LOCATION, '場所を追加', 'GoogleCalendarFormMuted')
  else
    add_icon_line(add, ICON_LOCATION, event.truncate(location, math.max(1, width - 2)))
  end

  local description = vim.trim(form.values.description or '')
  if description == '' then
    add_icon_line(
      add,
      ICON_NOTES,
      '説明または Google ドライブの添付ファイルを追加',
      'GoogleCalendarFormMuted'
    )
  else
    local first_line = vim.split(description, '\n', { plain = true })[1] or ''
    add_icon_line(add, ICON_NOTES, event.truncate(first_line, math.max(1, width - 2)))
  end

  local calendar_id = config.get().calendars[1] or 'primary'
  add_icon_line(add, ICON_CALENDAR, calendar_id, 'GoogleCalendarFormMuted')

  add('')
  local footer = event.truncate(footer_text(), width)
  local footer_spans = { { 0, #footer, 'GoogleCalendarFormMuted' } }
  local save_start = footer:find('[保存]', 1, true)
  if save_start ~= nil then
    table.insert(footer_spans, { save_start - 1, save_start - 1 + #'[保存]', 'GoogleCalendarFormButton' })
  end
  add(footer, footer_spans)

  local error_row = error_line()
  if error_row ~= nil then
    table.insert(
      highlights,
      { line = error_row - 1, start_col = 0, end_col = #(lines[error_row] or ''), group = 'GoogleCalendarError' }
    )
  end

  vim.bo[form.buf].modifiable = true
  vim.api.nvim_buf_set_lines(form.buf, 0, -1, false, lines)
  vim.bo[form.buf].modifiable = false

  local ns = vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_buf_clear_namespace(form.buf, ns, 0, -1)
  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(form.buf, ns, highlight.line, highlight.start_col, {
      end_col = highlight.end_col,
      hl_group = highlight.group,
    })
  end

  if vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_win_set_cursor(form.win, { ROWS[form.selected].line, 0 })
  end
end

local function selected_row()
  return ROWS[form.selected]
end

local function sync_selection()
  if not vim.api.nvim_win_is_valid(form.win) then
    return
  end
  local line = vim.api.nvim_win_get_cursor(form.win)[1]
  for index, row in ipairs(ROWS) do
    if row.line == line then
      form.selected = index
      return
    end
  end
end

local function move_field(delta)
  if not form.active or form.saving then
    return
  end
  form.selected = ((form.selected - 1 + delta) % #ROWS) + 1
  vim.api.nvim_win_set_cursor(form.win, { ROWS[form.selected].line, 0 })
end

local function close_editor()
  if editor.kind ~= nil then
    window.close('form_editor')
    editor.win = 0
    editor.buf = 0
    editor.kind = nil
    editor.selected = 1
  end
  if form.win ~= 0 and vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_set_current_win(form.win)
  end
end

local function editor_width()
  return math.max(1, math.min(60, vim.o.columns - 8))
end

local function set_write_command(buf, handler)
  vim.bo[buf].buftype = 'acwrite'
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = handler,
  })
end

local function set_editor_lines(lines)
  vim.bo[editor.buf].modifiable = true
  vim.api.nvim_buf_set_lines(editor.buf, 0, -1, false, lines)
  vim.bo[editor.buf].modifiable = true
end

local function save_editor()
  if editor.kind == nil or not vim.api.nvim_win_is_valid(editor.win) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(editor.buf, 0, -1, false)
  if editor.kind == 'summary' then
    form.values.summary = vim.trim(lines[1] or '')
  elseif editor.kind == 'location' then
    form.values.location = vim.trim(lines[1] or '')
  elseif editor.kind == 'description' then
    form.values.description = vim.trim(table.concat(lines, '\n'))
  elseif editor.kind == 'datetime' then
    local start_value = lines[1] and lines[1]:match('^開始:%s*(.*)$') or ''
    local end_value = lines[2] and lines[2]:match('^終了:%s*(.*)$') or ''
    local all_day = lines[3] and lines[3]:match('^終日:%s*(%a+)$') == 'on'
    form.values.start = vim.trim(start_value)
    form.values['end'] = vim.trim(end_value)
    form.values.all_day = all_day
  elseif editor.kind == 'guests' then
    local emails = {}
    local seen = {}
    for _, line in ipairs(lines) do
      local email = vim.trim(line)
      if email ~= '' then
        if email:match('^[^@%s]+@[^@%s]+$') == nil then
          notify('Invalid guest email address: ' .. email, vim.log.levels.WARN)
          return
        end
        if not seen[email] then
          seen[email] = true
          table.insert(emails, email)
        end
      end
    end
    form.values.attendees = emails
  end

  close_editor()
  render()
end

local function editor_toggle_all_day()
  local lines = vim.api.nvim_buf_get_lines(editor.buf, 0, -1, false)
  local all_day = lines[3] and lines[3]:match('^終日:%s*(%a+)$') == 'on'
  local start_value = lines[1] and lines[1]:match('^開始:%s*(.*)$') or ''
  local end_value = lines[2] and lines[2]:match('^終了:%s*(.*)$') or ''
  local start_date = start_value:sub(1, 10)
  if not all_day then
    lines[3] = '終日: on'
    lines[1] = '開始: ' .. start_date
    if calendar.parse_date(start_date) ~= nil then
      lines[2] = '終了: ' .. calendar.add_days(start_date, 1)
    else
      lines[2] = '終了: ' .. end_value:sub(1, 10)
    end
  else
    lines[3] = '終日: off'
    lines[1] = '開始: ' .. start_date .. ' 09:00'
    lines[2] = '終了: ' .. start_date .. ' 10:00'
  end
  set_editor_lines(lines)
  vim.api.nvim_win_set_cursor(editor.win, { 3, 0 })
end

local function editor_edit_selected()
  local line = vim.api.nvim_win_get_cursor(editor.win)[1]
  editor.selected = line
  if editor.kind == 'datetime' and line == 3 then
    editor_toggle_all_day()
    return
  end
  vim.cmd('startinsert!')
end

local function set_editor_keymaps(buf)
  local function map(mode, action, handler)
    local key = config.resolve('form', action)
    if key ~= nil then
      vim.keymap.set(mode, key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end

  if editor.kind ~= 'datetime' then
    map('n', 'edit', save_editor)
  end

  if editor.kind == 'datetime' then
    map({ 'n', 'i' }, 'next_field', function()
      vim.cmd('stopinsert')
      editor.selected = (editor.selected % 3) + 1
      vim.api.nvim_win_set_cursor(editor.win, { editor.selected, 0 })
    end)
    map({ 'n', 'i' }, 'prev_field', function()
      vim.cmd('stopinsert')
      editor.selected = ((editor.selected - 2) % 3) + 1
      vim.api.nvim_win_set_cursor(editor.win, { editor.selected, 0 })
    end)
    map('n', 'edit', editor_edit_selected)
    map('n', 'toggle', editor_toggle_all_day)
  end

  local save_key = config.resolve('form', 'save')
  if save_key ~= nil and save_key ~= ':w' then
    vim.keymap.set('n', save_key, save_editor, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set('i', save_key, function()
      vim.cmd('stopinsert')
      save_editor()
    end, { buffer = buf, nowait = true, silent = true })
  end
  map('n', 'cancel', close_editor)
  map('i', 'cancel', function()
    vim.cmd('stopinsert')
  end)
  map('n', 'close', close_editor)
end

local function open_editor(kind, title, lines, height, width)
  close_editor()

  width = width or editor_width()
  local row = math.max(0, math.floor((vim.o.lines - height - 2) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local win = window.open('form_editor', {
    width = width,
    height = height,
    row = row,
    col = col,
    title = title,
    border = 'rounded',
  })
  local buf = vim.api.nvim_win_get_buf(win)

  editor.win = win
  editor.buf = buf
  editor.kind = kind
  editor.selected = 1

  vim.api.nvim_buf_set_name(buf, 'google-calendar://form-editor/' .. kind)
  set_write_command(buf, save_editor)
  set_editor_lines(lines)
  set_editor_keymaps(buf)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.api.nvim_set_current_win(win)

  return win
end

local function open_summary_editor()
  open_editor('summary', ' タイトル ', { form.values.summary or '' }, 1)
end

local function open_location_editor()
  open_editor('location', ' 場所 ', { form.values.location or '' }, 1)
end

local function open_description_editor()
  local lines = vim.split(form.values.description or '', '\n', { plain = true })
  if #lines == 0 then
    lines = { '' }
  end
  open_editor('description', ' 説明 ', lines, FORM_HEIGHT, form.width)
end

local function open_datetime_editor()
  open_editor('datetime', ' 日時 ', {
    '開始: ' .. form.values.start,
    '終了: ' .. form.values['end'],
    '終日: ' .. (form.values.all_day and 'on' or 'off'),
  }, 3)
end

local function open_guests_editor()
  local lines = {}
  for _, email in ipairs(form.values.attendees or {}) do
    table.insert(lines, email)
  end
  if #lines == 0 then
    lines = { '' }
  end
  open_editor('guests', ' ゲスト ', lines, math.max(1, math.min(10, #lines)))
end

local function toggle_all_day()
  local start_date = form.values.start:sub(1, 10)
  if not form.values.all_day then
    form.values.all_day = true
    form.values.start = start_date
    if calendar.parse_date(start_date) ~= nil then
      form.values['end'] = calendar.add_days(start_date, 1)
    end
  else
    form.values.all_day = false
    form.values.start = start_date .. ' 09:00'
    form.values['end'] = start_date .. ' 10:00'
  end
  render()
end

local function toggle_meet()
  if form.mode == 'edit' then
    return
  end
  form.values.meet = not form.values.meet
  render()
end

local function open_selected()
  if not form.active or form.saving then
    return
  end
  sync_selection()
  local row = selected_row()
  if row.kind == 'summary' then
    open_summary_editor()
  elseif row.kind == 'datetime' then
    open_datetime_editor()
  elseif row.kind == 'guests' then
    open_guests_editor()
  elseif row.kind == 'toggle' then
    toggle_meet()
  elseif row.key == 'location' then
    open_location_editor()
  elseif row.key == 'description' then
    open_description_editor()
  else
    notify('This field cannot be changed', vim.log.levels.WARN)
  end
end

local function toggle_selected()
  if not form.active or form.saving then
    return
  end
  sync_selection()
  local row = selected_row()
  if row.key == 'datetime' then
    toggle_all_day()
  elseif row.key == 'meet' then
    toggle_meet()
  end
end

local function validate(values)
  local title = vim.trim(values.summary)
  if title == '' then
    return nil, 'Title is required', 'summary'
  end
  if vim.fn.strchars(title) > TITLE_LIMIT then
    return nil, 'Title must be 1024 characters or fewer', 'summary'
  end
  if vim.fn.strchars(values.location) > LOCATION_LIMIT then
    return nil, 'Location must be 1024 characters or fewer', 'location'
  end
  if vim.fn.strchars(values.description) > DESCRIPTION_LIMIT then
    return nil, 'Description must be 8192 characters or fewer', 'description'
  end

  if values.all_day then
    if calendar.parse_date(values.start) == nil then
      return nil, 'Start date must be in YYYY-MM-DD format', 'start'
    end
    if calendar.parse_date(values['end']) == nil then
      return nil, 'End date must be in YYYY-MM-DD format', 'end'
    end
    if values['end'] <= values.start then
      return nil, 'End date must be after the start date', 'end'
    end

    return {
      summary = title,
      all_day = true,
      start = values.start,
      ['end'] = values['end'],
      location = values.location,
      description = values.description,
      meet = values.meet,
      attendees = values.attendees,
    }
  end

  local start_year, start_month, start_day, start_hour, start_minute = calendar.parse_datetime(values.start)
  if start_year == nil then
    return nil, 'Start date/time must be in YYYY-MM-DD HH:MM format', 'start'
  end
  local end_year, end_month, end_day, end_hour, end_minute = calendar.parse_datetime(values['end'])
  if end_year == nil then
    return nil, 'End date/time must be in YYYY-MM-DD HH:MM format', 'end'
  end
  if values['end'] <= values.start then
    return nil, 'End must be after the start', 'end'
  end

  return {
    summary = title,
    all_day = false,
    start = calendar.rfc3339(
      string.format('%04d-%02d-%02d', start_year, start_month, start_day),
      string.format('%02d:%02d', start_hour, start_minute)
    ),
    ['end'] = calendar.rfc3339(
      string.format('%04d-%02d-%02d', end_year, end_month, end_day),
      string.format('%02d:%02d', end_hour, end_minute)
    ),
    location = values.location,
    description = values.description,
    meet = values.meet,
    attendees = values.attendees,
  }
end

local function error_detail(err)
  local detail
  if type(err) == 'string' then
    detail = err
  elseif type(err) == 'table' then
    detail = err.message or err.reason
  end
  return detail or 'Unknown error'
end

local function in_display_range(created)
  if state.year == nil or state.month == nil then
    return true
  end

  local date = event.start_date(created)
  if date == nil then
    return true
  end

  local cfg = config.get()
  local grid = calendar.month_grid(state.year, state.month, cfg.week_start)
  return date >= grid.weeks[1][1].date and date <= grid.weeks[6][7].date
end

local CHANGE_KEYS = { 'summary', 'start', 'end', 'all_day', 'location', 'description', 'attendees' }

local function emails_key(emails)
  return table.concat(emails or {}, '\n')
end

local function changed_fields()
  local changed = {}
  for _, key in ipairs(CHANGE_KEYS) do
    if key == 'attendees' then
      changed[key] = emails_key(form.values.attendees) ~= emails_key(form.initial_values.attendees)
    else
      changed[key] = form.values[key] ~= form.initial_values[key]
    end
  end
  return changed
end

local function has_changes(changed)
  for _, key in ipairs(CHANGE_KEYS) do
    if changed[key] then
      return true
    end
  end
  return false
end

local function update_changes(fields, changed)
  local changes = {}

  if changed.summary then
    changes.summary = fields.summary
  end
  if changed.location then
    changes.location = fields.location
  end
  if changed.description then
    changes.description = fields.description
  end
  if changed.attendees then
    local existing = {}
    for _, attendee in ipairs(form.initial_values.attendee_details or {}) do
      if attendee.email ~= nil then
        existing[attendee.email] = attendee
      end
    end
    changes.attendees = {}
    for _, email in ipairs(fields.attendees or {}) do
      table.insert(changes.attendees, existing[email] or { email = email })
    end
  end

  local function time_value(value)
    if fields.all_day then
      return { date = value }
    end
    return { dateTime = value }
  end

  if changed.start then
    changes.start = time_value(fields.start)
  end
  if changed['end'] then
    changes['end'] = time_value(fields['end'])
  end

  return changes
end

local function close_edit_windows()
  form.saving = false
  form.active = false
  local on_changed = form.on_changed
  form.on_changed = nil

  close_editor()
  window.close('form')
  window.close('detail')

  return on_changed
end

local function close_after_update(updated)
  local on_changed = close_edit_windows()

  if in_display_range(updated) then
    notify('Event updated', vim.log.levels.INFO)
  else
    notify('Event updated (not visible in the current month)', vim.log.levels.INFO)
  end

  if on_changed ~= nil then
    on_changed(updated)
  end
end

local function close_after_deleted(err)
  local on_changed = close_edit_windows()

  notify_adapter.error(err)

  if on_changed ~= nil then
    on_changed()
  end
end

local function handle_edit_error(err, prefix)
  if err.kind == 'api' and err.code == 404 then
    close_after_deleted(err)
    return
  end

  form.saving = false
  form.error = prefix .. ': ' .. notify_adapter.message(err)
  form.error_field = nil
  render()
  notify_adapter.error(err)
end

local function save_edit(fields)
  local changed = changed_fields()
  if not has_changes(changed) then
    form.saving = false
    form.active = false
    form.on_changed = nil
    close_editor()
    window.close('form')
    return
  end

  local changes = update_changes(fields, changed)
  local gws = require('google-calendar.gws')

  gws.get_event(form.event_id, function(base, err)
    vim.schedule(function()
      if not form.active or not vim.api.nvim_win_is_valid(form.win) then
        return
      end

      if err ~= nil then
        handle_edit_error(err, 'Could not retrieve the event')
        return
      end

      local update_fields = event.merge_update(base, changes)
      update_fields.calendar_id = base.calendar_id or config.get().calendars[1] or 'primary'

      gws.update_event(update_fields, function(updated, update_err)
        vim.schedule(function()
          if not form.active or not vim.api.nvim_win_is_valid(form.win) then
            return
          end

          if update_err ~= nil then
            handle_edit_error(update_err, 'Could not update the event')
            return
          end

          close_after_update(updated)
        end)
      end)
    end)
  end)
end

local function save_create(fields)
  fields.calendar_id = config.get().calendars[1] or 'primary'
  local gws = require('google-calendar.gws')
  gws.create_event(fields, function(created, err)
    vim.schedule(function()
      if not form.active or not vim.api.nvim_win_is_valid(form.win) then
        return
      end

      form.saving = false
      if err ~= nil then
        form.error = 'Could not create the event: ' .. error_detail(err)
        form.error_field = nil
        render()
        notify(form.error, vim.log.levels.ERROR)
        return
      end

      local meet = form.values.meet
      local on_created = form.on_created
      local in_range = in_display_range(created)

      close_editor()
      window.close('form')
      form.active = false
      form.on_created = nil

      if in_range then
        notify('Event created', vim.log.levels.INFO)
      else
        notify('Event created (not visible in the current month)', vim.log.levels.INFO)
      end

      if meet and created.hangout_link == nil then
        notify('Event created, but no Meet URL was added', vim.log.levels.WARN)
      end

      if on_created ~= nil then
        on_created(created)
      end
    end)
  end)
end

local function save()
  if not form.active or form.saving then
    return
  end

  local fields, message, error_field = validate(form.values)
  if fields == nil then
    form.error = message
    form.error_field = error_field
    render()
    return
  end

  form.saving = true
  form.error = nil
  form.error_field = nil
  render()

  if form.mode == 'edit' then
    save_edit(fields)
  else
    save_create(fields)
  end
end

local function cancel()
  if not form.active or form.saving then
    return
  end

  close_editor()
  form.active = false
  form.on_created = nil
  form.on_changed = nil
  window.close('form')
end

local function open_help()
  if not form.active or form.saving then
    return
  end
  require('google-calendar.ui.help').open('form')
end

local function set_keymaps(buf)
  local function map(mode, action, handler)
    local key = config.resolve('form', action)
    if key ~= nil then
      vim.keymap.set(mode, key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end

  map({ 'n', 'i' }, 'next_field', function()
    vim.cmd('stopinsert')
    move_field(1)
  end)
  map({ 'n', 'i' }, 'prev_field', function()
    vim.cmd('stopinsert')
    move_field(-1)
  end)

  map('n', 'edit', open_selected)
  map('n', 'toggle', toggle_selected)
  local save_key = config.resolve('form', 'save')
  if save_key ~= nil and save_key ~= ':w' then
    vim.keymap.set({ 'n', 'i' }, save_key, function()
      vim.cmd('stopinsert')
      save()
    end, { buffer = buf, nowait = true, silent = true })
  end
  map('n', 'cancel', cancel)
  map('n', 'close', cancel)
  map('n', 'help', open_help)
end

local function open_window(title)
  local width = math.max(1, math.min(FORM_WIDTH_MAX, vim.o.columns - 8))
  local height = FORM_HEIGHT
  local row = math.max(0, math.floor((vim.o.lines - height - 2) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local win = window.open('form', {
    width = width,
    height = height,
    row = row,
    col = col,
    title = title,
    border = 'rounded',
  })
  local buf = vim.api.nvim_win_get_buf(win)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  form.width = width

  vim.api.nvim_buf_set_name(buf, 'google-calendar://form')
  set_write_command(buf, save)
  set_keymaps(buf)

  return win, buf
end

local function edit_values(item)
  local emails = {}
  for _, attendee in ipairs(item.attendees or {}) do
    if attendee.email ~= nil then
      table.insert(emails, attendee.email)
    end
  end
  return {
    summary = vim.trim(event.sanitize(item.summary)),
    start = event.display_datetime(item.start) or '',
    ['end'] = event.display_datetime(item['end']) or '',
    all_day = event.is_all_day(item),
    location = vim.trim(event.sanitize(item.location)),
    description = vim.trim(item.description or ''),
    meet = item.hangout_link or '',
    attendees = emails,
    attendee_details = item.attendees,
  }
end

function M.open_create(opts)
  opts = opts or {}

  if form.active and vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_set_current_win(form.win)
    return form.win
  end

  local date = state.selected_date or calendar.today()
  local win, buf = open_window(' 新しい予定 ')

  form.active = true
  form.mode = 'create'
  form.event_id = nil
  form.initial_values = nil
  form.on_changed = nil
  form.win = win
  form.buf = buf
  form.selected = 1
  form.saving = false
  form.error = nil
  form.error_field = nil
  form.on_created = opts.on_created
  form.values = {
    summary = '',
    start = date .. ' 09:00',
    ['end'] = date .. ' 10:00',
    all_day = false,
    location = '',
    description = '',
    meet = false,
    attendees = {},
  }

  render()
  vim.api.nvim_set_current_win(win)

  return win
end

function M.open_edit(item, opts)
  if item == nil then
    return nil
  end

  opts = opts or {}

  if form.active and vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_set_current_win(form.win)
    return form.win
  end

  local win, buf = open_window(' 予定を更新 ')

  form.active = true
  form.mode = 'edit'
  form.event_id = item.id
  form.on_created = nil
  form.on_changed = opts.on_changed
  form.win = win
  form.buf = buf
  form.selected = 1
  form.saving = false
  form.error = nil
  form.error_field = nil
  form.values = edit_values(item)
  form.initial_values = vim.deepcopy(form.values)

  render()
  vim.api.nvim_set_current_win(win)

  return win
end

return M
