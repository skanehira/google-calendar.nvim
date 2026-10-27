local M = {
  year = nil,
  month = nil,
  selected_date = nil,
  events_by_date = {},
  loading = false,
  windows = {},
  stack = {},
}

function M.reset()
  M.year = nil
  M.month = nil
  M.selected_date = nil
  M.events_by_date = {}
  M.loading = false
  M.windows = {}
  M.stack = {}
end

return M
