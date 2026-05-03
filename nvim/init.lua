-- Basic editor defaults
vim.g.mapleader = ' '
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

-- Tool paths installed by winget. These make headless/plugin installs work even when Windows aliases are flaky.
local nvim_tools_dir = vim.fn.expand('~/AppData/Local/nvim-tools')
local tree_sitter_dir = vim.fn.expand('~/AppData/Local/Microsoft/WinGet/Packages/tree-sitter.tree-sitter-cli_Microsoft.Winget.Source_8wekyb3d8bbwe')
local zig_dir = vim.fn.expand('~/AppData/Local/Microsoft/WinGet/Packages/zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe/zig-x86_64-windows-0.16.0')
vim.env.PATH = nvim_tools_dir .. ';' .. tree_sitter_dir .. ';' .. zig_dir .. ';' .. vim.env.PATH
vim.env.CC = nvim_tools_dir .. '/cc.cmd'
vim.env.CXX = nvim_tools_dir .. '/c++.cmd'

vim.filetype.add({
  extension = {
    prisma = 'prisma',
  },
})
vim.opt.signcolumn = 'yes'
vim.opt.clipboard = 'unnamedplus'
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.fileformats = { 'unix', 'dos' }
vim.opt.fileformat = 'unix'
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.updatetime = 250

-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  -- Coloring/theme
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme('tokyonight-night')
    end,
  },

  -- Better syntax highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local treesitter = require('nvim-treesitter')
      treesitter.setup({
        install_dir = vim.fn.stdpath('data') .. '/site',
      })

      if vim.fn.executable('tree-sitter') == 1 then
        treesitter.install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'prisma' })
      end

      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'lua', 'vim', 'javascript', 'typescript', 'typescriptreact', 'json', 'html', 'css', 'prisma' },
        callback = function()
          pcall(vim.treesitter.start)
          if vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] then
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Language servers and completion
  { 'neovim/nvim-lspconfig' },
  { 'williamboman/mason.nvim', config = true },
  { 'williamboman/mason-lspconfig.nvim' },
  { 'hrsh7th/cmp-nvim-lsp' },
  { 'hrsh7th/cmp-buffer' },
  { 'hrsh7th/cmp-path' },
  { 'hrsh7th/nvim-cmp' },
  { 'L3MON4D3/LuaSnip' },
  { 'saadparwaiz1/cmp_luasnip' },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({})
    end,
  },
  {
    'windwp/nvim-ts-autotag',
    event = 'InsertEnter',
    config = function()
      require('nvim-ts-autotag').setup({})
    end,
  },
}, {
  checker = { enabled = true },
})

local cmp = require('cmp')
local luasnip = require('luasnip')

local function find_frontend_src()
  local current = vim.fn.expand('%:p:h')
  if current == '' then
    current = vim.loop.cwd()
  end

  local dir = current
  while dir and dir ~= '' do
    if vim.fn.isdirectory(dir .. '/src') == 1 and vim.fn.filereadable(dir .. '/vite.config.ts') == 1 then
      return vim.fn.fnamemodify(dir .. '/src', ':p')
    end

    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end

  local cwd = vim.loop.cwd()
  local candidates = {
    cwd .. '/src',
    cwd .. '/front-end/src',
  }

  for _, candidate in ipairs(candidates) do
    if vim.fn.isdirectory(candidate) == 1 then
      return vim.fn.fnamemodify(candidate, ':p')
    end
  end
end

local alias_path_source = {}

function alias_path_source:is_available()
  return find_frontend_src() ~= nil
end

function alias_path_source:get_trigger_characters()
  return { '@', '/' }
end

function alias_path_source:complete(params, callback)
  local line = params.context.cursor_before_line
  local alias = line:match('@/[%w%._%-%/]*$')
  if not alias then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local src = find_frontend_src()
  if not src then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local partial = alias:sub(3)
  local dir_part = partial:match('^(.*/)[^/]*$') or ''
  local typed_name = partial:match('([^/]*)$') or ''
  local scan_dir = src .. dir_part
  local entries = vim.fn.readdir(scan_dir)
  local items = {}

  for _, entry in ipairs(entries) do
    if entry:sub(1, #typed_name) == typed_name then
      local full = scan_dir .. entry
      local is_dir = vim.fn.isdirectory(full) == 1
      local insert = '@/' .. dir_part .. entry

      if is_dir then
        insert = insert .. '/'
      else
        insert = insert:gsub('%.tsx$', ''):gsub('%.ts$', ''):gsub('%.jsx$', ''):gsub('%.js$', '')
      end

      table.insert(items, {
        label = insert,
        insertText = insert,
        filterText = insert,
        kind = is_dir and cmp.lsp.CompletionItemKind.Folder or cmp.lsp.CompletionItemKind.File,
      })
    end
  end

  callback({ items = items, isIncomplete = false })
end

cmp.register_source('alias_path', alias_path_source)
cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-BS>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.close()
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>', true, false, true), 'n', false)
    end, { 'i' }),
    ['<C-H>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.close()
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>', true, false, true), 'n', false)
    end, { 'i' }),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
    ['<Tab>'] = cmp.mapping.select_next_item(),
    ['<S-Tab>'] = cmp.mapping.select_prev_item(),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'alias_path' },
    { name = 'luasnip' },
    { name = 'path' },
    { name = 'buffer' },
  }),
})

