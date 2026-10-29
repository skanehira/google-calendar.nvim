local M = {}

local default_highlights = {
  GoogleCalendarHeader = { fg = '#7aa2f7', bold = true },
  GoogleCalendarToday = { fg = '#e0af68', bold = true },
  GoogleCalendarSelected = { fg = '#ff9e64', bold = true },
  GoogleCalendarSelectedBorder = { fg = '#ff9e64', bold = true },
  GoogleCalendarSunday = { fg = '#f7768e' },
  GoogleCalendarSaturday = { fg = '#7dcfff' },
  GoogleCalendarOtherMonth = { fg = '#565f89' },
  -- 予定チップは背景を付けず、通常の文字色で表示する
  GoogleCalendarEvent = {},
  GoogleCalendarEventTime = { fg = '#bb9af7' },
  GoogleCalendarEventColor1 = { fg = '#bb9af7' },
  GoogleCalendarEventColor2 = { fg = '#9ece6a' },
  GoogleCalendarEventColor3 = { fg = '#9d7cd8' },
  GoogleCalendarEventColor4 = { fg = '#f7768e' },
  GoogleCalendarEventColor5 = { fg = '#e0af68' },
  GoogleCalendarEventColor6 = { fg = '#ff9e64' },
  GoogleCalendarEventColor7 = { fg = '#7dcfff' },
  GoogleCalendarEventColor8 = { fg = '#565f89' },
  GoogleCalendarEventColor9 = { fg = '#7aa2f7' },
  GoogleCalendarEventColor10 = { fg = '#41a6b5' },
  GoogleCalendarEventColor11 = { fg = '#db4b4b' },
  GoogleCalendarCalendarColor1 = { fg = '#7aa2f7' },
  GoogleCalendarCalendarColor2 = { fg = '#e0af68' },
  GoogleCalendarCalendarColor3 = { fg = '#9ece6a' },
  GoogleCalendarCalendarColor4 = { fg = '#f7768e' },
  GoogleCalendarCalendarColor5 = { fg = '#bb9af7' },
  GoogleCalendarCalendarColor6 = { fg = '#ff9e64' },
  GoogleCalendarCalendarColor7 = { fg = '#7dcfff' },
  GoogleCalendarCalendarColor8 = { fg = '#41a6b5' },
  GoogleCalendarCalendarColor9 = { fg = '#9d7cd8' },
  GoogleCalendarCalendarColor10 = { fg = '#db4b4b' },
  GoogleCalendarCalendarColor11 = { fg = '#565f89' },
  GoogleCalendarCalendarBg1 = { fg = '#ffffff', bg = '#7aa2f7' },
  GoogleCalendarCalendarBg2 = { fg = '#ffffff', bg = '#e0af68' },
  GoogleCalendarCalendarBg3 = { fg = '#ffffff', bg = '#9ece6a' },
  GoogleCalendarCalendarBg4 = { fg = '#ffffff', bg = '#f7768e' },
  GoogleCalendarCalendarBg5 = { fg = '#ffffff', bg = '#bb9af7' },
  GoogleCalendarCalendarBg6 = { fg = '#ffffff', bg = '#ff9e64' },
  GoogleCalendarCalendarBg7 = { fg = '#ffffff', bg = '#7dcfff' },
  GoogleCalendarCalendarBg8 = { fg = '#ffffff', bg = '#41a6b5' },
  GoogleCalendarCalendarBg9 = { fg = '#ffffff', bg = '#9d7cd8' },
  GoogleCalendarCalendarBg10 = { fg = '#ffffff', bg = '#db4b4b' },
  GoogleCalendarCalendarBg11 = { fg = '#ffffff', bg = '#565f89' },
  GoogleCalendarDetailTitle = { fg = '#e0e6ea', bold = true },
  GoogleCalendarDetailIcon = { fg = '#ff9e64', bold = true },
  GoogleCalendarDetailMuted = { fg = '#565f89' },
  GoogleCalendarDetailMeet = { fg = '#7dcfff' },
  GoogleCalendarDetailAccepted = { fg = '#9ece6a' },
  GoogleCalendarDetailPending = { fg = '#e0af68' },
  GoogleCalendarDetailDeclined = { fg = '#f7768e' },
  GoogleCalendarFormTitle = { fg = '#e0e6ea', bold = true },
  GoogleCalendarFormMuted = { fg = '#565f89' },
  GoogleCalendarFormIcon = { fg = '#ff9e64', bold = true },
  GoogleCalendarFormButton = { fg = '#7aa2f7', bold = true },
  GoogleCalendarFormSeparator = { fg = '#565f89' },
  GoogleCalendarBorder = { fg = '#7aa2f7' },
  GoogleCalendarError = { fg = '#f7768e', bold = true },
}

