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

  local function hidden(win)
    return vim.api.nvim_win_get_config(win).hide == true
  end

  it(
    'hide_all で重ねた float をすべて隠し、開く前のウィンドウへフォーカスを戻す',
    function()
      local parent = vim.api.nvim_get_current_win()
      local first = window.open('first', float_opts)
      local second = window.open('second', float_opts)
      local second_buf = vim.api.nvim_win_get_buf(second)

      window.hide_all()

      assert.are.same({ true, true }, { hidden(first), hidden(second) })
      assert.are.equal(parent, vim.api.nvim_get_current_win())
      assert.is_true(window.is_hidden())
      -- 保存中の応答が隠した画面へ届くように、ウィンドウとバッファは残す
      assert.are.same({ true, true }, { vim.api.nvim_win_is_valid(second), vim.api.nvim_buf_is_valid(second_buf) })
      assert.are.equal(2, #state.stack)
    end
  )

  it(
    'show_all で隠した float をすべて表示し、いちばん上の float にフォーカスを移す',
    function()
      local first = window.open('first', float_opts)
      local second = window.open('second', float_opts)
      window.hide_all()

      window.show_all()

      assert.are.same({ false, false }, { hidden(first), hidden(second) })
      assert.are.equal(second, vim.api.nvim_get_current_win())
      assert.is_false(window.is_hidden())
    end
  )

  it('隠している間に float が閉じても、フォーカスは隠した float へ移らない', function()
    local parent = vim.api.nvim_get_current_win()
    local first = window.open('first', float_opts)
    window.open('second', float_opts)
    window.hide_all()

    window.close('second')

    assert.are.equal(parent, vim.api.nvim_get_current_win())
    assert.is_true(hidden(first))
  end)

  it('隠している間に float を開くと、隠した float も表示してから開く', function()
    local first = window.open('first', float_opts)
    window.hide_all()

    local second = window.open('second', float_opts)

    assert.are.same({ false, false }, { hidden(first), hidden(second) })
    assert.are.equal(second, vim.api.nvim_get_current_win())
    assert.is_false(window.is_hidden())
  end)

  it(
    ':q のようにプラグインのキー以外で閉じた float はスタックから外れ、残りを隠して表示し直せる',
    function()
      local parent = vim.api.nvim_get_current_win()
      local first = window.open('first', float_opts)
      local second = window.open('second', float_opts)

      vim.api.nvim_win_close(first, true)
      window.hide_all()

      assert.is_true(window.is_hidden())
      assert.are.equal(parent, vim.api.nvim_get_current_win())
      window.show_all()
      assert.are.equal(second, vim.api.nvim_get_current_win())
      assert.is_false(hidden(second))
      assert.are.same(
        { 'second' },
        vim.tbl_map(function(entry)
          return entry.name
        end, state.stack)
      )
      assert.is_nil(state.windows.first)
    end
  )

  it(
    'close_all で隠した float をすべて閉じ、開く前のウィンドウへフォーカスを戻す',
    function()
      local parent = vim.api.nvim_get_current_win()
      local first = window.open('first', float_opts)
      local second = window.open('second', float_opts)
      window.hide_all()

      window.close_all()

      assert.are.same({ false, false }, { vim.api.nvim_win_is_valid(first), vim.api.nvim_win_is_valid(second) })
      assert.are.equal(0, #state.stack)
      assert.are.equal(parent, vim.api.nvim_get_current_win())
      assert.is_false(window.is_hidden())
    end
  )

  it('float を閉じるとバッファが破棄される', function()
    local win = window.open('test', float_opts)
    local buf = vim.api.nvim_win_get_buf(win)

    window.close('test')

    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)
end)