local cmp_autopairs = require('nvim-autopairs.completion.cmp')
cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())
local capabilities = require('cmp_nvim_lsp').default_capabilities()

vim.lsp.config('*', {
  capabilities = capabilities,
})

require('mason-lspconfig').setup({
  ensure_installed = { 'ts_ls', 'eslint', 'html', 'cssls', 'jsonls', 'lua_ls', 'prismals' },
  automatic_enable = true,
})


vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
})

local function copy_current_line_diagnostic()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diagnostics = vim.diagnostic.get(bufnr, { lnum = lnum })

  if vim.tbl_isempty(diagnostics) then
    vim.notify('No diagnostic on current line', vim.log.levels.INFO)
    return
  end

  table.sort(diagnostics, function(a, b)
    return (a.severity or vim.diagnostic.severity.HINT) < (b.severity or vim.diagnostic.severity.HINT)
  end)

  local lines = {}
  for _, diagnostic in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[diagnostic.severity] or 'UNKNOWN'
    local source = diagnostic.source and (' [' .. diagnostic.source .. ']') or ''
    local code = diagnostic.code and (' (' .. diagnostic.code .. ')') or ''
    local message = diagnostic.message:gsub('%s+', ' ')
    table.insert(lines, severity .. source .. code .. ': ' .. message)
  end

  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied diagnostic for current line', vim.log.levels.INFO)
end

local function lsp_supports_formatting()
  return not vim.tbl_isempty(vim.lsp.get_clients({
    bufnr = 0,
    method = 'textDocument/formatting',
  }))
end

local function indent_whole_file()
  local view = vim.fn.winsaveview()
  vim.cmd('keepjumps normal! gg=G')
  vim.fn.winrestview(view)
end

local function format_or_indent_file()
  if lsp_supports_formatting() then
    vim.lsp.buf.format({ async = false, timeout_ms = 2000 })
  else
    indent_whole_file()
  end
end

local function indent_selection()
  vim.cmd('normal! gv=gv')
end

local function duplicate_current_line_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  vim.api.nvim_buf_set_lines(0, row, row, false, { line })
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

vim.keymap.set('n', '<leader>e', copy_current_line_diagnostic, { desc = 'Copy diagnostic on current line' })
vim.keymap.set('n', '<leader>F', format_or_indent_file, { desc = 'Format or indent file' })
vim.keymap.set('x', '<leader>F', indent_selection, { desc = 'Indent selection' })
vim.keymap.set('i', '<C-S-D>', duplicate_current_line_insert, { desc = 'Duplicate current line' })
vim.keymap.set('i', '<C-y><C-p>', duplicate_current_line_insert, { desc = 'Duplicate current line' })
-- VS Code-style Shift+Arrow selection.
vim.keymap.set('n', '<S-Left>', 'vh<C-g>', { noremap = true, desc = 'Select left' })
vim.keymap.set('n', '<S-Right>', 'vl<C-g>', { noremap = true, desc = 'Select right' })
vim.keymap.set('n', '<S-Up>', 'Vk<C-g>', { noremap = true, desc = 'Select line up' })
vim.keymap.set('n', '<S-Down>', 'Vj<C-g>', { noremap = true, desc = 'Select line down' })

vim.keymap.set('i', '<S-Left>', '<Esc>vh<C-g>', { noremap = true, desc = 'Select left' })
vim.keymap.set('i', '<S-Right>', '<Esc>vl<C-g>', { noremap = true, desc = 'Select right' })
vim.keymap.set('i', '<S-Up>', '<Esc>Vk<C-g>', { noremap = true, desc = 'Select line up' })
vim.keymap.set('i', '<S-Down>', '<Esc>Vj<C-g>', { noremap = true, desc = 'Select line down' })

