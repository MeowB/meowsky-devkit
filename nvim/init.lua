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

vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { desc = 'Hover docs' })
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename symbol' })
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
vim.keymap.set('n', '<leader>f', function()
  vim.lsp.buf.format({ async = true })
end, { desc = 'Format file' })
-- VS Code-style Shift+Arrow selection.
vim.keymap.set('n', '<S-Left>', 'vh', { noremap = true, desc = 'Select left' })
vim.keymap.set('n', '<S-Right>', 'vl', { noremap = true, desc = 'Select right' })
vim.keymap.set('n', '<S-Up>', 'Vk', { noremap = true, desc = 'Select line up' })
vim.keymap.set('n', '<S-Down>', 'Vj', { noremap = true, desc = 'Select line down' })

vim.keymap.set('i', '<S-Left>', '<Esc>vhi', { noremap = true, desc = 'Select left' })
vim.keymap.set('i', '<S-Right>', '<Esc>vli', { noremap = true, desc = 'Select right' })
vim.keymap.set('i', '<S-Up>', '<Esc>Vki', { noremap = true, desc = 'Select line up' })
vim.keymap.set('i', '<S-Down>', '<Esc>Vji', { noremap = true, desc = 'Select line down' })

vim.keymap.set('v', '<S-Left>', 'h', { noremap = true, desc = 'Extend selection left' })
vim.keymap.set('v', '<S-Right>', 'l', { noremap = true, desc = 'Extend selection right' })
vim.keymap.set('v', '<S-Up>', 'k', { noremap = true, desc = 'Extend selection up' })
vim.keymap.set('v', '<S-Down>', 'j', { noremap = true, desc = 'Extend selection down' })
-- VS Code-style Ctrl+Shift+Arrow selection.
vim.keymap.set('n', '<C-S-Left>', 'vb', { noremap = true, desc = 'Select word left' })
vim.keymap.set('n', '<C-S-Right>', 've', { noremap = true, desc = 'Select word right' })
vim.keymap.set('n', '<C-S-Up>', 'V{', { noremap = true, desc = 'Select block up' })
vim.keymap.set('n', '<C-S-Down>', 'V}', { noremap = true, desc = 'Select block down' })

vim.keymap.set('i', '<C-S-Left>', '<Esc>vb', { noremap = true, desc = 'Select word left' })
vim.keymap.set('i', '<C-S-Right>', '<Esc>ve', { noremap = true, desc = 'Select word right' })
vim.keymap.set('i', '<C-S-Up>', '<Esc>V{', { noremap = true, desc = 'Select block up' })
vim.keymap.set('i', '<C-S-Down>', '<Esc>V}', { noremap = true, desc = 'Select block down' })

vim.keymap.set('v', '<C-S-Left>', 'b', { noremap = true, desc = 'Extend selection word left' })
vim.keymap.set('v', '<C-S-Right>', 'e', { noremap = true, desc = 'Extend selection word right' })
vim.keymap.set('v', '<C-S-Up>', '{', { noremap = true, desc = 'Extend selection block up' })
vim.keymap.set('v', '<C-S-Down>', '}', { noremap = true, desc = 'Extend selection block down' })

-- VS Code-style selected-block indentation.
vim.keymap.set('v', '<Tab>', '>gv', { noremap = true, silent = true, desc = 'Indent selection' })
vim.keymap.set('v', '<S-Tab>', '<gv', { noremap = true, silent = true, desc = 'Outdent selection' })
-- VS Code-style Alt+Arrow line movement.
vim.keymap.set('n', '<A-Up>', ':move .-2<CR>==', { silent = true, desc = 'Move line up' })
vim.keymap.set('n', '<A-Down>', ':move .+1<CR>==', { silent = true, desc = 'Move line down' })
vim.keymap.set('i', '<A-Up>', '<Esc>:move .-2<CR>==gi', { silent = true, desc = 'Move line up' })
vim.keymap.set('i', '<A-Down>', '<Esc>:move .+1<CR>==gi', { silent = true, desc = 'Move line down' })
vim.keymap.set('v', '<A-Up>', ":move '<-2<CR>gv=gv", { silent = true, desc = 'Move selection up' })
vim.keymap.set('v', '<A-Down>', ":move '>+1<CR>gv=gv", { silent = true, desc = 'Move selection down' })
-- VS Code-style Shift+Home/End selection.
vim.keymap.set('n', '<S-Home>', 'v^', { noremap = true, desc = 'Select to first nonblank' })
vim.keymap.set('n', '<S-End>', 'v$', { noremap = true, desc = 'Select to end of line' })
vim.keymap.set('n', '<C-S-Home>', 'vgg', { noremap = true, desc = 'Select to top of file' })
vim.keymap.set('n', '<C-S-End>', 'vG', { noremap = true, desc = 'Select to bottom of file' })

vim.keymap.set('i', '<S-Home>', '<Esc>v^', { noremap = true, desc = 'Select to first nonblank' })
vim.keymap.set('i', '<S-End>', '<Esc>v$', { noremap = true, desc = 'Select to end of line' })
vim.keymap.set('i', '<C-S-Home>', '<Esc>vgg', { noremap = true, desc = 'Select to top of file' })
vim.keymap.set('i', '<C-S-End>', '<Esc>vG', { noremap = true, desc = 'Select to bottom of file' })

vim.keymap.set('v', '<S-Home>', '^', { noremap = true, desc = 'Extend selection to first nonblank' })
vim.keymap.set('v', '<S-End>', '$', { noremap = true, desc = 'Extend selection to end of line' })
vim.keymap.set('v', '<C-S-Home>', 'gg', { noremap = true, desc = 'Extend selection to top of file' })
vim.keymap.set('v', '<C-S-End>', 'G', { noremap = true, desc = 'Extend selection to bottom of file' })

