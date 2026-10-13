local M = {}

local function source_file(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.fn.fnamemodify(path, ':e'):lower() ~= 'c' then
    error('Open a saved .c file first')
  end
  return path
end

local function build(bufnr, extra_sources)
  if vim.fn.executable('gcc') ~= 1 then
    error('gcc is unavailable; check PATH and docs/c-development.md')
  end

  vim.api.nvim_buf_call(bufnr, function() vim.cmd.update() end)
  local source = source_file(bufnr)
  local directory = vim.fn.fnamemodify(source, ':h')
  local executable = vim.fn.fnamemodify(source, ':r') .. '.exe'
  local args = { 'gcc', '-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-g', source }

  for _, file in ipairs(extra_sources) do
    local path = vim.fn.fnamemodify(file, ':p')
    if vim.fn.fnamemodify(path, ':e'):lower() ~= 'c' or vim.fn.filereadable(path) ~= 1 then
      error('Expected an existing .c source file: ' .. file)
    end
    table.insert(args, path)
  end
  table.insert(args, '-o')
  table.insert(args, executable)

  local result = vim.system(args, { cwd = directory, text = true }):wait()
  local output = ((result.stdout or '') .. '\n' .. (result.stderr or '')):gsub('\r', '')
  local lines = vim.split(output, '\n', { trimempty = true })
  vim.fn.setqflist({}, ' ', {
    title = 'C build',
    lines = lines,
    efm = '%f:%l:%c: %t%*[^:]: %m,%f:%l: %t%*[^:]: %m,%-G%.%#',
  })

  if #lines > 0 then
    local source_window = vim.api.nvim_get_current_win()
    vim.cmd.cwindow()
    vim.api.nvim_set_current_win(source_window)
  end
  if result.code ~= 0 then
    error('C build failed; inspect :copen for compiler diagnostics')
  end
  vim.notify('Built ' .. executable, vim.log.levels.INFO)
  return executable, directory
end

local function open_terminal(command, directory)
  vim.cmd.new()
  local job = vim.fn.termopen(command, { cwd = directory })
  if job <= 0 then
    error('Could not start ' .. command[1])
  end
  vim.cmd.startinsert()
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'c',
    callback = function(event)
      local bufnr = event.buf
      local function command(name, action, description)
        vim.api.nvim_buf_create_user_command(bufnr, name, action, {
          nargs = '*',
          complete = 'file',
          desc = description,
        })
      end

      command('CBuild', function(opts) build(bufnr, opts.fargs) end, 'Build this C file and optional additional .c files')
      command('CRun', function(opts)
        local executable, directory = build(bufnr, opts.fargs)
        open_terminal({ executable }, directory)
      end, 'Build and run this C program')
      command('CDebug', function(opts)
        if vim.fn.executable('gdb') ~= 1 then
          error('gdb is unavailable; check PATH and docs/c-development.md')
        end
        local executable, directory = build(bufnr, opts.fargs)
        open_terminal({ 'gdb', '-q', executable }, directory)
      end, 'Build and debug this C program with GDB')
      vim.api.nvim_buf_create_user_command(bufnr, 'CDefinition', function()
        vim.lsp.buf.definition()
      end, { desc = 'Go to symbol definition' })
      vim.api.nvim_buf_create_user_command(bufnr, 'CReferences', function()
        vim.lsp.buf.references()
      end, { desc = 'Find symbol references' })
      vim.api.nvim_buf_create_user_command(bufnr, 'CDiagnostics', function()
        vim.diagnostic.setloclist({ open = true })
      end, { desc = 'Show C diagnostics' })
    end,
  })
end

return M
