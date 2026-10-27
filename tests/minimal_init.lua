local plenary_path = os.getenv('PLENARY_PATH') or vim.fn.expand('~/.local/share/nvim/lazy/plenary.nvim')
local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

vim.opt.runtimepath:append(plenary_path)
vim.opt.runtimepath:append(repo_root)
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'

vim.cmd('runtime plugin/plenary.vim')
if vim.fn.exists(':PlenaryBustedDirectory') == 0 then
  io.stderr:write(
    'plenary.nvim が見つかりません。PLENARY_PATH を設定してください: ' .. plenary_path .. '\n'
  )
  vim.cmd('cquit 1')
end

local harness = require('plenary.test_harness')
local test_directory = harness.test_directory

-- PlenaryBustedDirectory は spec が 0 件のディレクトリで終了コード 0 を返すため、
-- テストが 0 件のまま成功するのを防ぐ。
harness.test_directory = function(directory, opts)
  local timeout = vim.env.PLENARY_TEST_TIMEOUT
  vim.env.PLENARY_TEST_TIMEOUT = nil
  local paths = harness._find_files_to_run(directory)
  vim.env.PLENARY_TEST_TIMEOUT = timeout

  if #paths == 0 then
    io.stderr:write('spec が 0 件です: ' .. directory .. '\n')
    vim.cmd('cquit 1')
  end
  return test_directory(directory, opts)
end
