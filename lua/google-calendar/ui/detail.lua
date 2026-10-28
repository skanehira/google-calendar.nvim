local config = require('google-calendar.config')
local event = require('google-calendar.event')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local DESCRIPTION_MAX_LINES = 5

-- 更新フォーム・削除確認・Meet URL コピーの実処理は別機能が持つため、キー処理からは opener 経由で呼ぶ
M.openers = {
  edit = function(item, opts)
    require('google-calendar.ui.form').open_edit(item, opts)
  end,
  delete = function(item, opts)
    require('google-calendar.ui.confirm').open(item, {
      on_finished = function()
        window.close('detail')
        if opts ~= nil and opts.on_changed ~= nil then
          opts.on_changed()
        end
      end,
    })
  end,
  copy_meet = function(item)
    M.copy_meet(item)
  end,
  help = function(screen)
    require('google-calendar.ui.help').open(screen)
  end,
}

local current_item = nil
local current_opts = {}

local function value_line(label, value)
  if value == nil or value == '' then
    return nil
  end

  return label .. ': ' .. value
end

local function build_lines(item, width)
  local lines = {}

  local title_width = math.max(0, width - vim.fn.strdisplaywidth('タイトル: '))
  local title = event.truncate(event.sanitize(item.summary), title_width)
  local title_line = value_line('タイトル', title)
  if title_line ~= nil then
    table.insert(lines, title_line)
  end

  local start_line = value_line('開始', event.display_datetime(item.start))
  if start_line ~= nil then
    table.insert(lines, start_line)
  end

  local end_line = value_line('終了', event.display_datetime(item['end']))
  if end_line ~= nil then
    table.insert(lines, end_line)
  end

  local location_line = value_line('場所', event.sanitize(item.location))
  if location_line ~= nil then
    table.insert(lines, location_line)
  end

  local description_lines = event.description_lines(item.description, DESCRIPTION_MAX_LINES)
  if description_lines ~= nil then
    table.insert(lines, '説明: ' .. description_lines[1])
    for index = 2, #description_lines do
      table.insert(lines, description_lines[index])
    end
  end

  local meet_line = value_line('Meet URL', item.hangout_link)
  if meet_line ~= nil then
    table.insert(lines, meet_line)
  end

  local calendar_line = value_line('カレンダー', item.calendar_id)
  if calendar_line ~= nil then
    table.insert(lines, calendar_line)
  end

  return lines
end

local function render(win, item, width)
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = build_lines(item, width)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- 幅は内容に合わせ、高さは内容の 2 倍にして見やすくする
  window.resize(
    win,
    math.min(width, window.max_display_width(lines) + 2),
    math.max(1, math.min(#lines * 2, vim.o.lines - 4))
  )

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

local function notify(message, level)
  config.get().notify(event.truncate(message, vim.o.columns), level)
end

local function notify_copy_failure(url)
  notify('クリップボードにコピーできませんでした: ' .. url, vim.log.levels.ERROR)
end

function M.copy_meet(item)
  local url = event.meet_url(item)
  if url == nil then
    notify('この予定には Meet URL がありません', vim.log.levels.WARN)
    return
  end

  if vim.fn.has('clipboard') == 0 then
    notify_copy_failure(url)
    return
  end

  if not pcall(config.get().clipboard, url) then
    notify_copy_failure(url)
    return
  end

  notify('Meet URL をコピーしました: ' .. url, vim.log.levels.INFO)
end

local function open_edit()
  if current_item ~= nil then
    M.openers.edit(current_item, current_opts)
  end
end

local function open_delete()
  if current_item ~= nil then
    M.openers.delete(current_item, current_opts)
  end
end

local function copy_meet()
  if current_item ~= nil then
    M.openers.copy_meet(current_item)
  end
end

local function open_help()
  M.openers.help('detail')
end

local function close()
  window.close('detail')
end

local key_actions = {
  edit = open_edit,
  delete = open_delete,
  copy_meet = copy_meet,
  help = open_help,
  close = close,
  esc_close = close,
}

local function set_keymaps(buf)
  for action, handler in pairs(key_actions) do
    local key = config.resolve('detail', action)
    if key ~= nil then
      vim.keymap.set('n', key, handler, { buffer = buf, nowait = true, silent = true })
    end
  end
end

function M.open(item, opts)
  local max_width = math.max(1, math.min(70, vim.o.columns - 8))
  local lines = build_lines(item, max_width)
  local width = math.max(1, math.min(max_width, window.max_display_width(lines) + 2))
  -- Enter で開く詳細は、内容の 2 倍ほどの高さにして見やすくする
  local height = math.max(1, math.min(#lines * 2, vim.o.lines - 4))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local opts_win = { relative = 'editor', width = width, height = height, row = row, col = col }

  local win = state.windows.detail
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, opts_win)
  else
    win = window.open('detail', opts_win)
  end

  current_item = item
  current_opts = opts or {}
  render(win, item, width)
  set_keymaps(vim.api.nvim_win_get_buf(win))
  vim.api.nvim_set_current_win(win)

  return win
end

return M
