local M = {}

-- 更新時に保持する API フィールド。events update は PUT のため、送らないフィールドは消える
local EDITABLE_FIELDS = {
  'attendees',
  'reminders',
  'colorId',
  'visibility',
  'transparency',
  'conferenceData',
}

local function present(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  return value
end

local function parse_offset(value)
  local sign, hours, minutes = value:match('^([+-])(%d%d):(%d%d)$')
  if sign == nil then
    sign, hours, minutes = value:match('^([+-])(%d%d)(%d%d)$')
  end
  if sign == nil then
    return nil
  end

  local offset = tonumber(hours) * 3600 + tonumber(minutes) * 60
  if sign == '-' then
    offset = -offset
  end
  return offset
end

local function local_offset()
  return parse_offset(os.date('%z')) or 0
end

local function parse_rfc3339(value)
  local year, month, day, hour, minute, second, rest =
    value:match('^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$')
  if year == nil then
    return nil
  end

  rest = rest:gsub('^%.%d+', '')
  local offset
  if rest == 'Z' or rest == 'z' then
    offset = 0
  else
    offset = parse_offset(rest)
    if offset == nil then
      return nil
    end
  end

  return {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    minute = tonumber(minute),
    second = tonumber(second),
    offset = offset,
  }
end

local function format_offset(offset)
  local sign = '+'
  if offset < 0 then
    sign = '-'
    offset = -offset
  end
  return string.format('%s%02d:%02d', sign, math.floor(offset / 3600), math.floor((offset % 3600) / 60))
end

local function to_local_datetime(value, display_offset)
  local parsed = parse_rfc3339(value)
  if parsed == nil then
    return value
  end

  -- os.time() はローカル時刻として解釈するため、イベントのオフセットとの差を足して UTC エポックにする
  local epoch = os.time({
    year = parsed.year,
    month = parsed.month,
    day = parsed.day,
    hour = parsed.hour,
    min = parsed.minute,
    sec = parsed.second,
  }) + local_offset() - parsed.offset

  -- os.date('!') は UTC として整形する。ローカル時刻のエポックを渡すことでタイムゾーン設定に依存しない
  local local_time = os.date('!*t', epoch + display_offset)
  return string.format(
    '%04d-%02d-%02dT%02d:%02d:%02d%s',
    local_time.year,
    local_time.month,
    local_time.day,
    local_time.hour,
    local_time.min,
    local_time.sec,
    format_offset(display_offset)
  )
end

local function normalize_time(raw_time, display_offset)
  if type(raw_time) ~= 'table' then
    return nil
  end

  local normalized = {}
  local date = present(raw_time.date)
  local date_time = present(raw_time.dateTime)
  if date ~= nil then
    normalized.date = date
  elseif date_time ~= nil then
    normalized.dateTime = to_local_datetime(date_time, display_offset)
  else
    return nil
  end

  local time_zone = present(raw_time.timeZone)
  if time_zone ~= nil then
    normalized.timeZone = time_zone
  end
  return normalized
end

function M.extract_hangout_link(raw)
  local hangout_link = present(raw.hangoutLink)
  if hangout_link ~= nil then
    return hangout_link
  end

  local conference_data = present(raw.conferenceData)
  if type(conference_data) ~= 'table' then
    return nil
  end

  local entry_points = present(conference_data.entryPoints)
  if type(entry_points) ~= 'table' then
    return nil
  end

  for _, entry_point in ipairs(entry_points) do
    if entry_point.entryPointType == 'video' then
      local uri = present(entry_point.uri)
      if uri ~= nil then
        return uri
      end
    end
  end
  return nil
end

function M.normalize(raw, opts)
  opts = opts or {}
  local display_offset = local_offset()
  local model = {
    id = present(raw.id),
    summary = present(raw.summary),
    location = present(raw.location),
    description = present(raw.description),
    start = normalize_time(raw.start, display_offset),
    ['end'] = normalize_time(raw['end'], display_offset),
    hangout_link = M.extract_hangout_link(raw),
    calendar_id = present(opts.calendar_id),
    status = present(raw.status),
  }

  for _, field in ipairs(EDITABLE_FIELDS) do
    local value = present(raw[field])
    if value ~= nil then
      model[field] = value
    end
  end
  return model
end

function M.normalize_list(items, opts)
  local events = {}
  for _, raw in ipairs(items) do
    table.insert(events, M.normalize(raw, opts))
  end
  return events
end

function M.update_body(fields)
  local body = {}
  for _, field in ipairs({ 'summary', 'location', 'description', 'start', 'end' }) do
    local value = present(fields[field])
    if value ~= nil then
      body[field] = value
    end
  end
  for _, field in ipairs(EDITABLE_FIELDS) do
    local value = present(fields[field])
    if value ~= nil then
      body[field] = value
    end
  end
  return body
end

return M
