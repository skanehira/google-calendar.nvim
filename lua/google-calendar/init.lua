local calendar = require('google-calendar.calendar')
local config = require('google-calendar.config')
local state = require('google-calendar.state')
local month_view = require('google-calendar.ui.month_view')

local M = {}

function M.setup(opts)
  config.setup(opts)
  config.apply_highlights()
end

function M.open(args)
  local today = calendar.today()
  local today_year, today_month, today_day = calendar.date_parts(today)
  local target_year, target_month

  if args == nil or args == '' then
    target_year, target_month = today_year, today_month
  else
    target_year, target_month = calendar.parse_month(args)
    if target_year == nil then
      config.get().notify('月の指定は YYYY-MM 形式で入力してください', vim.log.levels.ERROR)
      return false
    end
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

return M
