local function complete_months(arglead)
  local now = os.date('*t')
  local candidates = {}

  for offset = -12, 12 do
    local total = now.year * 12 + (now.month - 1) + offset
    local year = math.floor(total / 12)
    local month = total % 12 + 1
    local value = string.format('%04d-%02d', year, month)
    if value:sub(1, #arglead) == arglead then
      table.insert(candidates, value)
    end
  end

  return candidates
end

vim.api.nvim_create_user_command('GoogleCalendar', function(opts)
  require('google-calendar').open(opts.args)
end, {
  nargs = '?',
  complete = complete_months,
  desc = 'Google カレンダーの月表示を開く',
  force = true,
})
