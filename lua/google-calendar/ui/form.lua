local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local recurrence = require('google-calendar.recurrence')
local notify_adapter = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local namespace_name = 'google-calendar-form'
local TITLE_LIMIT = 1024
local LOCATION_LIMIT = 1024
local DESCRIPTION_LIMIT = 8192
local FORM_WIDTH_MAX = 80
local FORM_HEIGHT = 12

local WEEKDAYS = { '日', '月', '火', '水', '木', '金', '土' }
local ICON_CALENDAR = '▣'
local ICON_CLOCK = '◷'
local ICON_GUESTS = '◉'
local ICON_MEET = '▶'
local ICON_LOCATION = '⌖'
local ICON_NOTES = '≡'
local ICON_RECURRENCE = '↻'

local ROWS = {
  { key = 'summary', line = 1, kind = 'summary' },
  { key = 'datetime', line = 4, kind = 'datetime' },
  { key = 'recurrence', line = 5, kind = 'recurrence' },
  { key = 'guests', line = 6, kind = 'guests' },
  { key = 'meet', line = 7, kind = 'toggle' },
  { key = 'location', line = 8, kind = 'text' },
  { key = 'description', line = 9, kind = 'text' },
  { key = 'calendar', line = 10, kind = 'calendar' },
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
  calendar_id = nil,
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

local recurrence_options = {}
local custom_recurrence_draft = nil
local custom_selector_options = {}
local custom_weekday_selection = {}
local open_custom_recurrence_editor
local current_editor_lines
local custom_config_from_lines
local custom_recurrence_rows
local open_custom_unit_selector
local open_custom_end_selector
local open_custom_weekday_selector
local open_custom_date_selector
local open_custom_date_day_selector
local custom_date_stage = nil
local custom_date_month = nil
local WEEKDAY_CODES = { 'SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA' }
local UNIT_PHRASES = { DAILY = '日ごと', WEEKLY = '週間ごと', MONTHLY = '月ごと', YEARLY = '年ごと' }
local UNIT_BY_PHRASE = {}
for freq, phrase in pairs(UNIT_PHRASES) do
  UNIT_BY_PHRASE[phrase] = freq
end
local UNIT_OPTIONS = {
  { key = 'DAILY', label = '日ごと' },
  { key = 'WEEKLY', label = '週間ごと' },
  { key = 'MONTHLY', label = '月ごと' },
  { key = 'YEARLY', label = '年ごと' },
}
local END_OPTIONS = {
  { key = 'never', label = 'なし' },
  { key = 'until', label = '終了日' },
  { key = 'count', label = '回数' },
}
local END_TYPE_BY_LABEL = { ['なし'] = 'never', ['終了日'] = 'until', ['回数'] = 'count' }

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

  local recurrence_label = recurrence.label(form.values.recurrence, form.values.start)
  add_icon_line(
    add,
    ICON_RECURRENCE,
    event.truncate(recurrence_label, math.max(1, width - 2)),
    form.values.recurrence == nil and 'GoogleCalendarFormMuted' or nil
  )

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

local function custom_start_date()
  local date = form.values.start:sub(1, 10)
  if calendar.parse_date(date) == nil then
    date = tostring(calendar.today())
  end
  return date
end

local function start_weekday_code()
  local date = custom_start_date()
  local year, month, day = calendar.parse_date(date)
  year = assert(year)
  month = assert(month)
  day = assert(day)
  local weekday = tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 }))) or 0
  return WEEKDAY_CODES[weekday + 1]
end

