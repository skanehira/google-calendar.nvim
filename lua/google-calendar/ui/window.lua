local state = require('google-calendar.state')

local M = {}

local function find_entry(name)
  for index = #state.stack, 1, -1 do
    if state.stack[index].name == name then
      return index, state.stack[index]
    end
  end

  return nil, nil
end

local function focus_after_close(entry)
  local target = entry.parent
  if target == nil or not vim.api.nvim_win_is_valid(target) then
    target = nil
    local top = state.stack[#state.stack]
    if top ~= nil and vim.api.nvim_win_is_valid(top.win) then
      target = top.win
    end
  end

  if target ~= nil and vim.api.nvim_win_is_valid(target) and target ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(target)
  end
end

function M.open(name, opts)
  local parent = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local win = vim.api.nvim_open_win(
    buf,
    true,
    vim.tbl_extend('force', {
      relative = 'editor',
      style = 'minimal',
      border = 'rounded',
    }, opts or {})
  )

  state.windows[name] = win
  table.insert(state.stack, { name = name, win = win, buf = buf, parent = parent })

  return win
end

function M.close(name)
  local index, entry = find_entry(name)
  if entry == nil then
    return false
  end

  table.remove(state.stack, index)
  state.windows[name] = nil

  if vim.api.nvim_win_is_valid(entry.win) then
    vim.api.nvim_win_close(entry.win, true)
  end
  if vim.api.nvim_buf_is_valid(entry.buf) then
    vim.api.nvim_buf_delete(entry.buf, { force = true })
  end

  focus_after_close(entry)

  return true
end

function M.max_display_width(lines)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return width
end

function M.resize(win, width, height)
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end

  width = math.max(1, math.min(width, vim.o.columns - 2))
  height = math.max(1, math.min(height, vim.o.lines - 2))

  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  vim.api.nvim_win_set_config(win, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
  })
end

return M
