local calendar = require('google-calendar.calendar')

local M = {}

local WEEKDAYS = {
  { code = 'SU', label = '日' },
  { code = 'MO', label = '月' },
  { code = 'TU', label = '火' },
  { code = 'WE', label = '水' },
  { code = 'TH', label = '木' },
  { code = 'FR', label = '金' },
  { code = 'SA', label = '土' },
}
local WEEKDAY_BY_CODE = {}
local WEEKDAY_BY_LABEL = {}
for _, weekday in ipairs(WEEKDAYS) do
  WEEKDAY_BY_CODE[weekday.code] = weekday
  WEEKDAY_BY_LABEL[weekday.label] = weekday
end

local FREQS = { 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY' }
local UNIT_LABELS = { DAILY = '日', WEEKLY = '週', MONTHLY = '月', YEARLY = '年' }
local END_LABELS = { never = 'なし', ['until'] = '終了日', count = '回数' }

local function start_parts(start)
  local date = start and start:sub(1, 10) or calendar.today()
  local year, month, day = calendar.parse_date(date)
  if year == nil then
    return nil
  end
  year = assert(year)
  month = assert(month)
  day = assert(day)
  local weekday = tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 })))
  return {
    date = date,
    year = year,
    month = month,
    day = day,
    weekday = WEEKDAYS[weekday + 1],
  }
end

local function nth_weekday(day)
  local nth = math.floor((day - 1) / 7) + 1
  if nth > 4 then
    return -1
  end
  return nth
end

local function nth_label(nth)
  if nth == -1 then
    return '最終'
  end
  return '第' .. nth
end

local function weekday_labels(codes)
  local labels = {}
  for _, weekday in ipairs(WEEKDAYS) do
    for _, code in ipairs(codes or {}) do
      if code:gsub('^%-?%d+', '') == weekday.code then
        table.insert(labels, weekday.label)
        break
      end
    end
  end
  return labels
end

local function sorted_byday(codes)
  local sorted = {}
  for _, weekday in ipairs(WEEKDAYS) do
    for _, code in ipairs(codes or {}) do
      if code == weekday.code then
        table.insert(sorted, code)
        break
      end
    end
  end
  return sorted
end

local function end_suffix(config)
  if config.end_type == 'until' and config.until_date ~= nil then
    return string.format('（%s まで）', config.until_date)
  end
  if config.end_type == 'count' and config.count ~= nil then
    return string.format('（%d 回）', config.count)
  end
  return ''
end

local function base_label(config, parts)
  local interval = config.interval or 1
  local prefix
  if interval > 1 then
    prefix = string.format('%d%sごと', interval, UNIT_LABELS[config.freq] or '')
  else
    prefix = ({ DAILY = '毎日', WEEKLY = '毎週', MONTHLY = '毎月', YEARLY = '毎年' })[config.freq]
  end

  if config.freq == 'WEEKLY' then
    local labels = weekday_labels(config.byday)
    if #labels == 5 and table.concat(labels, ',') == '月,火,水,木,金' then
      return prefix .. ' 平日（月〜金）'
    end
    if #labels > 0 then
      return prefix .. ' ' .. table.concat(labels, '・') .. '曜日'
    end
  elseif config.freq == 'MONTHLY' then
    if config.byday ~= nil and #config.byday > 0 then
      local byday = config.byday[1]
      local nth, code = byday:match('^(%-?%d+)(%a%a)$')
      local weekday = WEEKDAY_BY_CODE[code]
      if nth ~= nil and weekday ~= nil then
        return prefix .. ' ' .. nth_label(tonumber(nth)) .. weekday.label .. '曜日'
      end
    end
    if config.bymonthday ~= nil then
      return prefix .. ' ' .. config.bymonthday .. '日'
    end
  elseif config.freq == 'YEARLY' then
    local month = config.bymonth or (parts and parts.month)
    local day = config.bymonthday or (parts and parts.day)
    if month ~= nil and day ~= nil then
      return prefix .. ' ' .. month .. '月' .. day .. '日'
    end
  end

  return prefix
end

