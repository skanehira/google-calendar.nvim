local config = require('google-calendar.config')

local M = {}

function M.setup(opts)
  config.setup(opts)
  config.apply_highlights()
end

function M.open(_args)
  return false
end

return M
