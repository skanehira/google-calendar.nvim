local config = require('google-calendar.config')
local event = require('google-calendar.event')

local M = {}

local TIMEOUT_MS = 30000
local MAX_PAGES = 10
local PAGE_SIZE = 2500

local function cache_dir()
  local dir = vim.fn.stdpath('cache') .. '/google-calendar.nvim'
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

local function default_calendar_id()
  local calendars = config.get().calendars
  if type(calendars) == 'table' and calendars[1] ~= nil then
    return calendars[1]
  end
  return 'primary'
end

local function first_chars(value, count)
  if type(value) ~= 'string' then
    return ''
  end
  return vim.fn.strcharpart(value, 0, count)
end

local function decode_stdout(stdout)
  if type(stdout) ~= 'string' or stdout == '' then
    return nil
  end

  local ok, body = pcall(vim.json.decode, stdout)
  if not ok then
    return nil
  end
  return body
end

function M.classify(out)
  if out.code == 124 then
    return nil, { kind = 'network', message = 'timeout' }
  end

  local body = decode_stdout(out.stdout)
  if out.code == 0 then
    if type(body) ~= 'table' then
      return nil,
        {
          kind = 'invalid_output',
          output = first_chars(out.stdout, 200),
          stderr = out.stderr or '',
        }
    end
    return body, nil
  end

  local error_body = nil
  if type(body) == 'table' then
    error_body = body.error
    if error_body == vim.NIL then
      error_body = nil
    end
  end
  if out.code == 2 and type(error_body) == 'table' and error_body.reason == 'authError' then
    return nil, { kind = 'auth', message = error_body.message }
  end
  if type(error_body) == 'table' then
    return nil,
      {
        kind = 'api',
        code = error_body.code,
        message = error_body.message,
        reason = error_body.reason,
      }
  end
  return nil,
    {
      kind = 'invalid_output',
      output = first_chars(out.stdout, 200),
      stderr = out.stderr or '',
    }
end

local function execute(args, callback)
  local cmd = config.get().gws_cmd
  if vim.fn.executable(cmd) == 0 then
    callback(nil, { kind = 'not_found', command = cmd })
    return
  end

  local argv = { cmd }
  vim.list_extend(argv, args)
  vim.list_extend(argv, { '--format', 'json' })

  local ok = pcall(vim.system, argv, {
    cwd = cache_dir(),
    text = true,
    timeout = TIMEOUT_MS,
  }, function(out)
    local body, err = M.classify(out)
    if err ~= nil then
      callback(nil, err)
    else
      callback(body, nil)
    end
  end)

  if not ok then
    callback(nil, { kind = 'not_found', command = cmd })
  end
end

function M.list_events(opts, callback)
  opts = opts or {}
  local calendar_id = opts.calendar_id or default_calendar_id()
  local params = {
    calendarId = calendar_id,
    singleEvents = true,
    maxResults = PAGE_SIZE,
  }
  if opts.time_min ~= nil then
    params.timeMin = opts.time_min
  end
  if opts.time_max ~= nil then
    params.timeMax = opts.time_max
  end

  local collected = {}

  local function fetch_page(pages)
    execute({ 'calendar', 'events', 'list', '--params', vim.json.encode(params) }, function(body, err)
      if err ~= nil then
        callback(nil, err)
        return
      end

      local items = body.items
      if items == nil or items == vim.NIL then
        items = {}
      end
      if type(items) ~= 'table' then
        callback(nil, { kind = 'invalid_output', output = first_chars(vim.json.encode(body), 200) })
        return
      end
      vim.list_extend(collected, items)

      local next_page_token = body.nextPageToken
      if next_page_token == nil or next_page_token == vim.NIL then
        callback(event.normalize_list(collected, { calendar_id = calendar_id }), nil)
        return
      end

      if pages >= MAX_PAGES then
        local notify = config.get().notify
        if notify ~= nil then
          notify(
            'google-calendar.nvim: 予定の取得が '
              .. MAX_PAGES
              .. ' ページを超えたため打ち切りました',
            vim.log.levels.WARN
          )
        end
        callback(event.normalize_list(collected, { calendar_id = calendar_id }), nil)
        return
      end

      params.pageToken = next_page_token
      fetch_page(pages + 1)
    end)
  end

  fetch_page(1)
end

function M.create_event(fields, callback)
  local calendar_id = fields.calendar_id or default_calendar_id()

  if fields.all_day then
    local params = { calendarId = calendar_id }
    local body = {
      summary = fields.summary,
      start = { date = fields.start },
      ['end'] = { date = fields['end'] },
    }
    if fields.location ~= nil and fields.location ~= '' then
      body.location = fields.location
    end
    if fields.description ~= nil and fields.description ~= '' then
      body.description = fields.description
    end

    execute({
      'calendar',
      'events',
      'insert',
      '--params',
      vim.json.encode(params),
      '--json',
      vim.json.encode(body),
    }, function(response, err)
      if err ~= nil then
        callback(nil, err)
        return
      end
      callback(event.normalize(response, { calendar_id = calendar_id }), nil)
    end)
    return
  end

  local args = {
    'calendar',
    '+insert',
    '--calendar',
    calendar_id,
    '--summary',
    fields.summary,
    '--start',
    fields.start,
    '--end',
    fields['end'],
  }
  if fields.location ~= nil and fields.location ~= '' then
    vim.list_extend(args, { '--location', fields.location })
  end
  if fields.description ~= nil and fields.description ~= '' then
    vim.list_extend(args, { '--description', fields.description })
  end
  if fields.meet then
    table.insert(args, '--meet')
  end

  execute(args, function(response, err)
    if err ~= nil then
      callback(nil, err)
      return
    end
    callback(event.normalize(response, { calendar_id = calendar_id }), nil)
  end)
end

function M.get_event(event_id, callback)
  local calendar_id = default_calendar_id()
  local params = { calendarId = calendar_id, eventId = event_id }
  execute({ 'calendar', 'events', 'get', '--params', vim.json.encode(params) }, function(response, err)
    if err ~= nil then
      callback(nil, err)
      return
    end
    callback(event.normalize(response, { calendar_id = calendar_id }), nil)
  end)
end

function M.update_event(fields, callback)
  local calendar_id = fields.calendar_id or default_calendar_id()
  local params = { calendarId = calendar_id, eventId = fields.id }
  if fields.conferenceData ~= nil then
    params.conferenceDataVersion = 1
  end

  execute({
    'calendar',
    'events',
    'update',
    '--params',
    vim.json.encode(params),
    '--json',
    vim.json.encode(event.update_body(fields)),
  }, function(response, err)
    if err ~= nil then
      callback(nil, err)
      return
    end
    callback(event.normalize(response, { calendar_id = calendar_id }), nil)
  end)
end

function M.delete_event(event_id, callback)
  local calendar_id = default_calendar_id()
  local params = { calendarId = calendar_id, eventId = event_id }
  execute({ 'calendar', 'events', 'delete', '--params', vim.json.encode(params) }, function(_, err)
    if err ~= nil then
      callback(nil, err)
      return
    end
    callback(true, nil)
  end)
end

return M