local function normalize_config(config)
  if config == nil or config.freq == nil then
    return nil
  end

  local normalized = {
    freq = config.freq,
    interval = tonumber(config.interval) or 1,
    byday = config.byday and vim.deepcopy(config.byday) or nil,
    bymonth = tonumber(config.bymonth),
    bymonthday = tonumber(config.bymonthday),
    end_type = config.end_type or 'never',
    until_date = config.until_date,
    count = tonumber(config.count),
  }
  if normalized.end_type ~= 'until' then
    normalized.until_date = nil
  end
  if normalized.end_type ~= 'count' then
    normalized.count = nil
  end
  if normalized.freq ~= 'WEEKLY' and normalized.freq ~= 'MONTHLY' then
    normalized.byday = nil
  end
  if normalized.freq ~= 'YEARLY' then
    normalized.bymonth = nil
  end
  if normalized.freq ~= 'MONTHLY' and normalized.freq ~= 'YEARLY' then
    normalized.bymonthday = nil
  end
  return normalized
end

function M.presets(start)
  local parts = start_parts(start)
  if parts == nil then
    return {}
  end

  local weekday = parts.weekday
  local nth = nth_weekday(parts.day)
  return {
    { key = 'none', label = '繰り返さない', config = nil },
    { key = 'daily', label = '毎日', config = { freq = 'DAILY', interval = 1, end_type = 'never' } },
    {
      key = 'weekly',
      label = '毎週 ' .. weekday.label .. '曜日',
      config = { freq = 'WEEKLY', interval = 1, byday = { weekday.code }, end_type = 'never' },
    },
    {
      key = 'monthly',
      label = '毎月 ' .. nth_label(nth) .. weekday.label .. '曜日',
      config = { freq = 'MONTHLY', interval = 1, byday = { tostring(nth) .. weekday.code }, end_type = 'never' },
    },
    {
      key = 'yearly',
      label = string.format('毎年 %d月%d日', parts.month, parts.day),
      config = { freq = 'YEARLY', interval = 1, end_type = 'never' },
    },
    {
      key = 'weekdays',
      label = '毎週平日（月〜金）',
      config = { freq = 'WEEKLY', interval = 1, byday = { 'MO', 'TU', 'WE', 'TH', 'FR' }, end_type = 'never' },
    },
    { key = 'custom', label = 'カスタム...', config = nil },
  }
end

function M.key(config, all_day)
  local normalized = normalize_config(config)
  if normalized == nil then
    return ''
  end

  local parts = { 'FREQ=' .. normalized.freq }
  if normalized.interval ~= 1 then
    table.insert(parts, 'INTERVAL=' .. normalized.interval)
  end
  if normalized.byday ~= nil and #normalized.byday > 0 then
    if normalized.freq == 'WEEKLY' then
      table.insert(parts, 'BYDAY=' .. table.concat(sorted_byday(normalized.byday), ','))
    else
      table.insert(parts, 'BYDAY=' .. table.concat(normalized.byday, ','))
    end
  end
  if normalized.freq == 'YEARLY' and normalized.bymonth ~= nil and normalized.bymonthday ~= nil then
    table.insert(parts, 'BYMONTH=' .. normalized.bymonth)
    table.insert(parts, 'BYMONTHDAY=' .. normalized.bymonthday)
  elseif normalized.bymonthday ~= nil then
    table.insert(parts, 'BYMONTHDAY=' .. normalized.bymonthday)
  end
  if normalized.end_type == 'until' and normalized.until_date ~= nil then
    local until_value = normalized.until_date:gsub('%-', '')
    if not all_day then
      until_value = until_value .. 'T235959Z'
    end
    table.insert(parts, 'UNTIL=' .. until_value)
  elseif normalized.end_type == 'count' and normalized.count ~= nil then
    table.insert(parts, 'COUNT=' .. normalized.count)
  end
  return table.concat(parts, ';')
end

function M.to_api(config, all_day)
  local rule = M.key(config, all_day)
  if rule == '' then
    return {}
  end
  return { 'RRULE:' .. rule }
end

function M.parse(recurrence_array)
  if type(recurrence_array) ~= 'table' then
    return nil
  end

  local rule
  for _, value in ipairs(recurrence_array) do
    if type(value) == 'string' and value:match('^RRULE:') then
      rule = value:gsub('^RRULE:', '')
      break
    end
  end
  if rule == nil then
    return nil
  end

  local values = {}
  for part in rule:gmatch('[^;]+') do
    local key, value = part:match('^([^=]+)=(.*)$')
    if key ~= nil then
      values[key] = value
    end
  end

  local config = normalize_config({
    freq = values.FREQ,
    interval = tonumber(values.INTERVAL) or 1,
    byday = values.BYDAY and vim.split(values.BYDAY, ',', { plain = true }) or nil,
    bymonth = values.BYMONTH and tonumber(values.BYMONTH) or nil,
    bymonthday = values.BYMONTHDAY and tonumber(values.BYMONTHDAY) or nil,
    end_type = values.COUNT and 'count' or (values.UNTIL and 'until' or 'never'),
    until_date = values.UNTIL and values.UNTIL:sub(1, 8):gsub('(%d%d%d%d)(%d%d)(%d%d)', '%1-%2-%3') or nil,
    count = values.COUNT and tonumber(values.COUNT) or nil,
  })
  return config
