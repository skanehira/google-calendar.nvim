---@diagnostic disable: undefined-field
local config = require('google-calendar.config')

local default_keymaps = {
  month = {
    prev_day = 'h',
    next_day = 'l',
    prev_week = 'k',
    next_week = 'j',
    prev_month = 'H',
    next_month = 'L',
    today = 't',
    agenda = '<CR>',
    create = 'a',
    refresh = 'r',
    help = '?',
    close = 'q',
    esc_close = '<Esc>',
  },
  agenda = { next = 'j', prev = 'k', open = '<CR>', help = '?', close = 'q', esc_close = '<Esc>' },
  detail = {
    edit = 'e',
    delete = 'd',
    copy_meet = 'y',
    toggle_guests = 'g',
    help = '?',
    close = 'q',
    esc_close = '<Esc>',
  },
  form = {
    next_field = '<Tab>',
    prev_field = '<S-Tab>',
    edit = '<CR>',
    toggle = '<Space>',
    save = ':w',
    cancel = '<Esc>',
    close = 'q',
    help = '?',
  },
  confirm = { yes = 'y', no = 'n', close = 'q', esc_close = '<Esc>' },
  help = { close = 'q', esc_close = '<Esc>' },
}

local default_highlight_groups = {
  'GoogleCalendarBorder',
  'GoogleCalendarDetailAccepted',
  'GoogleCalendarDetailDeclined',
  'GoogleCalendarDetailIcon',
  'GoogleCalendarDetailMeet',
  'GoogleCalendarDetailMuted',
  'GoogleCalendarDetailPending',
  'GoogleCalendarDetailTitle',
  'GoogleCalendarError',
  'GoogleCalendarEvent',
  'GoogleCalendarEventColor1',
  'GoogleCalendarEventColor10',
  'GoogleCalendarEventColor11',
  'GoogleCalendarEventColor2',
  'GoogleCalendarEventColor3',
  'GoogleCalendarEventColor4',
  'GoogleCalendarEventColor5',
  'GoogleCalendarEventColor6',
  'GoogleCalendarEventColor7',
  'GoogleCalendarEventColor8',
  'GoogleCalendarEventColor9',
  'GoogleCalendarEventTime',
  'GoogleCalendarFormButton',
  'GoogleCalendarFormIcon',
  'GoogleCalendarFormMuted',
  'GoogleCalendarFormSeparator',
  'GoogleCalendarFormTitle',
  'GoogleCalendarHeader',
  'GoogleCalendarOtherMonth',
  'GoogleCalendarSaturday',
  'GoogleCalendarSelected',
  'GoogleCalendarSunday',
  'GoogleCalendarToday',
}

