local config = require('google-calendar.config')
local event = require('google-calendar.event')

local M = {}

local MESSAGES = {
  not_found = 'gws was not found. Install gws by following the setup instructions in README.md.',
  auth = 'gws authentication has expired. Run gws auth login.',
  network = 'Cannot connect to Google Calendar. Check your network and retry with r.',
  invalid_output = 'Could not parse the output from gws',
  deleted = 'The event has already been deleted.',
}

local last_message = nil

local function api_message(err)
  local detail = err.message
  if type(detail) ~= 'string' or detail == '' then
    detail = 'Unknown error'
  end
  return 'Google Calendar API error: ' .. detail
end

local function message_for(err)
  if err.kind == 'api' then
    if err.code == 404 then
      return MESSAGES.deleted
    end
    return api_message(err)
  end

  return MESSAGES[err.kind] or 'Google Calendar operation failed'
end

function M.message(err)
  return event.sanitize(message_for(err))
end

function M.error(err)
  local full = event.sanitize(message_for(err))
  if full == last_message then
    return
  end
  last_message = full

  local notify = config.get().notify
  local shown = full
  if err.kind == 'api' then
    shown = event.truncate(full, vim.o.columns)
  end

  notify(shown, vim.log.levels.ERROR)
  if shown ~= full then
    notify(full, vim.log.levels.DEBUG)
  end
  if err.kind == 'invalid_output' and type(err.stderr) == 'string' and err.stderr ~= '' then
    notify(err.stderr, vim.log.levels.DEBUG)
  end
end

function M.reset()
  last_message = nil
end

return M
