---@diagnostic disable: undefined-field
local config = require('google-calendar.config')
local event = require('google-calendar.event')
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
        message = 'gws was not found. Install gws by following the setup instructions in README.md.',
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
        message = 'gws authentication has expired. Run gws auth login.',
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
        message = 'Google Calendar API error: Backend Error',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)

  it('error.message が無い API エラーでも通知できる', function()
    notify.error({ kind = 'api', code = 500 })

    assert.are.same({
      {
        message = 'Google Calendar API error: Unknown error',
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
        message = 'The event has already been deleted.',
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
          message = 'Cannot connect to Google Calendar. Check your network and retry with r.',
          level = vim.log.levels.ERROR,
        },
      }, notifications)
    end
  )

  it('出力を解釈できないときに、その旨と生の stderr を DEBUG で通知する', function()
    notify.error({ kind = 'invalid_output', output = 'not-json\n', stderr = 'Using keyring backend: fake\n' })

    assert.are.same({
      {
        message = 'Could not parse the output from gws',
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
      'Cannot connect to Google Calendar. Check your network and retry with r.',
    }, messages())
  end)

  it('別のエラーを挟んだ場合は同じエラーでも再度通知する', function()
    notify.error({ kind = 'network', message = 'timeout' })
    notify.error({ kind = 'auth', message = 'authError' })
    notify.error({ kind = 'network', message = 'timeout' })

    assert.are.same({
      'Cannot connect to Google Calendar. Check your network and retry with r.',
      'gws authentication has expired. Run gws auth login.',
      'Cannot connect to Google Calendar. Check your network and retry with r.',
    }, messages())
  end)

  it('reset を呼ぶと、同じエラーを再度通知する', function()
    local err = { kind = 'network', message = 'timeout' }

    notify.error(err)
    notify.reset()
    notify.error(err)

    assert.are.same({
      'Cannot connect to Google Calendar. Check your network and retry with r.',
      'Cannot connect to Google Calendar. Check your network and retry with r.',
    }, messages())
  end)

  it('長い API エラーの本文は画面幅に切り詰め、全文を DEBUG で通知する', function()
    vim.o.columns = 40
    local detail = string.rep('x', 50)

    notify.error({ kind = 'api', code = 500, message = detail })

    assert.are.same({
      {
        message = event.truncate('Google Calendar API error: ' .. detail, vim.o.columns),
        level = vim.log.levels.ERROR,
      },
      {
        message = 'Google Calendar API error: ' .. detail,
        level = vim.log.levels.DEBUG,
      },
    }, notifications)
  end)

  it('API エラーの本文に含まれる改行は空白に置き換えて 1 行にする', function()
    notify.error({ kind = 'api', code = 500, message = 'first line\nsecond line' })

    assert.are.same({
      {
        message = 'Google Calendar API error: first line second line',
        level = vim.log.levels.ERROR,
      },
    }, notifications)
  end)
end)
