local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local namespace_name = 'google-calendar-form'
local LABEL_WIDTH = 10
local TITLE_LIMIT = 1024
local LOCATION_LIMIT = 1024
local DESCRIPTION_LIMIT = 8192

local FIELDS = {
  { key = 'summary', label = 'タイトル:', type = 'text' },
  { key = 'start', label = '開始:', type = 'text' },
  { key = 'end', label = '終了:', type = 'text' },
  { key = 'all_day', label = '終日:', type = 'toggle' },
  { key = 'location', label = '場所:', type = 'text' },
  { key = 'description', label = '説明:', type = 'text' },
  { key = 'meet', label = 'Meet:', type = 'toggle' },
}

---@class GoogleCalendarForm
---@field active boolean
---@field win integer
---@field buf integer
---@field selected integer
---@field saving boolean
---@field error string|nil
---@field error_field string|nil
---@field on_created function|nil
---@field values table

---@type GoogleCalendarForm
local form = {
  active = false,
  win = 0,
  buf = 0,
  selected = 1,
  saving = false,
  error = nil,
  error_field = nil,
  on_created = nil,
  values = {},
}

local function notify(message, level)
  config.get().notify(message, level)
end

local function pad_label(label)
  return label .. string.rep(' ', LABEL_WIDTH - vim.fn.strdisplaywidth(label))
end

local function format_value(field, value)
  if field.type == 'toggle' then
    return value and 'on' or 'off'
  end
  return value
end

local function key_footer()
  local parts = {}

  local field_keys = {}
  local next_key = config.resolve('form', 'next_field')
  local prev_key = config.resolve('form', 'prev_field')
  if next_key ~= nil then
    table.insert(field_keys, next_key)
  end
  if prev_key ~= nil then
    table.insert(field_keys, prev_key)
  end
  if #field_keys > 0 then
    table.insert(parts, table.concat(field_keys, '/') .. ':移動')
  end

  local edit_key = config.resolve('form', 'edit')
  if edit_key ~= nil then
    table.insert(parts, edit_key .. ':編集')
  end

  local toggle_key = config.resolve('form', 'toggle')
  if toggle_key ~= nil then
    table.insert(parts, toggle_key .. ':切替')
  end

  local save_key = config.resolve('form', 'save')
  if save_key ~= nil then
    table.insert(parts, save_key .. ':保存')
  end

  local cancel_key = config.resolve('form', 'cancel')
  if cancel_key ~= nil then
    table.insert(parts, cancel_key .. ':取消')
  end

  if #parts == 0 then
    return '有効なキーがありません'
  end

  return table.concat(parts, '  ')
end

local function footer_text()
  if form.saving then
    return '保存中...'
  end
  if form.error ~= nil then
    return 'エラー: ' .. form.error
  end
  return key_footer()
end

local function field_index(key)
  for index, field in ipairs(FIELDS) do
    if field.key == key then
      return index
    end
  end
  return nil
end

