local calendar = require('google-calendar.calendar')
local event = require('google-calendar.event')

local M = {}

local MINUTES_PER_DAY = 24 * 60
local NOW_STEP_MINUTES = 30

M.WEEKDAY_NAMES = { 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday' }
local WEEKDAY_LABELS = { '日', '月', '火', '水', '木', '金', '土' }

-- os.time はローカルのタイムゾーンと夏時間の影響を受けるため、暦の日数は算術で求める
local function day_number(date)
  local year, month, day = calendar.date_parts(date)
  year, month, day = assert(year), assert(month), assert(day)
  if month <= 2 then
    year = year - 1
  end
  local era = math.floor(year / 400)
  local year_of_era = year - era * 400
  local day_of_year = math.floor((153 * ((month + 9) % 12) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
  return era * 146097 + day_of_era - 719468
end

local function weekday_index(date)
  -- 1970-01-01 は木曜日
  return (day_number(date) + 4) % 7
end

local function clock_minutes(time)
  local hour, minute = time:match('^(%d%d):(%d%d)$')
  return tonumber(hour) * 60 + tonumber(minute)
end

local function format_clock(minutes)
  return string.format('%02d:%02d', math.floor(minutes / 60), minutes % 60)
end

local function to_minutes(date, time)
  return day_number(date) * MINUTES_PER_DAY + clock_minutes(time)
end

local function declined_by_self(item)
  if type(item.attendees) ~= 'table' then
    return false
  end
  for _, attendee in ipairs(item.attendees) do
    if type(attendee) == 'table' and attendee.self == true and attendee.responseStatus == 'declined' then
      return true
    end
  end
  return false
end

function M.is_busy(item)
  if event.is_all_day(item) then
    return false
  end
  if type(item.start) ~= 'table' or type(item.start.dateTime) ~= 'string' then
    return false
  end
  if type(item['end']) ~= 'table' or type(item['end'].dateTime) ~= 'string' then
    return false
  end
  if item.status == 'cancelled' or item.transparency == 'transparent' then
    return false
  end
  return not declined_by_self(item)
end

---予定の開始・終了をローカル時刻の分単位の通し番号で返す
function M.event_minutes(item, local_offset)
  local start_date, start_time = event.local_datetime(item.start.dateTime, local_offset)
  local end_date, end_time = event.local_datetime(item['end'].dateTime, local_offset)
  if start_date == nil or end_date == nil then
    return nil
  end
  return to_minutes(start_date, start_time), to_minutes(end_date, end_time)
end

function M.day_start_minutes(date)
  return day_number(date) * MINUTES_PER_DAY
end

local function busy_intervals(events, buffer, local_offset)
  local intervals = {}
  for _, item in ipairs(events) do
    if M.is_busy(item) then
      local start, finish = M.event_minutes(item, local_offset)
      if start ~= nil then
        table.insert(intervals, { start - buffer, finish + buffer })
      end
    end
  end
  table.sort(intervals, function(a, b)
    return a[1] < b[1]
  end)
  return intervals
end

local function free_ranges(intervals, window_start, window_end, duration)
  local ranges = {}
  local cursor = window_start
  for _, interval in ipairs(intervals) do
    if interval[2] > cursor and interval[1] < window_end then
      if interval[1] - cursor >= duration then
        table.insert(ranges, { cursor, interval[1] })
      end
      cursor = math.max(cursor, interval[2])
    end
  end
  if window_end - cursor >= duration then
    table.insert(ranges, { cursor, window_end })
  end
  return ranges
end

---@class GoogleCalendarSlotSearch
---@field dates string[] 対象の日付 (YYYY-MM-DD)
---@field time_range { start: string, finish: string } 探索する時間帯 (HH:MM)
---@field duration integer 所要時間 (分)
---@field buffer integer 埋まっている予定の前後に空ける時間 (分)
---@field now string 現在時刻 (YYYY-MM-DD HH:MM)
---@field local_offset? string 表示に使うオフセット (+0900 など)

---@param events table[] 予定モデルの配列
---@param opts GoogleCalendarSlotSearch
---@return { date: string, start: string, finish: string }[]
function M.find(events, opts)
  local intervals = busy_intervals(events, opts.buffer, opts.local_offset)
  local now_date, now_time = opts.now:match('^(%S+) (%S+)$')
  local earliest = math.ceil(to_minutes(now_date, now_time) / NOW_STEP_MINUTES) * NOW_STEP_MINUTES

  local dates = vim.deepcopy(opts.dates)
  table.sort(dates)

  local result = {}
  for _, date in ipairs(dates) do
    if date >= now_date then
      local day_start = M.day_start_minutes(date)
      local window_start = day_start + clock_minutes(opts.time_range.start)
      local window_end = day_start + clock_minutes(opts.time_range.finish)
      if date == now_date then
        window_start = math.max(window_start, earliest)
      end

      for _, range in ipairs(free_ranges(intervals, window_start, window_end, opts.duration)) do
        table.insert(result, {
          date = date,
          start = format_clock(range[1] - day_start),
          finish = format_clock(range[2] - day_start),
        })
      end
    end
  end
  return result
end

local function short_label(date)
  local _, month, day = calendar.date_parts(date)
  return string.format('%02d/%02d(%s)', month, day, WEEKDAY_LABELS[weekday_index(date) + 1])
end

function M.week_options(today, week_start, count)
  local start_index = week_start == 'monday' and 1 or 0
  local first = calendar.add_days(today, -((weekday_index(today) - start_index + 7) % 7))

  local weeks = {}
  for index = 0, count - 1 do
    local start_date = calendar.add_days(first, index * 7)
    local end_date = calendar.add_days(start_date, 6)
    table.insert(weeks, {
      start_date = start_date,
      end_date = end_date,
      label = short_label(start_date) .. '~' .. short_label(end_date),
    })
  end
  return weeks
end

function M.target_dates(weeks, weekdays)
  local allowed = {}
  for _, name in ipairs(weekdays) do
    allowed[name] = true
  end

  local dates = {}
  for _, week in ipairs(weeks) do
    for offset = 0, 6 do
      local date = calendar.add_days(week.start_date, offset)
      if allowed[M.WEEKDAY_NAMES[weekday_index(date) + 1]] then
        table.insert(dates, date)
      end
    end
  end
  table.sort(dates)
  return dates
end

function M.date_label(date)
  return date:gsub('%-', '/') .. '(' .. WEEKDAY_LABELS[weekday_index(date) + 1] .. ')'
end

function M.format(found, opts)
  opts = opts or {}
  local lines = {}
  for _, slot in ipairs(found) do
    local date = opts.weekday and M.date_label(slot.date) or slot.date:gsub('%-', '/')
    table.insert(lines, string.format('%s %s ~ %s', date, slot.start, slot.finish))
  end
  return lines
end

function M.parse_time_range(value)
  if type(value) ~= 'string' then
    return nil
  end
  local start_hour, start_minute, end_hour, end_minute = value:match('^(%d%d):(%d%d)%-(%d%d):(%d%d)$')
  if start_hour == nil then
    return nil
  end
  start_hour, start_minute = tonumber(start_hour), tonumber(start_minute)
  end_hour, end_minute = tonumber(end_hour), tonumber(end_minute)
  if start_hour > 23 or start_minute > 59 or end_minute > 59 then
    return nil
  end
  if end_hour > 24 or (end_hour == 24 and end_minute > 0) then
    return nil
  end
  if start_hour * 60 + start_minute >= end_hour * 60 + end_minute then
    return nil
  end
  return { start = value:sub(1, 5), finish = value:sub(7, 11) }
end

function M.duration_label(minutes)
  local hours = math.floor(minutes / 60)
  local rest = minutes % 60
  if hours == 0 then
    return rest .. '分'
  end
  if rest == 0 then
    return hours .. '時間'
  end
  return hours .. '時間' .. rest .. '分'
end

return M