local function default_until_date()
  return calendar.add_days(custom_start_date(), 30)
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
  elseif editor.kind == 'recurrence' then
    local line = vim.api.nvim_win_get_cursor(editor.win)[1]
    local option = recurrence_options[line]
    if option == nil then
      return
    end
    if option.key == 'custom' then
      close_editor()
      open_custom_recurrence_editor(form.values.recurrence)
      return
    end
    form.values.recurrence = option.config
  elseif editor.kind == 'recurrence_unit' or editor.kind == 'recurrence_end' then
    local line = vim.api.nvim_win_get_cursor(editor.win)[1]
    local option = custom_selector_options[line]
    if option == nil then
      return
    end

    local draft = custom_recurrence_draft or {}
    if editor.kind == 'recurrence_unit' then
      local previous_freq = draft.freq
      draft.freq = option.key
      if draft.freq ~= previous_freq then
        draft.byday = nil
        draft.bymonth = nil
        draft.bymonthday = nil
      end
      if draft.freq == 'WEEKLY' then
        if draft.byday == nil or #draft.byday == 0 then
          draft.byday = { start_weekday_code() }
        end
        draft.bymonth = nil
        draft.bymonthday = nil
      elseif draft.freq == 'MONTHLY' then
        draft.bymonth = nil
        draft.bymonthday = draft.bymonthday or tonumber(custom_start_date():sub(9, 10))
        draft.byday = nil
      else
        draft.byday = nil
        draft.bymonth = nil
        draft.bymonthday = nil
      end
    else
      draft.end_type = option.key
      if draft.end_type == 'until' then
        draft.until_date = draft.until_date or default_until_date()
      elseif draft.end_type == 'count' then
        draft.count = tonumber(draft.count) or 13
      end
    end

    draft.end_type = draft.end_type or 'never'
    draft.until_date = draft.until_date or default_until_date()
    draft.count = tonumber(draft.count) or 13
    custom_recurrence_draft = draft
    close_editor()
    open_custom_recurrence_editor(draft, editor.kind == 'recurrence_unit' and 'unit' or 'end')
    return
  elseif editor.kind == 'recurrence_date' then
    local line = vim.api.nvim_win_get_cursor(editor.win)[1]
    local option = custom_selector_options[line]
    if option == nil then
      return
    end

    local draft = custom_recurrence_draft or {}
    if custom_date_stage == 'month' then
      open_custom_date_day_selector(option.key)
      return
    end

    if draft.freq == 'YEARLY' then
      draft.bymonth = custom_date_month or draft.bymonth
      draft.bymonthday = option.key
    else
      draft.bymonthday = option.key
    end
    custom_recurrence_draft = draft
    close_editor()
    open_custom_recurrence_editor(draft, draft.freq == 'YEARLY' and 'yearday' or 'monthday')
    return
  elseif editor.kind == 'recurrence_weekday' then
    local selected = {}
    for index, line in ipairs(lines) do
      if line:match('^●') then
        table.insert(selected, WEEKDAY_CODES[index])
      end
    end
    if #selected == 0 then
      notify('Select at least one weekday', vim.log.levels.WARN)
      return
    end

    local draft = custom_recurrence_draft or {}
    draft.byday = selected
    custom_recurrence_draft = draft
    close_editor()
    open_custom_recurrence_editor(draft, 'weekday')
    return
  elseif editor.kind == 'recurrence_custom' then
    local draft = custom_config_from_lines(lines, custom_recurrence_draft)
    local ok, err = recurrence.validate(draft, form.values.start)
    if not ok then
      notify(err, vim.log.levels.WARN)
      return
    end
    form.values.recurrence = draft
    custom_recurrence_draft = draft
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

local function editor_edit_custom()
  local line = vim.api.nvim_win_get_cursor(editor.win)[1]
  editor.selected = line
  local draft = custom_config_from_lines(current_editor_lines(), custom_recurrence_draft)
  custom_recurrence_draft = draft
  local row = custom_recurrence_rows(draft)[line]
  if row == nil then
    return
  end

  if row.key == 'unit' then
    open_custom_unit_selector()
  elseif row.key == 'weekday' then
    open_custom_weekday_selector()
  elseif row.key == 'end' then
    open_custom_end_selector()
  elseif row.key == 'monthday' or row.key == 'yearday' then
    open_custom_date_selector()
  elseif row.key == 'interval' or row.key == 'until' or row.key == 'count' then
    vim.cmd('startinsert!')
  end
end

local function editor_toggle_weekday()
  local line = vim.api.nvim_win_get_cursor(editor.win)[1]
  local code = WEEKDAY_CODES[line]
  if code == nil then
    return
  end

  custom_weekday_selection[code] = not custom_weekday_selection[code]
  local lines = vim.api.nvim_buf_get_lines(editor.buf, 0, -1, false)
  lines[line] = (custom_weekday_selection[code] and '● ' or '○ ') .. WEEKDAYS[line]
  set_editor_lines(lines)
  vim.api.nvim_win_set_cursor(editor.win, { line, 0 })
end

