---@diagnostic disable: undefined-field
local window = require('google-calendar.ui.window')
local state = require('google-calendar.state')

local float_opts = { relative = 'editor', width = 20, height = 5, row = 1, col = 1 }

describe('ui.window', function()
  before_each(function()
    state.reset()
  end)

  after_each(function()
    while #state.stack > 0 do
      window.close(state.stack[#state.stack].name)
    end
  end)

  it('float を開くとスタックに積まれ、現在のウィンドウになる', function()
    local parent = vim.api.nvim_get_current_win()

    local win = window.open('test', float_opts)

    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal(win, state.windows.test)
    assert.are.equal(1, #state.stack)
    assert.are.equal(parent, state.stack[1].parent)
  end)

  it('float を閉じると親のウィンドウへフォーカスが戻る', function()
    local parent = vim.api.nvim_get_current_win()
    local win = window.open('test', float_opts)

    window.close('test')

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.is_nil(state.windows.test)
    assert.are.equal(0, #state.stack)
  end)

  it('重ねた float を閉じると 1 段下の float にフォーカスが戻る', function()
    local parent = vim.api.nvim_get_current_win()
    local first = window.open('first', float_opts)
    window.open('second', float_opts)

    window.close('second')
    assert.are.equal(first, vim.api.nvim_get_current_win())

    window.close('first')
    assert.are.equal(parent, vim.api.nvim_get_current_win())
  end)

  it('float を閉じるとバッファが破棄される', function()
    local win = window.open('test', float_opts)
    local buf = vim.api.nvim_win_get_buf(win)

    window.close('test')

    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)
end)
