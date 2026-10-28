local config = require('google-calendar.config')
local state = require('google-calendar.state')
local window = require('google-calendar.ui.window')

local M = {}

local EMPTY_MESSAGE = '有効なキーがありません'

-- 画面ごとに表示するキーの並び。並びとラベルは docs/design/features/help.md の表に合わせる
local layouts = {
  month = {
    { { action = 'prev_day', label = '前日' }, { action = 'next_day', label = '翌日' } },
    { { action = 'prev_week', label = '前週' }, { action = 'next_week', label = '翌週' } },
    { { action = 'prev_month', label = '前月' }, { action = 'next_month', label = '次月' } },
    { { action = 'today', label = '今日' } },
    { { action = 'agenda', label = 'アジェンダ' } },
    { { action = 'create', label = '登録' } },
    { { action = 'refresh', label = '再取得' } },
    { { action = 'help', label = 'ヘルプ' } },
    { { action = 'close', label = '閉じる' } },
  },
  agenda = {
    { { action = 'next', label = '選択' }, { action = 'prev', label = '選択' } },
    { { action = 'open', label = '詳細' } },
    { { action = 'close', label = '戻る' } },
  },
  detail = {
    { { action = 'edit', label = '更新' } },
    { { action = 'delete', label = '削除' } },
    { { action = 'copy_meet', label = 'Meet URL コピー' } },
    { { action = 'close', label = '戻る' } },
  },
  form = {
    { { action = 'next_field', label = '移動' }, { action = 'prev_field', label = '移動' } },
    { { action = 'edit', label = '編集' } },
    { { action = 'toggle', label = '切替' } },
    { { action = 'save', label = '保存' } },
    { { action = 'cancel', label = '取消' } },
  },
}

local function format_entry(screen, entry)
  local keys = {}
  local labels = {}

  for _, item in ipairs(entry) do
    local key = config.resolve(screen, item.action)
    if key ~= nil then
      table.insert(keys, key)
      table.insert(labels, item.label)
    end
  end

  if #keys == 0 then
    return nil
  end

  -- 同じラベルのキー (例: j/k の「選択」) は 1 つにまとめ、ラベルが異なる組だけ並べる
  local label = labels[1]
  for index = 2, #labels do
    if labels[index] ~= labels[1] then
      label = table.concat(labels, '/')
      break
    end
  end

  return table.concat(keys, '/') .. ':' .. label
end

function M.lines(screen)
  local lines = {}

  for _, entry in ipairs(layouts[screen] or {}) do
    local line = format_entry(screen, entry)
    if line ~= nil then
      table.insert(lines, line)
    end
  end

  if #lines == 0 then
    return { EMPTY_MESSAGE }
  end

  return lines
end

-- バッファごとに最後に設定したヘルプのキーを覚え、キーマップの変更時に古い割り当てを消す
local applied_help_keys = {}

local HELP_KEYMAP_ACTIONS = { 'close', 'esc_close' }

local function apply_keymaps(buf)
  local previous = applied_help_keys[buf] or {}
  local current = {}
  for _, action in ipairs(HELP_KEYMAP_ACTIONS) do
    current[action] = config.resolve('help', action)
  end

  for _, action in ipairs(HELP_KEYMAP_ACTIONS) do
    local key = previous[action]
    if key ~= nil and key ~= current[action] then
      pcall(vim.api.nvim_buf_del_keymap, buf, 'n', key)
    end
  end

  for _, action in ipairs(HELP_KEYMAP_ACTIONS) do
    local key = current[action]
    if key ~= nil then
      vim.keymap.set('n', key, M.close, { buffer = buf, nowait = true })
    end
  end

  applied_help_keys[buf] = current
end

local function window_size(line_count)
  local width = math.max(1, math.min(70, vim.o.columns - 8))
  local height = math.min(line_count + 4, 20)

  return width, height
end

local function window_position(width, height)
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  return row, col
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.open(screen)
  local lines = M.lines(screen)
  local width, height = window_size(#lines)
  local row, col = window_position(width, height)
  local opts = { relative = 'editor', width = width, height = height, row = row, col = col }

  local win = state.windows.help
  local reuse = win ~= nil and vim.api.nvim_win_is_valid(win)
  if reuse then
    vim.api.nvim_win_set_config(win, opts)
  else
    win = window.open('help', opts)
  end

  local buf = vim.api.nvim_win_get_buf(win)
  set_lines(buf, lines)
  apply_keymaps(buf)
  vim.api.nvim_set_current_win(win)

  return win
end

function M.close()
  local win = state.windows.help
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    applied_help_keys[vim.api.nvim_win_get_buf(win)] = nil
  end

  return window.close('help')
end

return M