local function set_clipboard(url)
  vim.fn.setreg('+', url)
end

local defaults = {
  calendars = { 'primary' },
  week_start = 'sunday',
  max_events_per_cell = 7,
  width = 1.0,
  height = 1.0,
  agenda = { width = 0.5, height = 0.7 },
  detail = { width = 0.5, height = 0.5 },
  date_format = '%Y-%m-%d %H:%M',
  gws_cmd = 'gws',
  notify = vim.notify,
  clipboard = set_clipboard,
  keymaps = {
    month = {
      prev_day = 'h',
      next_day = 'l',
      prev_week = 'k',
      next_week = 'j',
      prev_month = 'H',
      next_month = 'L',
      today = 't',
      agenda = '<CR>',
      create = 'a',
      refresh = 'r',
      help = '?',
      close = 'q',
      esc_close = '<Esc>',
    },
    agenda = { next = 'j', prev = 'k', open = '<CR>', delete = 'd', help = '?', close = 'q', esc_close = '<Esc>' },
    detail = {
      edit = 'e',
      delete = 'd',
      copy_meet = 'y',
      toggle_guests = 'g',
      help = '?',
      close = 'q',
      esc_close = '<Esc>',
    },
    form = {
      next_field = '<Tab>',
      prev_field = '<S-Tab>',
      edit = '<CR>',
      toggle = '<Space>',
      save = ':w',
      cancel = '<Esc>',
      close = 'q',
      help = '?',
    },
    confirm = { yes = 'y', no = 'n', close = 'q', esc_close = '<Esc>' },
    help = { close = 'q', esc_close = '<Esc>' },
  },
  highlights = default_highlights,
}

local function warn(notify, message)
  notify('google-calendar.nvim: ' .. message, vim.log.levels.WARN)
end

local function validate_week_start(notify, value)
  if value == 'sunday' or value == 'monday' then
    return value
  end

  warn(notify, "week_start must be 'sunday' or 'monday'. Using the default 'sunday'.")
  return defaults.week_start
end

local function validate_max_events_per_cell(notify, value)
  if type(value) ~= 'number' or value < 1 then
    warn(notify, 'max_events_per_cell must be between 1 and 10. Using the default 7.')
    return defaults.max_events_per_cell
  end

  if value > 10 then
    warn(notify, 'max_events_per_cell must be between 1 and 10. Using 10.')
    return 10
  end

  return value
end

local function config_file_path(opts)
  if opts.config_file == false then
    return nil
  end
  if type(opts.config_file) == 'string' and opts.config_file ~= '' then
    return opts.config_file
  end
  local env_path = vim.env.GOOGLE_CALENDAR_CONFIG
  if type(env_path) == 'string' and env_path ~= '' then
    return env_path
  end
  return vim.fn.stdpath('data') .. '/google-calendar.nvim/config.json'
end

