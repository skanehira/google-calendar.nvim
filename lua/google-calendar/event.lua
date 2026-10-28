local calendar = require('google-calendar.calendar')

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
  }) + (parse_offset(os.date('%z')) or 0) - parsed.offset

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

-- 正規化済みのモデルは hangout_link を持つが、生の JSON を渡された場合に備えて conferenceData も見る
function M.meet_url(item)
  local url = present(item.hangout_link)
  if url ~= nil and url ~= '' then
    return url
  end

  url = M.extract_hangout_link(item)
  if url == nil or url == '' then
    return nil
  end

  return url
end

function M.normalize(raw, opts)
  opts = opts or {}
  local display_offset = parse_offset(os.date('%z')) or 0
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

-- events update は PUT のため、送らなかったフィールドは消える。取得した予定をベースに、変更分だけを上書きする
function M.merge_update(base, changes)
  local fields = {
    id = base.id,
    calendar_id = base.calendar_id,
    summary = base.summary,
    location = base.location,
    description = base.description,
    start = base.start,
    ['end'] = base['end'],
  }

  for _, field in ipairs(EDITABLE_FIELDS) do
    local value = present(base[field])
    if value ~= nil then
      fields[field] = value
    end
  end

  for key, value in pairs(changes or {}) do
    fields[key] = value
  end

  return fields
end

-- 以下は月表示 (#11) が使うローカル時刻・表示幅の整形
function M.local_datetime(value, local_offset)
  local parsed = parse_rfc3339(value)
  if parsed == nil then
    return nil
  end

  local display_offset = parse_offset(local_offset or os.date('%z'))
  if display_offset == nil then
    display_offset = 0
  end

  local epoch = os.time({
    year = parsed.year,
    month = parsed.month,
    day = parsed.day,
    hour = parsed.hour,
    min = parsed.minute,
    sec = parsed.second,
  }) + (parse_offset(os.date('%z')) or 0) - parsed.offset

  local local_time = os.date('!*t', epoch + display_offset)
  return string.format('%04d-%02d-%02d', local_time.year, local_time.month, local_time.day),
    string.format('%02d:%02d', local_time.hour, local_time.min)
end

function M.is_all_day(item)
  return item.start ~= nil and item.start.date ~= nil
end

function M.start_date(item, local_offset)
  if M.is_all_day(item) then
    return item.start.date
  end

  local date = M.local_datetime(item.start.dateTime, local_offset)
  return date
end

function M.start_time(item, local_offset)
  if M.is_all_day(item) then
    return nil
  end

  local _, time = M.local_datetime(item.start.dateTime, local_offset)
  return time
end

function M.end_time(item, local_offset)
  local finish = item['end']
  if type(finish) ~= 'table' or present(finish.dateTime) == nil then
    return nil
  end

  local _, time = M.local_datetime(finish.dateTime, local_offset)
  return time
end

function M.time_range(item, local_offset)
  if M.is_all_day(item) then
    return '終日'
  end

  local start = M.start_time(item, local_offset)
  local finish = M.end_time(item, local_offset)
  if start == nil then
    return nil
  end
  if finish == nil then
    return start
  end

  return start .. '-' .. finish
end

function M.display_datetime(time, local_offset)
  if type(time) ~= 'table' then
    return nil
  end

  local date = present(time.date)
  if date ~= nil then
    return date
  end

  local date_time = present(time.dateTime)
  if date_time == nil then
    return nil
  end

  local local_date, local_time = M.local_datetime(date_time, local_offset)
  if local_date == nil then
    return nil
  end

  return local_date .. ' ' .. local_time
end

function M.description_lines(description, max_lines)
  if description == nil or description == '' then
    return nil
  end

  local lines = vim.split(description, '\n', { plain = true })
  if #lines > max_lines then
    lines = vim.list_slice(lines, 1, max_lines)
    lines[max_lines] = lines[max_lines] .. '…'
  end

  return lines
end

function M.sanitize(text)
  local sanitized = (text or ''):gsub('[\r\n]+', ' ')
  return sanitized
end

function M.truncate(text, width)
  if width <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  -- … の表示幅 1 を確保してから文字を足す
  local limit = width - 1
  local result = ''
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    if vim.fn.strdisplaywidth(result .. char) > limit then
      break
    end
    result = result .. char
  end

  return result .. '…'
end

function M.chip_parts(item, width, local_offset)
  local prefix
  if M.is_all_day(item) then
    prefix = '終日 '
  else
    prefix = M.start_time(item, local_offset) .. ' '
  end

  local available = width - vim.fn.strdisplaywidth(prefix)
  if available < 0 then
    available = 0
  end

  return prefix, M.truncate(M.sanitize(item.summary), available)
end

function M.chip(item, width, local_offset)
  local prefix, title = M.chip_parts(item, width, local_offset)
  return prefix .. title
end

local function sort_day_events(list, local_offset)
  local indexed = {}
  for index, item in ipairs(list) do
    indexed[index] = { item = item, index = index }
  end

  table.sort(indexed, function(left, right)
    local left_all_day = M.is_all_day(left.item)
    local right_all_day = M.is_all_day(right.item)
    if left_all_day ~= right_all_day then
      return left_all_day
    end

    if not left_all_day then
      local left_time = M.start_time(left.item, local_offset)
      local right_time = M.start_time(right.item, local_offset)
      if left_time ~= right_time then
        return left_time < right_time
      end
    end

    return left.index < right.index
  end)

  local sorted = {}
  for index, entry in ipairs(indexed) do
    sorted[index] = entry.item
  end
  return sorted
end

function M.events_by_date(events, first_date, last_date, local_offset)
  local by_date = {}

  for _, item in ipairs(events) do
    if M.is_all_day(item) then
      local start_date = item.start.date
      local end_date = (item['end'] and item['end'].date) or calendar.add_days(start_date, 1)
      if end_date <= start_date then
        end_date = calendar.add_days(start_date, 1)
      end

      local date = start_date
      while date < end_date do
        if date >= first_date and date <= last_date then
          by_date[date] = by_date[date] or {}
          table.insert(by_date[date], item)
        end
        date = calendar.add_days(date, 1)
      end
    else
      local date = M.start_date(item, local_offset)
      if date ~= nil and date >= first_date and date <= last_date then
        by_date[date] = by_date[date] or {}
        table.insert(by_date[date], item)
      end
    end
  end

  for date, list in pairs(by_date) do
    by_date[date] = sort_day_events(list, local_offset)
  end

  return by_date
end

return M
