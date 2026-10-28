---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local notify = require('google-calendar.notify')

local notifications
local original_columns

local function capture(message, level)
  table.insert(notifications, { message = message, level = level })
end

local function messages()
  local result = {}
  for _, notification in ipairs(notifications) do
    table.insert(result, notification.message)
  end
  return result
end

describe('notify', function()
  before_each(function()
    notifications = {}
    original_columns = vim.o.columns
    config.setup({ notify = capture })
    notify.reset()
  end)

  after_each(function()
    config.setup({})
    notify.reset()
    vim.o.columns = original_columns
  end)

  it('gws が見つからないときに、インストール方法を含むエラーを通知する', function()
    notify.error({ kind = 'not_found', command = 'gws' })

    assert.are.same({
      {
        message = 'gws が見つかりません。README のセットアップ手順に従って gws をインストールしてください。',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it('認証エラーのときに、gws auth login の実行を促すエラーを通知する', function()
    notify.error({
      kind = 'auth',
      message = 'Request had invalid authentication credentials.',
    })

    assert.are.same({
      {
        message = 'gws の認証が切れています。gws auth login を実行してください。',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it('API エラーのときに、error.message を含むエラーを通知する', function()
    notify.error({
      kind = 'api',
      code = 500,
      message = 'Backend Error',
      reason = 'backendError',
    })

    assert.are.same({
      {
        message = 'Google Calendar API エラー: Backend Error',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it('error.message が無い API エラーでも通知できる', function()
    notify.error({ kind = 'api', code = 500 })

    assert.are.same({
      {
        message = 'Google Calendar API エラー: 不明なエラー',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it('404 のときに、予定が既に削除されている旨を通知する', function()
    notify.error({
      kind = 'api',
      code = 404,
      message = 'Not Found',
      reason = 'notFound',
    })

    assert.are.same({
      {
        message = '予定が既に削除されています。',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it(
    'ネットワークエラーのときに、ネットワークの確認と r による再試行を案内する',
    function()
      notify.error({ kind = 'network', message = 'timeout' })

      assert.are.same({
        {
          message = 'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
          level = vim.log.levels.ERROR,
        },
      }, notifications)
    end
  )

  it('出力を解釈できないときに、その旨と生の stderr を DEBUG で通知する', function()
    notify.error({ kind = 'invalid_output', output = 'not-json\n', stderr = 'Using keyring backend: fake\n' })

    assert.are.same({
      {
        message = 'gws の出力を解釈できませんでした',
        level = vim.log.levels.ERROR,
      },
      {
        message = 'Using keyring backend: fake\n',
        level = vim.log.levels.DEBUG,
      },
    }, notifications)
  end)

  it('同じエラーが連続した場合は 1 回だけ通知する', function()
    local err = { kind = 'network', message = 'timeout' }

    notify.error(err)
    notify.error(err)

    assert.are.same({
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
    }, messages())
  end)

  it('別のエラーを挟んだ場合は同じエラーでも再度通知する', function()
    notify.error({ kind = 'network', message = 'timeout' })
    notify.error({ kind = 'auth', message = 'authError' })
    notify.error({ kind = 'network', message = 'timeout' })

    assert.are.same({
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
      'gws の認証が切れています。gws auth login を実行してください。',
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
    }, messages())
  end)

  it('reset を呼ぶと、同じエラーを再度通知する', function()
    local err = { kind = 'network', message = 'timeout' }

    notify.error(err)
    notify.reset()
    notify.error(err)

    assert.are.same({
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
      'Google Calendar に接続できません。ネットワークを確認し、r で再試行してください。',
    }, messages())
  end)

  it('長い API エラーの本文は画面幅に切り詰め、全文を DEBUG で通知する', function()
    vim.o.columns = 40
    local detail = string.rep('x', 50)

    notify.error({ kind = 'api', code = 500, message = detail })

    assert.are.same({
      {
        message = 'Google Calendar API エラー: xxxxxxxxxxx…',
        level = vim.log.levels.ERROR,
      },
      {
        message = 'Google Calendar API エラー: ' .. detail,
        level = vim.log.levels.DEBUG,
      },
    }, notifications)
  end)

  it('API エラーの本文に含まれる改行は空白に置き換えて 1 行にする', function()
    notify.error({ kind = 'api', code = 500, message = 'first line\nsecond line' })

    assert.are.same({
      {
        message = 'Google Calendar API エラー: first line second line',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)
end)