local function render()
  local lines = {}
  for index, field in ipairs(FIELDS) do
    lines[index] = pad_label(field.label) .. format_value(field, form.values[field.key])
  end
  lines[#FIELDS + 1] = ''
  lines[#FIELDS + 2] = footer_text()

  vim.bo[form.buf].modifiable = true
  vim.api.nvim_buf_set_lines(form.buf, 0, -1, false, lines)
  vim.bo[form.buf].modifiable = false

  local ns = vim.api.nvim_create_namespace(namespace_name)
  vim.api.nvim_buf_clear_namespace(form.buf, ns, 0, -1)
  local error_index = form.error_field and field_index(form.error_field)
  if error_index ~= nil then
    vim.api.nvim_buf_set_extmark(form.buf, ns, error_index - 1, 0, {
      end_col = #lines[error_index],
      hl_group = 'GoogleCalendarError',
    })
  end

  if vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_win_set_cursor(form.win, { form.selected, 0 })
  end
end

local function sync_selection()
  local line = vim.api.nvim_win_get_cursor(form.win)[1]
  if line >= 1 and line <= #FIELDS then
    form.selected = line
  end
end

local function read_values()
  local lines = vim.api.nvim_buf_get_lines(form.buf, 0, #FIELDS, false)
  for index, field in ipairs(FIELDS) do
    local line = lines[index] or ''
    if field.type == 'toggle' then
      form.values[field.key] = line:match('^' .. field.label .. '%s*(%a+)$') == 'on'
    else
      local value = line:match('^' .. field.label .. '%s*(.*)$')
      form.values[field.key] = vim.trim(value or line)
    end
  end
end

local function on_insert_leave()
  if not form.active or not vim.api.nvim_win_is_valid(form.win) then
    return
  end

  read_values()
  vim.bo[form.buf].modifiable = false
  render()
end

local function edit_selected()
  if not form.active or form.saving then
    return
  end

  sync_selection()
  local field = FIELDS[form.selected]
  if field.type ~= 'text' then
    return
  end

  vim.bo[form.buf].modifiable = true
  vim.cmd('startinsert!')
end

local function toggle_selected()
  if not form.active or form.saving then
    return
  end

  sync_selection()
  local field = FIELDS[form.selected]
  if field.type ~= 'toggle' then
    return
  end

  local enabled = not form.values[field.key]
  form.values[field.key] = enabled

  if field.key == 'all_day' then
    local start_date = form.values.start:sub(1, 10)
    form.values.start = start_date
    if enabled then
      if calendar.parse_date(start_date) ~= nil then
        form.values['end'] = calendar.add_days(start_date, 1)
      end
    else
      form.values.start = start_date .. ' 09:00'
      form.values['end'] = start_date .. ' 10:00'
    end
  end

  render()
end

local function move_field(delta)
  if not form.active or form.saving then
    return
  end

  sync_selection()
  form.selected = ((form.selected - 1 + delta) % #FIELDS) + 1
  vim.api.nvim_win_set_cursor(form.win, { form.selected, 0 })
end

local function validate(values)
  local title = vim.trim(values.summary)
  if title == '' then
    return nil, 'タイトルを入力してください', 'summary'
  end
  if vim.fn.strchars(title) > TITLE_LIMIT then
    return nil, 'タイトルは 1024 文字以内で入力してください', 'summary'
  end
  if vim.fn.strchars(values.location) > LOCATION_LIMIT then
    return nil, '場所は 1024 文字以内で入力してください', 'location'
  end
  if vim.fn.strchars(values.description) > DESCRIPTION_LIMIT then
    return nil, '説明は 8192 文字以内で入力してください', 'description'
  end

  if values.all_day then
    if calendar.parse_date(values.start) == nil then
      return nil, '開始日は YYYY-MM-DD 形式で入力してください', 'start'
    end
    if calendar.parse_date(values['end']) == nil then
      return nil, '終了日は YYYY-MM-DD 形式で入力してください', 'end'
    end
    if values['end'] <= values.start then
      return nil, '終了日は開始日より後にしてください', 'end'
    end

    return {
      summary = title,
      all_day = true,
      start = values.start,
      ['end'] = values['end'],
      location = values.location,
      description = values.description,
      meet = values.meet,
    }
  end

  local start_year, start_month, start_day, start_hour, start_minute = calendar.parse_datetime(values.start)
  if start_year == nil then
    return nil, '開始日時は YYYY-MM-DD HH:MM 形式で入力してください', 'start'
  end
  local end_year, end_month, end_day, end_hour, end_minute = calendar.parse_datetime(values['end'])
  if end_year == nil then
    return nil, '終了日時は YYYY-MM-DD HH:MM 形式で入力してください', 'end'
  end
  if values['end'] <= values.start then
    return nil, '終了は開始より後にしてください', 'end'
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
  }
end

local function error_detail(err)
  local detail
  if type(err) == 'string' then
    detail = err
  elseif type(err) == 'table' then
    detail = err.message or err.reason
  end
  return detail or '不明なエラー'
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

local function save()
  if not form.active or form.saving then
    return
  end

  read_values()
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

  fields.calendar_id = config.get().calendars[1] or 'primary'
  local gws = require('google-calendar.gws')
  gws.create_event(fields, function(created, err)
    vim.schedule(function()
      if not form.active or not vim.api.nvim_win_is_valid(form.win) then
        return
      end

      form.saving = false
      if err ~= nil then
        form.error = '予定を作成できませんでした: ' .. error_detail(err)
        form.error_field = nil
        render()
        notify(form.error, vim.log.levels.ERROR)
        return
      end

      local meet = form.values.meet
      local on_created = form.on_created
      local in_range = in_display_range(created)

      window.close('form')
      form.active = false
      form.on_created = nil

      if in_range then
        notify('予定を作成しました', vim.log.levels.INFO)
      else
        notify('予定を作成しました（表示中の月には表示されません）', vim.log.levels.INFO)
      end

      if meet and created.hangout_link == nil then
        notify('予定は作成されましたが、Meet URL は付きませんでした', vim.log.levels.WARN)
      end

      if on_created ~= nil then
        on_created(created)
      end
    end)
  end)
end

local function cancel()
  if not form.active or form.saving then
    return
  end

  form.active = false
  form.on_created = nil
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

  local edit_key = config.resolve('form', 'edit')
  if edit_key ~= nil then
    vim.keymap.set('n', edit_key, edit_selected, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set('i', edit_key, function()
      vim.cmd('stopinsert')
    end, { buffer = buf, nowait = true, silent = true })
  end

  map('n', 'toggle', toggle_selected)
  map({ 'n', 'i' }, 'save', function()
    vim.cmd('stopinsert')
    save()
  end)
  map({ 'n', 'i' }, 'cancel', cancel)
  map('n', 'help', open_help)
end

function M.open_create(opts)
  opts = opts or {}

  if form.active and vim.api.nvim_win_is_valid(form.win) then
    vim.api.nvim_set_current_win(form.win)
    return form.win
  end

  local date = state.selected_date or calendar.today()
  local width = math.min(80, math.max(40, vim.o.columns - 8))
  local height = #FIELDS + 2
  local row = math.max(0, math.floor((vim.o.lines - height - 2) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local win = window.open('form', {
    width = width,
    height = height,
    row = row,
    col = col,
    title = ' 予定を登録 ',
    border = 'rounded',
  })
  local buf = vim.api.nvim_win_get_buf(win)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  form.active = true
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
  }

  set_keymaps(buf)
  vim.api.nvim_create_autocmd('InsertLeave', { buffer = buf, callback = on_insert_leave })
  render()

  return win
end

return M
