-- Basic editor defaults
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