local function set_editor_keymaps(buf)
  local function map(mode, action, handler)
    local key = config.resolve('form', action)
    if key ~= nil then
      vim.keymap.set(mode, key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end

  if editor.kind ~= 'datetime' and editor.kind ~= 'recurrence_custom' then
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
  elseif editor.kind == 'recurrence' then
    map('n', 'next_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local next_line = math.min(#recurrence_options, line + 1)
      vim.api.nvim_win_set_cursor(editor.win, { next_line, 0 })
    end)
    map('n', 'prev_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local prev_line = math.max(1, line - 1)
      vim.api.nvim_win_set_cursor(editor.win, { prev_line, 0 })
    end)
  elseif editor.kind == 'recurrence_unit' or editor.kind == 'recurrence_end' then
    map('n', 'next_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local next_line = math.min(#custom_selector_options, line + 1)
      vim.api.nvim_win_set_cursor(editor.win, { next_line, 0 })
    end)
    map('n', 'prev_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local prev_line = math.max(1, line - 1)
      vim.api.nvim_win_set_cursor(editor.win, { prev_line, 0 })
    end)
    map('n', 'toggle', save_editor)
  elseif editor.kind == 'recurrence_date' then
    map('n', 'next_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local next_line = math.min(#custom_selector_options, line + 1)
      vim.api.nvim_win_set_cursor(editor.win, { next_line, 0 })
    end)
    map('n', 'prev_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local prev_line = math.max(1, line - 1)
      vim.api.nvim_win_set_cursor(editor.win, { prev_line, 0 })
    end)
    map('n', 'toggle', save_editor)
  elseif editor.kind == 'recurrence_weekday' then
    map('n', 'next_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local next_line = math.min(#WEEKDAY_CODES, line + 1)
      vim.api.nvim_win_set_cursor(editor.win, { next_line, 0 })
    end)
    map('n', 'prev_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local prev_line = math.max(1, line - 1)
      vim.api.nvim_win_set_cursor(editor.win, { prev_line, 0 })
    end)
    map('n', 'edit', save_editor)
    map('n', 'toggle', editor_toggle_weekday)
  elseif editor.kind == 'recurrence_custom' then
    map('n', 'next_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local next_line = math.min(#custom_recurrence_rows(custom_recurrence_draft), line + 1)
      vim.api.nvim_win_set_cursor(editor.win, { next_line, 0 })
    end)
    map('n', 'prev_field', function()
      local line = vim.api.nvim_win_get_cursor(editor.win)[1]
      local prev_line = math.max(1, line - 1)
      vim.api.nvim_win_set_cursor(editor.win, { prev_line, 0 })
    end)
    map('n', 'edit', editor_edit_custom)
    map('n', 'toggle', editor_edit_custom)
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
  -- キーマップ処理の終了後に挿入モードへ入る。直接 startinsert すると
  -- マッピング終了時のモード復元でノーマルモードに戻ることがある。
  vim.schedule(function()
    if editor.kind == 'summary' and vim.api.nvim_win_is_valid(editor.win) then
      vim.api.nvim_set_current_win(editor.win)
      vim.cmd('startinsert!')
    end
  end)
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

current_editor_lines = function()
  if editor.buf == 0 or not vim.api.nvim_buf_is_valid(editor.buf) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(editor.buf, 0, -1, false)
end

local function default_custom_config()
  return {
    freq = 'WEEKLY',
    interval = 1,
    byday = { start_weekday_code() },
    end_type = 'never',
    until_date = default_until_date(),
    count = 13,
  }
end

local function normalize_custom_config(recurrence_config)
  local draft = recurrence_config and vim.deepcopy(recurrence_config) or default_custom_config()
  draft.freq = draft.freq or 'WEEKLY'
  draft.interval = tonumber(draft.interval) or 1
  draft.end_type = draft.end_type or 'never'
  draft.until_date = draft.until_date or default_until_date()
  draft.count = tonumber(draft.count) or 13
  if draft.freq == 'WEEKLY' then
    if draft.byday == nil or #draft.byday == 0 then
      draft.byday = { start_weekday_code() }
    end
    draft.bymonth = nil
    draft.bymonthday = nil
  elseif draft.freq == 'MONTHLY' then
    draft.bymonth = nil
    draft.bymonthday = draft.bymonthday or tonumber(custom_start_date():sub(9, 10))
    draft.byday = nil
  elseif draft.freq == 'YEARLY' then
    draft.byday = nil
    if draft.bymonth ~= nil and draft.bymonthday ~= nil then
      draft.bymonth = tonumber(draft.bymonth)
      draft.bymonthday = tonumber(draft.bymonthday)
    else
      draft.bymonth = nil
      draft.bymonthday = nil
    end
  else
    draft.byday = nil
    draft.bymonth = nil
    draft.bymonthday = nil
  end
  return draft
end

custom_recurrence_rows = function(recurrence_config)
  local rows = {
    { key = 'interval', text = '間隔: ' .. recurrence_config.interval },
    { key = 'unit', text = '単位: ' .. (UNIT_PHRASES[recurrence_config.freq] or UNIT_PHRASES.WEEKLY) },
  }
  if recurrence_config.freq == 'WEEKLY' then
    rows[#rows + 1] = { key = 'weekday', text = '曜日: ' .. recurrence.weekday_text(recurrence_config.byday) }
  elseif recurrence_config.freq == 'MONTHLY' then
    rows[#rows + 1] = {
      key = 'monthday',
      text = '日付: ' .. (recurrence_config.bymonthday or tonumber(custom_start_date():sub(9, 10))),
    }
  elseif recurrence_config.freq == 'YEARLY' then
    local _, start_month, start_day = calendar.parse_date(custom_start_date())
    start_month = assert(start_month)
    start_day = assert(start_day)
    local month = recurrence_config.bymonth or start_month
    local day = recurrence_config.bymonthday or start_day
    rows[#rows + 1] = { key = 'yearday', text = '日付: ' .. month .. '月' .. day .. '日' }
  end
  rows[#rows + 1] = { key = 'end', text = '終了: ' .. recurrence.end_label(recurrence_config.end_type) }
  if recurrence_config.end_type == 'until' then
    rows[#rows + 1] = { key = 'until', text = '終了日: ' .. recurrence_config.until_date }
  elseif recurrence_config.end_type == 'count' then
    rows[#rows + 1] = { key = 'count', text = '回数: ' .. recurrence_config.count }
  end
  return rows
end

local function custom_recurrence_lines(recurrence_config)
  local lines = {}
  for _, row in ipairs(custom_recurrence_rows(recurrence_config)) do
    table.insert(lines, row.text)
  end
  return lines
end

custom_config_from_lines = function(lines, fallback)
  local draft = normalize_custom_config(fallback)
  local interval = (lines[1] or ''):match('^間隔:%s*(%d+)$')
  if interval ~= nil then
    draft.interval = tonumber(interval)
  end
  local unit = (lines[2] or ''):match('^単位:%s*(.*)$')
  if unit ~= nil and UNIT_BY_PHRASE[unit] ~= nil then
    draft.freq = UNIT_BY_PHRASE[unit]
  end

  local weekday_text = nil
  local monthday_text = nil
  local year_month_text = nil
  local year_day_text = nil
  local end_label = nil
  local until_date = nil
  local count = nil
  for _, line in ipairs(lines) do
    local value = line:match('^曜日:%s*(.*)$')
    if value ~= nil then
      weekday_text = value
    end
    value = line:match('^日付:%s*(%d+)日?$')
    if value ~= nil then
      monthday_text = value
    end
    local month_text, day_text = line:match('^日付:%s*(%d+)月(%d+)日$')
    if month_text ~= nil then
      year_month_text = tonumber(month_text)
      year_day_text = tonumber(day_text)
    end
    value = line:match('^終了:%s*(.*)$')
    if value ~= nil then
      end_label = value
    end
    value = line:match('^終了日:%s*(.*)$')
    if value ~= nil then
      until_date = vim.trim(value)
    end
    value = line:match('^回数:%s*(%d+)$')
    if value ~= nil then
      count = tonumber(value)
    end
  end

  if draft.freq == 'WEEKLY' then
    draft.byday = recurrence.parse_weekday_text(weekday_text or '', form.values.start)
    draft.bymonth = nil
    draft.bymonthday = nil
  elseif draft.freq == 'MONTHLY' then
    draft.bymonth = nil
    draft.bymonthday = tonumber(monthday_text) or draft.bymonthday or tonumber(custom_start_date():sub(9, 10))
    draft.byday = nil
  elseif draft.freq == 'YEARLY' then
    draft.byday = nil
    local _, start_month, start_day = calendar.parse_date(custom_start_date())
    start_month = assert(start_month)
    start_day = assert(start_day)
    if year_month_text ~= nil and year_day_text ~= nil then
      if year_month_text ~= start_month or year_day_text ~= start_day then
        draft.bymonth = year_month_text
        draft.bymonthday = year_day_text
      else
        draft.bymonth = nil
        draft.bymonthday = nil
      end
    elseif draft.bymonth == nil or draft.bymonthday == nil then
      draft.bymonth = nil
      draft.bymonthday = nil
    end
  else
    draft.byday = nil
    draft.bymonth = nil
    draft.bymonthday = nil
  end

  if end_label ~= nil and END_TYPE_BY_LABEL[end_label] ~= nil then
    draft.end_type = END_TYPE_BY_LABEL[end_label]
  end
  if until_date ~= nil and until_date ~= '' then
    draft.until_date = until_date
  end
  if count ~= nil then
    draft.count = count
  end
  draft.until_date = draft.until_date or default_until_date()
  draft.count = tonumber(draft.count) or 13
  return draft
end

local function custom_row_index(recurrence_config, key)
  for index, row in ipairs(custom_recurrence_rows(recurrence_config)) do
    if row.key == key then
      return index
    end
  end
  return nil
end

open_custom_recurrence_editor = function(recurrence_config, focus_key)
  custom_recurrence_draft = normalize_custom_config(recurrence_config)
  local lines = custom_recurrence_lines(custom_recurrence_draft)
  local win = open_editor('recurrence_custom', ' カスタムの繰り返し ', lines, #lines, 40)
  local line = custom_row_index(custom_recurrence_draft, focus_key) or 1
  editor.selected = line
  vim.api.nvim_win_set_cursor(win, { line, 0 })
end

open_custom_unit_selector = function()
  local draft = custom_config_from_lines(current_editor_lines(), custom_recurrence_draft)
  custom_recurrence_draft = draft
  custom_selector_options = UNIT_OPTIONS
  local lines = {}
  local selected = 1
  for index, option in ipairs(custom_selector_options) do
    local is_current = option.key == draft.freq
    lines[index] = (is_current and '● ' or '  ') .. option.label
    if is_current then
      selected = index
    end
  end
  local win = open_editor('recurrence_unit', ' 単位 ', lines, #lines, 30)
  editor.selected = selected
  vim.api.nvim_win_set_cursor(win, { selected, 0 })
end

open_custom_end_selector = function()
  local draft = custom_config_from_lines(current_editor_lines(), custom_recurrence_draft)
  custom_recurrence_draft = draft
  custom_selector_options = END_OPTIONS
  local lines = {}
  local selected = 1
  for index, option in ipairs(custom_selector_options) do
    local is_current = option.key == draft.end_type
    lines[index] = (is_current and '● ' or '  ') .. option.label
    if is_current then
      selected = index
    end
  end
  local win = open_editor('recurrence_end', ' 終了 ', lines, #lines, 30)
  editor.selected = selected
  vim.api.nvim_win_set_cursor(win, { selected, 0 })
end

local function open_date_selector(title, options, current, height)
  custom_selector_options = options
  local lines = {}
  local selected = 1
  for index, option in ipairs(options) do
    local is_current = option.key == current
    lines[index] = (is_current and '● ' or '  ') .. option.label
    if is_current then
      selected = index
    end
  end
  local win = open_editor('recurrence_date', title, lines, math.min(#lines, height), 20)
  editor.selected = selected
  vim.api.nvim_win_set_cursor(win, { selected, 0 })
end

open_custom_date_day_selector = function(month)
  local draft = custom_recurrence_draft or {}
  local current = 1
  if tonumber(draft.bymonth) == month and draft.bymonthday ~= nil then
    current = tonumber(draft.bymonthday) or 1
  else
    local _, start_month, start_day = calendar.parse_date(custom_start_date())
    start_month = assert(start_month)
    start_day = assert(start_day)
    if start_month == month then
      current = start_day
    end
  end
  local max_day = calendar.days_in_month(2000, month) or 31
  current = math.min(current, max_day)
  local options = {}
  for day = 1, max_day do
    options[day] = { key = day, label = day .. '日' }
  end
  custom_date_stage = 'day'
  custom_date_month = month
  open_date_selector(' 日付 ', options, current, 12)
end

open_custom_date_selector = function()
  local draft = custom_config_from_lines(current_editor_lines(), custom_recurrence_draft)
  custom_recurrence_draft = draft
  if draft.freq == 'MONTHLY' then
    local current = tonumber(draft.bymonthday) or tonumber(custom_start_date():sub(9, 10)) or 1
    local options = {}
    for day = 1, 31 do
      options[day] = { key = day, label = day .. '日' }
    end
    custom_date_stage = 'day'
    custom_date_month = nil
    open_date_selector(' 日付 ', options, current, 12)
  elseif draft.freq == 'YEARLY' then
    local _, start_month = calendar.parse_date(custom_start_date())
    start_month = assert(start_month)
    local current = tonumber(draft.bymonth) or start_month
    local options = {}
    for month = 1, 12 do
      options[month] = { key = month, label = month .. '月' }
    end
    custom_date_stage = 'month'
    custom_date_month = nil
    open_date_selector(' 月 ', options, current, 12)
  end
end

open_custom_weekday_selector = function()
  local draft = custom_config_from_lines(current_editor_lines(), custom_recurrence_draft)
  custom_recurrence_draft = draft
  custom_weekday_selection = {}
  for _, code in ipairs(draft.byday or {}) do
    custom_weekday_selection[code] = true
  end
  local lines = {}
  local selected = 1
  for index, code in ipairs(WEEKDAY_CODES) do
    local is_selected = custom_weekday_selection[code] == true
    lines[index] = (is_selected and '● ' or '○ ') .. WEEKDAYS[index]
    if is_selected then
      selected = index
    end
  end
  local win = open_editor('recurrence_weekday', ' 曜日 ', lines, #WEEKDAY_CODES, 30)
  editor.selected = selected
  vim.api.nvim_win_set_cursor(win, { selected, 0 })
end

local function open_recurrence_editor()
  recurrence_options = recurrence.presets(form.values.start)
  if #recurrence_options == 0 then
    notify('Set a valid start date/time first', vim.log.levels.WARN)
    return
  end
  local lines = {}
  local selected = 1
  local current_key = 'none'
  if form.values.recurrence ~= nil then
    current_key = recurrence.preset_key(form.values.recurrence, form.values.start)
  end

  for index, option in ipairs(recurrence_options) do
    local is_current = option.key == current_key
    lines[index] = (is_current and '● ' or '  ') .. option.label
    if is_current then
      selected = index
    end
  end

  local win = open_editor('recurrence', ' 繰り返し ', lines, #lines, 40)
  editor.selected = selected
  vim.api.nvim_win_set_cursor(win, { selected, 0 })
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
  elseif row.kind == 'recurrence' then
    open_recurrence_editor()
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

  local recurrence_ok, recurrence_err = recurrence.validate(values.recurrence, values.start)
  if not recurrence_ok then
    return nil, recurrence_err, 'recurrence'
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
      recurrence = recurrence.to_api(values.recurrence, values.all_day),
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
    recurrence = recurrence.to_api(values.recurrence, values.all_day),
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

local CHANGE_KEYS = { 'summary', 'start', 'end', 'all_day', 'location', 'description', 'attendees', 'recurrence' }

local function emails_key(emails)
  return table.concat(emails or {}, '\n')
end

local function changed_fields()
  local changed = {}
  for _, key in ipairs(CHANGE_KEYS) do
    if key == 'attendees' then
      changed[key] = emails_key(form.values.attendees) ~= emails_key(form.initial_values.attendees)
    elseif key == 'recurrence' then
      changed[key] = recurrence.key(form.values.recurrence) ~= recurrence.key(form.initial_values.recurrence)
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

  if changed.recurrence then
    changes.recurrence = fields.recurrence
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

  gws.get_event(form.event_id, form.calendar_id, function(base, err)
    vim.schedule(function()
      if not form.active or not vim.api.nvim_win_is_valid(form.win) then
        return
      end

      if err ~= nil then
        handle_edit_error(err, 'Could not retrieve the event')
        return
      end

      local update_fields = event.merge_update(base, changes)
      update_fields.calendar_id = base.calendar_id or form.calendar_id or config.get().calendars[1] or 'primary'

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
    recurrence = recurrence.parse(item.recurrence),
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
  form.calendar_id = nil
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
    recurrence = nil,
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
  form.calendar_id = item.calendar_id
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
