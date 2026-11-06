local M = {}

local entries = {}
local primary_entry = nil
local loaded = false
local loading = false
local waiters = {}

local function present(value)
  if value == nil or value == vim.NIL then
    return nil
  end
  return value
end

local function normalize_entry(raw)
  if type(raw) ~= 'table' then
    return nil
  end
  local id = present(raw.id)
  if type(id) ~= 'string' or id == '' then
    return nil
  end
  return {
    id = id,
    summary = present(raw.summaryOverride) or present(raw.summary),
    primary = raw.primary == true,
  }
end

function M.set(items)
  entries = {}
  primary_entry = nil
  loaded = true
  for _, raw in ipairs(items or {}) do
    local entry = normalize_entry(raw)
    if entry ~= nil then
      entries[entry.id] = entry
      if entry.primary then
        primary_entry = entry
      end
    end
  end
end

function M.get(calendar_id)
  if type(calendar_id) ~= 'string' or calendar_id == '' then
    return nil
  end
  if calendar_id == 'primary' then
    return primary_entry or entries.primary
  end
  return entries[calendar_id]
end

function M.label(calendar_id)
  if type(calendar_id) ~= 'string' or calendar_id == '' then
    return nil
  end
  local entry = M.get(calendar_id)
  if entry == nil then
    return calendar_id
  end
  local email = entry.id
  local name = entry.summary
  if name == nil or name == '' or name == email or name == 'primary' then
    return email
  end
  return email .. ' (' .. name .. ')'
end

function M.reset()
  entries = {}
  primary_entry = nil
  loaded = false
  loading = false
  waiters = {}
end

function M.is_loaded()
  return loaded
end

function M.ensure_loaded(callback)
  if loaded then
    if callback ~= nil then
      callback(true)
    end
    return
  end
  if callback ~= nil then
    table.insert(waiters, callback)
  end
  if loading then
    return
  end

  loading = true
  local gws = require('google-calendar.gws')
  if type(gws.list_calendars) ~= 'function' then
    loading = false
    local callbacks = waiters
    waiters = {}
    for _, waiter in ipairs(callbacks) do
      waiter(false)
    end
    return
  end

  gws.list_calendars(function(items, err)
    loading = false
    if err == nil then
      M.set(items or {})
    end
    local callbacks = waiters
    waiters = {}
    for _, waiter in ipairs(callbacks) do
      waiter(err == nil)
    end
  end)
end

return M