local function load_calendars(notify, path)
  if path == nil then
    return nil
  end
  path = vim.fn.expand(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    warn(notify, 'Could not read config file: ' .. path)
    return nil
  end

  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(decoded) ~= 'table' then
    warn(notify, 'Config file must be valid JSON: ' .. path)
    return nil
  end

  local calendars = decoded.calendars
  if calendars == nil then
    return nil
  end
  if type(calendars) ~= 'table' then
    warn(notify, 'calendars in ' .. path .. ' must be an array of strings')
    return nil
  end
  for _, calendar_id in ipairs(calendars) do
    if type(calendar_id) ~= 'string' or calendar_id == '' then
      warn(notify, 'calendars in ' .. path .. ' must be an array of strings')
      return nil
    end
  end

  return vim.deepcopy(calendars)
end

local function normalize_calendars(calendars)
  local result = { 'primary' }
  local seen = { primary = true }
  if type(calendars) == 'table' then
    for _, calendar_id in ipairs(calendars) do
      if type(calendar_id) == 'string' and calendar_id ~= '' and not seen[calendar_id] then
        seen[calendar_id] = true
        table.insert(result, calendar_id)
      end
    end
  end
  return result
end

local function merge_keymaps(notify, overrides)
  local merged = vim.deepcopy(defaults.keymaps)
  if overrides == nil then
    return merged
  end

  if type(overrides) ~= 'table' then
    warn(notify, 'keymaps must be a table')
    return merged
  end

  for screen, actions in pairs(overrides) do
    if merged[screen] == nil then
      warn(notify, string.format("Ignoring unknown screen '%s'", screen))
    elseif type(actions) ~= 'table' then
      warn(notify, string.format("keymaps for screen '%s' must be a table", screen))
    else
      for action, key in pairs(actions) do
        if merged[screen][action] == nil then
          warn(notify, string.format("Ignoring unknown action '%s' (screen '%s')", action, screen))
        else
          merged[screen][action] = key
        end
      end
    end
  end

  return merged
end

local function merge_highlights(overrides)
  local merged = vim.deepcopy(defaults.highlights)
  if type(overrides) ~= 'table' then
    return merged
  end

  for group, definition in pairs(overrides) do
    if type(definition) == 'table' then
      merged[group] = vim.tbl_deep_extend('force', merged[group] or {}, definition)
    else
      merged[group] = definition
    end
  end

  return merged
end

M.current = vim.deepcopy(defaults)
M.highlight_overrides = {}
local applied_default_highlights = {}

function M.setup(opts)
  opts = opts or {}
  local notify = opts.notify or vim.notify
  local current = vim.deepcopy(defaults)
  current.notify = notify

  local file_calendars = nil
  if opts.calendars == nil then
    file_calendars = load_calendars(notify, config_file_path(opts))
  end

  if opts.calendars ~= nil then
    current.calendars = normalize_calendars(opts.calendars)
  elseif file_calendars ~= nil then
    current.calendars = normalize_calendars(file_calendars)
  end
  if opts.width ~= nil then
    current.width = opts.width
  end
  if opts.height ~= nil then
    current.height = opts.height
  end
  if type(opts.agenda) == 'table' then
    current.agenda = vim.tbl_deep_extend('force', defaults.agenda, opts.agenda)
  end
  if type(opts.detail) == 'table' then
    current.detail = vim.tbl_deep_extend('force', defaults.detail, opts.detail)
  end
  if opts.date_format ~= nil then
    current.date_format = opts.date_format
  end
  if opts.gws_cmd ~= nil then
    current.gws_cmd = opts.gws_cmd
  end
  if opts.clipboard ~= nil then
    current.clipboard = opts.clipboard
  end

  current.week_start = validate_week_start(notify, opts.week_start or defaults.week_start)
  current.max_events_per_cell =
    validate_max_events_per_cell(notify, opts.max_events_per_cell or defaults.max_events_per_cell)
  current.keymaps = merge_keymaps(notify, opts.keymaps)
  current.highlights = merge_highlights(opts.highlights)

  M.current = current
  if type(opts.highlights) == 'table' then
    M.highlight_overrides = vim.deepcopy(opts.highlights)
  else
    M.highlight_overrides = {}
  end

  return current
end

function M.get()
  return M.current
end

function M.resolve(screen, action)
  local actions = M.current.keymaps[screen]
  if actions == nil then
    return nil
  end

  local key = actions[action]
  if key == false then
    return nil
  end

  return key
end

function M.apply_highlights()
  -- default = true は既存定義を上書きしないため、前回上書きしたグループは default = false で既定へ戻す
  for group, definition in pairs(defaults.highlights) do
    if M.current.highlights[group] == false then
      -- false は無効化として扱い、既定の定義を消す
      vim.api.nvim_set_hl(0, group, {})
      applied_default_highlights[group] = true
    else
      -- 一度このプラグインが適用したグループは、プラグイン更新後の setup() で
      -- 既定色の変更が反映されるように default = false で上書きする
      local options = vim.tbl_extend('force', { default = not applied_default_highlights[group] }, definition)
      vim.api.nvim_set_hl(0, group, options)
      applied_default_highlights[group] = true
    end
  end

  for group in pairs(M.highlight_overrides) do
    local definition = M.current.highlights[group]
    if type(definition) == 'table' then
      vim.api.nvim_set_hl(0, group, vim.tbl_extend('force', { default = false }, definition))
    end
  end
end

return M