end

function M.preset_key(config, start)
  local normalized = normalize_config(config)
  if normalized == nil then
    return 'none'
  end
  for _, preset in ipairs(M.presets(start)) do
    if preset.key ~= 'custom' and preset.key ~= 'none' and M.key(preset.config) == M.key(normalized) then
      return preset.key
    end
  end
  return 'custom'
end

function M.label(config, start)
  local normalized = normalize_config(config)
  if normalized == nil then
    return '繰り返さない'
  end
  local parts = start_parts(start)
  return base_label(normalized, parts) .. end_suffix(normalized)
end

function M.unit_label(freq)
  return UNIT_LABELS[freq] or ''
end

function M.end_label(end_type)
  return END_LABELS[end_type] or END_LABELS.never
end

function M.next_end_type(end_type)
  if end_type == 'until' then
    return 'count'
  elseif end_type == 'count' then
    return 'never'
  end
  return 'until'
end

function M.next_freq(freq)
  for index, candidate in ipairs(FREQS) do
    if candidate == freq then
      return FREQS[(index % #FREQS) + 1]
    end
  end
  return FREQS[1]
end

function M.weekday_text(byday)
  local labels = weekday_labels(byday)
  return table.concat(labels, ',')
end

function M.parse_weekday_text(text, start)
  local codes = {}
  for label in text:gmatch('[^,%s]+') do
    local weekday = WEEKDAY_BY_LABEL[label]
    if weekday ~= nil then
      table.insert(codes, weekday.code)
    end
  end
  if #codes == 0 then
    local parts = start_parts(start)
    if parts ~= nil then
      table.insert(codes, parts.weekday.code)
    end
  end
  return sorted_byday(codes)
end

function M.validate(config, start)
  if config == nil or config.freq == nil then
    return true, nil
  end
  if not vim.tbl_contains(FREQS, config.freq) then
    return false, 'Invalid recurrence frequency'
  end
  local interval = tonumber(config.interval)
  if interval == nil or interval < 1 or interval > 999 then
    return false, 'Recurrence interval must be between 1 and 999'
  end
  if config.freq == 'WEEKLY' then
    local codes = config.byday or {}
    if #codes == 0 then
      return false, 'Select at least one weekday'
    end
    for _, code in ipairs(codes) do
      if WEEKDAY_BY_CODE[code] == nil then
        return false, 'Invalid weekday'
      end
    end
  end
  if config.freq == 'MONTHLY' and config.byday ~= nil then
    for _, value in ipairs(config.byday) do
      local nth, code = value:match('^(%-?%d+)(%a%a)$')
      if nth == nil or WEEKDAY_BY_CODE[code] == nil then
        return false, 'Invalid monthly recurrence'
      end
    end
  end
  if config.freq == 'MONTHLY' and config.bymonthday ~= nil then
    local day = tonumber(config.bymonthday)
    if day == nil or day < 1 or day > 31 then
      return false, 'Monthly recurrence day must be between 1 and 31'
    end
  end
  if config.freq == 'YEARLY' and (config.bymonth ~= nil or config.bymonthday ~= nil) then
    local month = tonumber(config.bymonth)
    local day = tonumber(config.bymonthday)
    if month == nil or month < 1 or month > 12 then
      return false, 'Yearly recurrence month must be between 1 and 12'
    end
    if day == nil or day < 1 or day > calendar.days_in_month(2000, month) then
      return false, 'Yearly recurrence day is invalid for the selected month'
    end
  end
  if config.end_type == 'until' then
    if calendar.parse_date(config.until_date or '') == nil then
      return false, 'Recurrence end date must be in YYYY-MM-DD format'
    end
    local parts = start_parts(start)
    if parts ~= nil and config.until_date <= parts.date then
      return false, 'Recurrence end date must be after the start date'
    end
  elseif config.end_type == 'count' then
    local count = tonumber(config.count)
    if count == nil or count < 1 or count > 999 then
      return false, 'Recurrence count must be between 1 and 999'
    end
  end
  return true, nil
end

return M