vim.keymap.set('v', '<S-Left>', 'h', { noremap = true, desc = 'Extend selection left' })
vim.keymap.set('v', '<S-Right>', 'l', { noremap = true, desc = 'Extend selection right' })
vim.keymap.set('v', '<S-Up>', 'k', { noremap = true, desc = 'Extend selection up' })
vim.keymap.set('v', '<S-Down>', 'j', { noremap = true, desc = 'Extend selection down' })
vim.keymap.set('s', '<S-Left>', '<Left>', { noremap = true, desc = 'Extend selection left' })
vim.keymap.set('s', '<S-Right>', '<Right>', { noremap = true, desc = 'Extend selection right' })
vim.keymap.set('s', '<S-Up>', '<Up>', { noremap = true, desc = 'Extend selection up' })
vim.keymap.set('s', '<S-Down>', '<Down>', { noremap = true, desc = 'Extend selection down' })
-- VS Code-style Ctrl+Shift+Left/Right word selection.
vim.keymap.set('n', '<C-S-Left>', 'vb<C-g>', { noremap = true, desc = 'Select word left' })
vim.keymap.set('n', '<C-S-Right>', 've<C-g>', { noremap = true, desc = 'Select word right' })

vim.keymap.set('i', '<C-S-Left>', '<Esc>vb<C-g>', { noremap = true, desc = 'Select word left' })
vim.keymap.set('i', '<C-S-Right>', '<Esc>ve<C-g>', { noremap = true, desc = 'Select word right' })

vim.keymap.set('v', '<C-S-Left>', 'b', { noremap = true, desc = 'Extend selection word left' })
vim.keymap.set('v', '<C-S-Right>', 'e', { noremap = true, desc = 'Extend selection word right' })
vim.keymap.set('s', '<C-S-Left>', '<C-Left>', { noremap = true, desc = 'Extend selection word left' })
vim.keymap.set('s', '<C-S-Right>', '<C-Right>', { noremap = true, desc = 'Extend selection word right' })

-- VS Code-style selected-block indentation.
vim.keymap.set('v', '<Tab>', '>gv', { noremap = true, silent = true, desc = 'Indent selection' })
vim.keymap.set('v', '<S-Tab>', '<gv', { noremap = true, silent = true, desc = 'Outdent selection' })
-- Terminal-safe line movement.
vim.keymap.set('n', '<leader>k', ':move .-2<CR>==', { silent = true, desc = 'Move line up' })
vim.keymap.set('n', '<leader>j', ':move .+1<CR>==', { silent = true, desc = 'Move line down' })
vim.keymap.set('n', '<C-k>', ':move .-2<CR>==', { silent = true, desc = 'Move line up' })
vim.keymap.set('n', '<C-j>', ':move .+1<CR>==', { silent = true, desc = 'Move line down' })
vim.keymap.set('i', '<C-k>', '<Esc>:move .-2<CR>==gi', { silent = true, desc = 'Move line up' })
vim.keymap.set('i', '<C-j>', '<Esc>:move .+1<CR>==gi', { silent = true, desc = 'Move line down' })
vim.keymap.set('v', '<leader>k', ":move '<-2<CR>gv=gv", { silent = true, desc = 'Move selection up' })
vim.keymap.set('v', '<leader>j', ":move '>+1<CR>gv=gv", { silent = true, desc = 'Move selection down' })
vim.keymap.set('v', '<C-k>', ":move '<-2<CR>gv=gv", { silent = true, desc = 'Move selection up' })
vim.keymap.set('v', '<C-j>', ":move '>+1<CR>gv=gv", { silent = true, desc = 'Move selection down' })
-- VS Code-style Shift+Home/End selection.
vim.keymap.set('n', '<S-Home>', 'v^<C-g>', { noremap = true, desc = 'Select to first nonblank' })
vim.keymap.set('n', '<S-End>', 'v$<C-g>', { noremap = true, desc = 'Select to end of line' })

vim.keymap.set('i', '<S-Home>', '<Esc>v^<C-g>', { noremap = true, desc = 'Select to first nonblank' })
vim.keymap.set('i', '<S-End>', '<Esc>v$<C-g>', { noremap = true, desc = 'Select to end of line' })

vim.keymap.set('v', '<S-Home>', '^', { noremap = true, desc = 'Extend selection to first nonblank' })
vim.keymap.set('v', '<S-End>', '$', { noremap = true, desc = 'Extend selection to end of line' })
vim.keymap.set('s', '<S-Home>', '<Home>', { noremap = true, desc = 'Extend selection to first nonblank' })
vim.keymap.set('s', '<S-End>', '<End>', { noremap = true, desc = 'Extend selection to end of line' })

