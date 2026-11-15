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

local function is_hidden_win(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).hide == true
end

-- 隠したかどうかをフラグで持たないのは、非同期の応答で float が閉じたときにフラグとスタックがずれるため
function M.is_hidden()
  local bottom = state.stack[1]
  return bottom ~= nil and is_hidden_win(bottom.win)
end

local function focus_after_close(entry)
  if M.is_hidden() then
    return
  end

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

local function set_hidden(hide)
  for _, entry in ipairs(state.stack) do
    if vim.api.nvim_win_is_valid(entry.win) then
      vim.api.nvim_win_set_config(entry.win, { hide = hide })
    end
  end
end

local function base_window()
  local bottom = state.stack[1]
  if bottom ~= nil and vim.api.nvim_win_is_valid(bottom.parent) and not is_hidden_win(bottom.parent) then
    return bottom.parent
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      return win
    end
  end
  return nil
end

function M.hide_all()
  if #state.stack == 0 then
    return false
  end

  local target = base_window()
  set_hidden(true)
  -- 隠した float はカレントのまま残り、見えない画面にキー入力が入るため、開く前のウィンドウへ戻す
  if target ~= nil then
    vim.api.nvim_set_current_win(target)
  end
  return true
end

function M.show_all()
  if not M.is_hidden() then
    return false
  end

  set_hidden(false)
  local top = state.stack[#state.stack]
  if vim.api.nvim_win_is_valid(top.win) then
    vim.api.nvim_set_current_win(top.win)
  end
  return true
end

function M.close_all()
  while #state.stack > 0 do
    M.close(state.stack[#state.stack].name)
  end
end

function M.open(name, opts)
  -- 隠した画面の上に新しい画面だけが見える状態を作らないため、先に全体を表示する
  M.show_all()

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
  -- :q などプラグインのキー以外で閉じた float がスタックに残ると、隠した・表示中の判定を誤るため取り除く
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      for index, entry in ipairs(state.stack) do
        if entry.win == win then
          table.remove(state.stack, index)
          if state.windows[entry.name] == win then
            state.windows[entry.name] = nil
          end
          break
        end
      end
    end,
  })

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

function M.target_size(width_ratio, height_ratio)
  local usable_width = math.max(1, vim.o.columns - 2)
  local usable_height = math.max(1, vim.o.lines - 2)
  local width = math.max(1, math.min(usable_width, math.floor(usable_width * width_ratio)))
  local height = math.max(1, math.min(usable_height, math.floor(usable_height * height_ratio)))
  return width, height
end

function M.resize(win, width, height)
  if win == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end

  width = math.max(1, math.min(width, vim.o.columns - 2))
  height = math.max(1, math.min(height, vim.o.lines - 2))

  -- ボーダー 2 列/行を含めて画面内に収め、中央に置く
  local row = math.max(0, math.floor((vim.o.lines - (height + 2)) / 2))
  local col = math.max(0, math.floor((vim.o.columns - (width + 2)) / 2))
  vim.api.nvim_win_set_config(win, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
  })
end

return M
