local M = {}

local days_by_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local weekday_labels_by_start = {
  sunday = { '日', '月', '火', '水', '木', '金', '土' },
  monday = { '月', '火', '水', '木', '金', '土', '日' },
}

local function is_leap_year(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function weekday_of(year, month, day)
  return tonumber(os.date('%w', os.time({ year = year, month = month, day = day, hour = 12 })))
end

local function week_start_index(week_start)
  if week_start == 'monday' then
    return 1
  end
  return 0
end

function M.parse_month(value)
  local year, month = value:match('^(%d%d%d%d)%-(%d%d)$')
  if year == nil then
    return nil
  end

  year, month = tonumber(year), tonumber(month)
  if month < 1 or month > 12 then
    return nil
  end

  return year, month
end

function M.days_in_month(year, month)
  if month == 2 and is_leap_year(year) then
    return 29
  end
  return days_by_month[month]
end

function M.date_parts(date)
  local year, month, day = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if year == nil then
    return nil
  end
  return tonumber(year), tonumber(month), tonumber(day)
end

function M.parse_date(value)
  local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if year == nil then
    return nil
  end

  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if month < 1 or month > 12 then
    return nil
  end
  if day < 1 or day > M.days_in_month(year, month) then
    return nil
  end

  return year, month, day
end

function M.parse_datetime(value)
  local date, hour, minute = value:match('^(%d%d%d%d%-%d%d%-%d%d) (%d%d):(%d%d)$')
  if date == nil then
    return nil
  end

  local year, month, day = M.parse_date(date)
  if year == nil then
    return nil
  end

  hour, minute = tonumber(hour), tonumber(minute)
  if hour > 23 or minute > 59 then
    return nil
  end

  return year, month, day, hour, minute
end

function M.today()
  return os.date('%Y-%m-%d')
end

---@param date string
---@param delta integer
---@return string
function M.add_days(date, delta)
  local year, month, day = M.date_parts(date)
  local epoch = os.time({
    year = assert(year),
    month = assert(month),
    day = assert(day) + delta,
    hour = 12,
  })
  return tostring(os.date('%Y-%m-%d', epoch))
end

function M.add_months(year, month, delta)
  local total = year * 12 + (month - 1) + delta
  return math.floor(total / 12), total % 12 + 1
end

function M.clamp_day(year, month, day)
  return math.min(day, M.days_in_month(year, month))
end

function M.format_month_title(year, month)
  return string.format('%d年%d月', year, month)
end

function M.weekday_labels(week_start)
  return weekday_labels_by_start[week_start] or weekday_labels_by_start.sunday
end

function M.grid_start(year, month, week_start)
  local first = string.format('%04d-%02d-01', year, month)
  local offset = (weekday_of(year, month, 1) - week_start_index(week_start) + 7) % 7
  return M.add_days(first, -offset)
end

function M.month_grid(year, month, week_start)
  local start_date = M.grid_start(year, month, week_start)
  local start_index = week_start_index(week_start)
  local weeks = {}

  for week_index = 0, 5 do
    local week = {}
    for day_index = 0, 6 do
      local date = M.add_days(start_date, week_index * 7 + day_index)
      local cell_year, cell_month, cell_day = M.date_parts(date)
      week[day_index + 1] = {
        date = date,
        day = cell_day,
        in_month = cell_year == year and cell_month == month,
        weekday = (start_index + day_index) % 7,
      }
    end
    weeks[week_index + 1] = week
  end

  return { year = year, month = month, weeks = weeks }
end

function M.rfc3339(date, time)
  local year, month, day = M.date_parts(date)
  local hour, minute, second = (time or '00:00:00'):match('^(%d%d):(%d%d):(%d%d)$')
  if hour == nil then
    hour, minute = (time or '00:00'):match('^(%d%d):(%d%d)$')
    second = '00'
  end
  local epoch = os.time({
    year = assert(year),
    month = assert(month),
    day = assert(day),
    hour = assert(tonumber(hour)),
    min = assert(tonumber(minute)),
    sec = assert(tonumber(second)),
  })
  local offset = tostring(os.date('%z', epoch))
  local sign, offset_hour, offset_minute = offset:match('^([%+%-])(%d%d)(%d%d)$')

  return string.format(
    '%04d-%02d-%02dT%s:%s:%s%s%s:%s',
    year,
    month,
    day,
    hour,
    minute,
    second,
    sign,
    offset_hour,
    offset_minute
  )
end

function M.fetch_range(year, month, week_start)
  local start_date = M.grid_start(year, month, week_start)
  local end_date = M.add_days(start_date, 42)
  return start_date, end_date, M.rfc3339(start_date), M.rfc3339(end_date)
end

return M
