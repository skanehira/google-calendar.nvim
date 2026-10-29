local config = require('google-calendar.config')

local M = {}

local PALETTE_SIZE = 11

local function calendar_index(calendar_id)
  local calendars = config.get().calendars
  if type(calendars) == 'table' then
    for index, id in ipairs(calendars) do
      if id == calendar_id then
        return ((index - 1) % PALETTE_SIZE) + 1
      end
    end
  end

  local id = calendar_id or 'primary'
  local hash = 0
  for index = 1, #id do
    hash = (hash * 31 + string.byte(id, index)) % PALETTE_SIZE
  end
  return hash + 1
end

function M.dot_group(calendar_id)
  return 'GoogleCalendarCalendarColor' .. calendar_index(calendar_id)
end

function M.bar_group(calendar_id)
  return 'GoogleCalendarCalendarBg' .. calendar_index(calendar_id)
end

return M