describe('config', function()
  before_each(function()
    config.setup({})
  end)

  it('setup() が既定値をマージする', function()
    config.setup({ width = 0.5 })

    local merged = config.get()
    assert.are.equal(0.5, merged.width)
    assert.are.equal(0.7, merged.height)
    assert.are.equal('%Y-%m-%d %H:%M', merged.date_format)
    assert.are.same(default_keymaps, merged.keymaps)

    config.setup()

    local cfg = config.get()
    assert.are.same({ 'primary' }, cfg.calendars)
    assert.are.equal('sunday', cfg.week_start)
    assert.are.equal(3, cfg.max_events_per_cell)
    assert.are.equal(0.7, cfg.width)
    assert.are.equal(0.7, cfg.height)
    assert.are.same({ width = 0.5, height = 0.7 }, cfg.agenda)
    assert.are.same({ width = 0.5, height = 0.5 }, cfg.detail)
    assert.are.equal('%Y-%m-%d %H:%M', cfg.date_format)
    assert.are.equal('gws', cfg.gws_cmd)
    assert.are.equal(vim.notify, cfg.notify)
    assert.are.same(default_keymaps, cfg.keymaps)
    assert.are.same(default_highlight_groups, vim.fn.sort(vim.tbl_keys(cfg.highlights)))
  end)

  it('setup() が keymaps の上書きを既定値とマージする', function()
    config.setup({ keymaps = { form = { save = '<A-s>' }, month = { close = 'Q' } } })

    local expected = vim.deepcopy(default_keymaps)
    expected.form.save = '<A-s>'
    expected.month.close = 'Q'
    assert.are.same(expected, config.get().keymaps)
    assert.are.equal('<A-s>', config.resolve('form', 'save'))
    assert.are.equal('Q', config.resolve('month', 'close'))
  end)

  it('DoD: setup({ keymaps = { form = { save = ":w" }, month = { close = "Q" } } }) を反映する', function()
    config.setup({ keymaps = { form = { save = ':w' }, month = { close = 'Q' } } })

    assert.are.equal(':w', config.resolve('form', 'save'))
    assert.are.equal('Q', config.resolve('month', 'close'))
  end)

  it('false を指定したキーは作用しない', function()
    config.setup({ keymaps = { form = { save = false } } })

    assert.is_false(config.get().keymaps.form.save)
    assert.is_nil(config.resolve('form', 'save'))
    assert.are.equal('<Esc>', config.resolve('form', 'cancel'))
  end)

  it('未知の画面名・アクション名を指定すると警告し、その指定を無視する', function()
    local messages = {}
    config.setup({
      notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end,
      keymaps = {
        unknown_screen = { close = 'Q' },
        month = { unknown_action = 'x', close = 'Q' },
      },
    })

    table.sort(messages, function(a, b)
      return a.msg < b.msg
    end)
    assert.are.same({
      {
        msg = "google-calendar.nvim: 未知のアクション名 'unknown_action' (画面 'month') を無視しました",
        level = vim.log.levels.WARN,
      },
      {
        msg = "google-calendar.nvim: 未知の画面名 'unknown_screen' を無視しました",
        level = vim.log.levels.WARN,
      },
    }, messages)
    assert.is_nil(config.get().keymaps.unknown_screen)
    assert.is_nil(config.get().keymaps.month.unknown_action)
    assert.are.equal('Q', config.resolve('month', 'close'))
    assert.are.equal('h', config.resolve('month', 'prev_day'))
  end)

  it('setup() が highlights の上書きを既定値とマージする', function()
    config.setup({ highlights = { GoogleCalendarHeader = { fg = '#ff0000' } } })

    local cfg = config.get()
    assert.are.same({ fg = '#ff0000', bold = true }, cfg.highlights.GoogleCalendarHeader)
    assert.are.same({ fg = '#565f89' }, cfg.highlights.GoogleCalendarOtherMonth)
    assert.are.same(default_highlight_groups, vim.fn.sort(vim.tbl_keys(cfg.highlights)))
  end)

  it('apply_highlights が既定のハイライトを定義する', function()
    config.setup({})
    config.apply_highlights()

    local header = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarHeader', link = false })
    assert.are.equal('#7aa2f7', string.format('#%06x', header.fg))
    assert.is_true(header.bold)
  end)

  it('apply_highlights が予定チップに背景を付けない', function()
    config.setup({})
    config.apply_highlights()

    local event_hl = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarEvent', link = false })
    assert.is_nil(event_hl.bg)
  end)

  it('apply_highlights が上書きを既定の属性とマージして適用する', function()
    config.setup({ highlights = { GoogleCalendarHeader = { fg = '#ff0000' } } })
    config.apply_highlights()

    local header = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarHeader', link = false })
    assert.are.equal('#ff0000', string.format('#%06x', header.fg))
    assert.is_true(header.bold)
  end)

  it('setup() を呼び直すと前回の highlights の上書きが既定値に戻る', function()
    config.setup({ highlights = { GoogleCalendarHeader = { fg = '#ff0000' } } })
    config.apply_highlights()

    config.setup({})
    config.apply_highlights()

    local header = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarHeader', link = false })
    assert.are.equal('#7aa2f7', string.format('#%06x', header.fg))
    assert.is_true(header.bold)
  end)

  it('highlights に false を指定すると既定のハイライトを無効化する', function()
    config.setup({ highlights = { GoogleCalendarHeader = false } })
    config.apply_highlights()

    local header = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarHeader', link = false })
    assert.is_nil(header.fg)
    assert.is_nil(header.bold)

    config.setup({})
    config.apply_highlights()

    header = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarHeader', link = false })
    assert.are.equal('#7aa2f7', string.format('#%06x', header.fg))
    assert.is_true(header.bold)
  end)

  it('不正な week_start は警告して既定値を使う', function()
    local messages = {}
    config.setup({
      week_start = 'tuesday',
      notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end,
    })

    assert.are.equal('sunday', config.get().week_start)
    assert.are.same({
      {
        msg = "google-calendar.nvim: week_start は 'sunday' または 'monday' を指定してください。既定値の 'sunday' を使います",
        level = vim.log.levels.WARN,
      },
    }, messages)
  end)

  it('max_events_per_cell が 1 未満なら警告して既定値を使う', function()
    local messages = {}
    config.setup({
      max_events_per_cell = 0,
      notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end,
    })

    assert.are.equal(3, config.get().max_events_per_cell)
    assert.are.same({
      {
        msg = 'google-calendar.nvim: max_events_per_cell は 1〜10 で指定してください。既定値の 3 を使います',
        level = vim.log.levels.WARN,
      },
    }, messages)
  end)

  it('max_events_per_cell が 10 を超えたら警告して 10 に制限する', function()
    local messages = {}
    config.setup({
      max_events_per_cell = 11,
      notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end,
    })

    assert.are.equal(10, config.get().max_events_per_cell)
    assert.are.same({
      {
        msg = 'google-calendar.nvim: max_events_per_cell は 1〜10 で指定してください。10 を使います',
        level = vim.log.levels.WARN,
      },
    }, messages)
  end)

  it('setup() を複数回呼ぶと最後の設定が有効になる', function()
    config.setup({ week_start = 'monday', keymaps = { month = { close = 'Q' } } })

    assert.are.equal('monday', config.get().week_start)
    assert.are.equal('Q', config.resolve('month', 'close'))

    config.setup({ week_start = 'sunday' })

    local cfg = config.get()
    assert.are.equal('sunday', cfg.week_start)
    assert.are.equal('q', cfg.keymaps.month.close)
    assert.are.equal('h', config.resolve('month', 'prev_day'))
  end)
  it('apply_highlights が前回適用した既定ハイライトの変更を上書きする', function()
    config.setup({})
    config.apply_highlights()
    vim.api.nvim_set_hl(0, 'GoogleCalendarSelected', { bg = '#000000' })

    config.setup({})
    config.apply_highlights()

    local selected = vim.api.nvim_get_hl(0, { name = 'GoogleCalendarSelected', link = false })
    assert.are.equal('#7aa2f7', string.format('#%06x', selected.bg))
    assert.are.equal('#1a1b26', string.format('#%06x', selected.fg))
    assert.is_true(selected.bold)
  end)
  it('setup() が agenda / detail のサイズを上書きする', function()
    config.setup({ agenda = { width = 0.6 }, detail = { height = 0.7 } })

    local cfg = config.get()
    assert.are.same({ width = 0.6, height = 0.7 }, cfg.agenda)
    assert.are.same({ width = 0.5, height = 0.7 }, cfg.detail)
  end)
end)
