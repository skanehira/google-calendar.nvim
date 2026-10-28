local M = {}

local default_highlights = {
  GoogleCalendarHeader = { fg = '#7aa2f7', bold = true },
  GoogleCalendarToday = { fg = '#e0af68', bold = true },
  GoogleCalendarSelected = { bg = '#7aa2f7', fg = '#1a1b26', bold = true },
  GoogleCalendarSunday = { fg = '#f7768e' },
  GoogleCalendarSaturday = { fg = '#7dcfff' },
  GoogleCalendarOtherMonth = { fg = '#565f89' },
  GoogleCalendarEvent = { bg = '#2ac3de' },
  GoogleCalendarEventTime = { fg = '#bb9af7' },
  GoogleCalendarBorder = { fg = '#7aa2f7' },
  GoogleCalendarError = { fg = '#f7768e', bold = true },
}

local function set_clipboard(url)
  vim.fn.setreg('+', url)
end

local defaults = {
  calendars = { 'primary' },
  week_start = 'sunday',
  max_events_per_cell = 3,
  width = 0.9,
  height = 0.85,
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
    agenda = { next = 'j', prev = 'k', open = '<CR>', help = '?', close = 'q', esc_close = '<Esc>' },
    detail = { edit = 'e', delete = 'd', copy_meet = 'y', help = '?', close = 'q', esc_close = '<Esc>' },
    form = {
      next_field = '<Tab>',
      prev_field = '<S-Tab>',
      edit = '<CR>',
      toggle = '<Space>',
      save = '<F2>',
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

  warn(
    notify,
    "week_start は 'sunday' または 'monday' を指定してください。既定値の 'sunday' を使います"
  )
  return defaults.week_start
end

local function validate_max_events_per_cell(notify, value)
  if type(value) ~= 'number' or value < 1 then
    warn(notify, 'max_events_per_cell は 1〜10 で指定してください。既定値の 3 を使います')
    return defaults.max_events_per_cell
  end

  if value > 10 then
    warn(notify, 'max_events_per_cell は 1〜10 で指定してください。10 を使います')
    return 10
  end

  return value
end

local function merge_keymaps(notify, overrides)
  local merged = vim.deepcopy(defaults.keymaps)
  if overrides == nil then
    return merged
  end

  if type(overrides) ~= 'table' then
    warn(notify, 'keymaps はテーブルで指定してください')
    return merged
  end

  for screen, actions in pairs(overrides) do
    if merged[screen] == nil then
      warn(notify, string.format("未知の画面名 '%s' を無視しました", screen))
    elseif type(actions) ~= 'table' then
      warn(notify, string.format("画面 '%s' の keymaps はテーブルで指定してください", screen))
    else
      for action, key in pairs(actions) do
        if merged[screen][action] == nil then
          warn(
            notify,
            string.format("未知のアクション名 '%s' (画面 '%s') を無視しました", action, screen)
          )
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

  if opts.calendars ~= nil then
    current.calendars = vim.deepcopy(opts.calendars)
  end
  if opts.width ~= nil then
    current.width = opts.width
  end
  if opts.height ~= nil then
    current.height = opts.height
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
