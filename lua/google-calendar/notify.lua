local config = require('google-calendar.config')
local event = require('google-calendar.event')

local M = {}

local MESSAGES = {
  not_found = 'gws が見つかりません。README のセットアップ手順に従って gws をインストールしてください。',
  auth = 'gws の認証が切れています。gws auth login を実行してください。',
  network = 'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
  invalid_output = 'gws の出力を解釈できませんでした',
  deleted = '予定が既に削除されています。',
}

local last_message = nil

local function api_message(err)
  local detail = err.message
  if type(detail) ~= 'string' or detail == '' then
    detail = '不明なエラー'
  end
  return 'Google Calendar API エラー: ' .. detail
end

local function message_for(err)
  if err.kind == 'api' then
    if err.code == 404 then
      return MESSAGES.deleted
    end
    return api_message(err)
  end

  return MESSAGES[err.kind] or 'Google Calendar の操作に失敗しました'
end

function M.error(err)
  local full = event.sanitize(message_for(err))
  if full == last_message then
    return
  end
  last_message = full

  local notify = config.get().notify
  local shown = full
  if err.kind == 'api' then
    shown = event.truncate(full, vim.o.columns)
  end

  notify(shown, vim.log.levels.ERROR)
  if shown ~= full then
    notify(full, vim.log.levels.DEBUG)
  end
  if err.kind == 'invalid_output' and type(err.stderr) == 'string' and err.stderr ~= '' then
    notify(err.stderr, vim.log.levels.DEBUG)
  end
end

function M.reset()
  last_message = nil
end

return M
