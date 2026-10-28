local config = require('google-calendar.config')
local event = require('google-calendar.event')
local notify = require('google-calendar.notify')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local confirm = {
  active = false,
  win = 0,
  buf = 0,
  item = nil,
  deleting = false,
  on_finished = nil,
}

local function message(item, width)
  local prefix = '予定「'
  local suffix = '」を削除しますか? (y/n)'
  local available = math.max(0, width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(suffix))
  return prefix .. event.truncate(event.sanitize(item.summary), available) .. suffix
end

local function key_hint()
  local parts = {}

  local yes = config.resolve('confirm', 'yes')
  if yes ~= nil then
    table.insert(parts, yes .. ':削除')
  end

  local no = config.resolve('confirm', 'no')
  if no ~= nil then
    table.insert(parts, no .. ':キャンセル')
  end

  if #parts == 0 then
    return '有効なキーがありません'
  end

  return table.concat(parts, '  ')
end

local function render()
  if not confirm.active or not vim.api.nvim_win_is_valid(confirm.win) then
    return
  end

  local width = vim.api.nvim_win_get_width(confirm.win)
  local hint = key_hint()
  if confirm.deleting then
    hint = '削除中...'
  end

  vim.bo[confirm.buf].modifiable = true
  vim.api.nvim_buf_set_lines(confirm.buf, 0, -1, false, { message(confirm.item, width), hint })
  vim.bo[confirm.buf].modifiable = false
end

local function close()
  if confirm.deleting then
    return
  end

  confirm.active = false
  confirm.item = nil
  confirm.on_finished = nil
  window.close('confirm')
end

local function finish()
  confirm.active = false
  confirm.deleting = false
  confirm.item = nil

  local on_finished = confirm.on_finished
  confirm.on_finished = nil
  window.close('confirm')

  if on_finished ~= nil then
    on_finished()
  end
end

local function delete()
  if not confirm.active or confirm.deleting then
    return
  end

  confirm.deleting = true
  render()

  local item = confirm.item
  local gws = require('google-calendar.gws')
  gws.delete_event(item.id, function(_, err)
    vim.schedule(function()
      if not confirm.active then
        return
      end

      if err == nil then
        finish()
        config.get().notify('予定を削除しました', vim.log.levels.INFO)
        return
      end

      notify.error(err)
      if err.kind == 'api' and err.code == 404 then
        finish()
      else
        confirm.deleting = false
        render()
      end
    end)
  end)
end

local key_actions = {
  yes = delete,
  no = close,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve('confirm', action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

function M.open(item, opts)
  local width = math.max(1, math.min(70, vim.o.columns - 8))
  local height = 2
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local opts_win = { relative = 'editor', width = width, height = height, row = row, col = col }

  local win = state.windows.confirm
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, opts_win)
  else
    win = window.open('confirm', opts_win)
  end

  confirm.active = true
  confirm.win = win
  confirm.buf = vim.api.nvim_win_get_buf(win)
  confirm.item = item
  confirm.deleting = false
  confirm.on_finished = opts ~= nil and opts.on_finished or nil
  render()
  set_keymaps(confirm.buf)
  vim.api.nvim_set_current_win(win)

  return win
end

return M
