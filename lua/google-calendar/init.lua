local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local notify = require('google-calendar.notify')
local state = require('google-calendar.state')
local month_view = require('google-calendar.ui.month_view')
local window = require('google-calendar.ui.window')

local M = {}

function M.setup(opts)
  config.setup(opts)
  config.apply_highlights()
end

local function ensure_gws()
  local cfg = config.get()
  if vim.fn.executable(cfg.gws_cmd) == 0 then
    notify.error({ kind = 'not_found', command = cfg.gws_cmd })
    return false
  end
  return true
end

function M.open(args)
  if window.is_hidden() then
    if args == nil or args == '' then
      return window.show_all()
    end
    -- 別の月や空き枠を指定されたら、隠した画面の上に重ねず閉じてから開き直す
    window.close_all()
  end

  if args == 'slots' then
    if not ensure_gws() then
      return false
    end
    require('google-calendar.ui.slot_filter').open()
    return true
  end

  local today = calendar.today()
  local today_year, today_month, today_day = calendar.date_parts(today)
  local target_year, target_month

  if args == nil or args == '' then
    target_year, target_month = today_year, today_month
  else
    target_year, target_month = calendar.parse_month(args)
    if target_year == nil then
      config.get().notify('Month must be specified in YYYY-MM format', vim.log.levels.ERROR)
      return false
    end
  end

  if not ensure_gws() then
    return false
  end

  if state.year ~= target_year or state.month ~= target_month or state.selected_date == nil then
    state.year = target_year
    state.month = target_month
    state.selected_date = string.format(
      '%04d-%02d-%02d',
      target_year,
      target_month,
      calendar.clamp_day(target_year, target_month, today_day)
    )
  end

  return month_view.open()
end

function M.toggle()
  if window.is_hidden() then
    return window.show_all()
  end
  if #state.stack > 0 then
    return window.hide_all()
  end
  return M.open()
end

return M
