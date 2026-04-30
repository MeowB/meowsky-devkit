# New PC Dev Setup For Windows

Use this file to recreate a portable Windows developer setup on a new PC or laptop.

The main focus is a general-purpose Neovim config for web and scripting work. It adds:

- Theme/colors with `tokyonight.nvim`
- Treesitter highlighting for Lua, Vim, JavaScript, TypeScript, TSX, JSON, HTML, CSS, and Markdown
- LSP autocomplete through Mason
- `Ctrl+Space` completion
- `Ctrl+Backspace` / `Ctrl+H` delete previous word in insert mode
- Auto-close brackets, parentheses, braces, and quotes
- VS Code-style Shift+Arrow and Shift+Home/End selection mappings
- Ctrl+Shift+Arrow word/block selection mappings
- VS Code-style Alt+Arrow line/block movement
- Visual-mode `Tab` / `Shift+Tab` selected-block indentation

## Install System Tools

Run these in PowerShell:

```powershell
winget install --id Neovim.Neovim --exact --accept-package-agreements --accept-source-agreements
winget install --id Git.Git --exact --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli --exact --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS --exact --accept-package-agreements --accept-source-agreements
winget install --id tree-sitter.tree-sitter-cli --exact --accept-package-agreements --accept-source-agreements
winget install --id zig.zig --exact --accept-package-agreements --accept-source-agreements
winget install --id eza-community.eza --exact --accept-package-agreements --accept-source-agreements
winget install --id JohnMacFarlane.Pandoc --exact --accept-package-agreements --accept-source-agreements
```

Open a new terminal after installing so `nvim`, `git`, `gh`, `node`, `npm`, `tree-sitter`, `zig`, `eza`, and `pandoc` are available on `PATH`.

If `pandoc` is installed but not available on `PATH`, the `meowsky md` helper also checks the common Windows install locations:

- `C:\Program Files\Pandoc\pandoc.exe`
- `%LOCALAPPDATA%\Pandoc\pandoc.exe`

If `nvim` is installed but the command is not found, add this folder to your user `Path`:

```text
C:\Program Files\Neovim\bin
```

## Create Zig Compiler Wrapper

Treesitter parser compilation on Windows may pass an MSVC target string that Zig does not accept. Create local wrapper scripts:

```powershell
$tools = "$env:LOCALAPPDATA\nvim-tools"
New-Item -ItemType Directory -Force $tools | Out-Null

$zigPath = (Get-Command zig.exe -ErrorAction SilentlyContinue).Source
if (-not $zigPath) {
  $zigPath = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter zig.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $zigPath) {
  throw "zig.exe was not found. Install Zig and open a new terminal."
}

@"
`$zig = '$zigPath'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig cc @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\cc.ps1"

@"
`$zig = '$zigPath'
`$out = New-Object System.Collections.Generic.List[string]
`$skipNext = `$false
foreach (`$arg in `$args) {
  if (`$skipNext) {
    `$skipNext = `$false
    continue
  }
  if (`$arg -eq '-target' -or `$arg -eq '--target') {
    `$skipNext = `$true
    continue
  }
  if (`$arg -like '*x86_64-pc-windows-msvc*') {
    continue
  }
  `$out.Add(`$arg)
}
& `$zig c++ @out
exit `$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 "$tools\c++.ps1"

Set-Content -Encoding ASCII "$tools\cc.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\cc.ps1`" %*"
Set-Content -Encoding ASCII "$tools\c++.cmd" "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$tools\c++.ps1`" %*"
```

## Create Neovim Config

Create this file:

```text
%LOCALAPPDATA%\nvim\init.lua
```

Full content:

```lua
-- Basic editor defaults
vim.g.mapleader = ' '
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

-- Tool paths. Prefer regular PATH entries, with WinGet package folders as a fallback.
local function first_existing_dir(candidates)
  for _, dir in ipairs(candidates) do
    if dir and dir ~= '' and vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
end

local function exe_dir(name)
  local path = vim.fn.exepath(name)
  if path ~= '' then
    return vim.fn.fnamemodify(path, ':h')
  end
end

local localappdata = vim.env.LOCALAPPDATA or vim.fn.expand('~/AppData/Local')
local nvim_tools_dir = localappdata .. '/nvim-tools'
local winget_packages = localappdata .. '/Microsoft/WinGet/Packages'
local tree_sitter_dir = first_existing_dir({
  exe_dir('tree-sitter'),
  vim.fn.glob(winget_packages .. '/tree-sitter.tree-sitter-cli_*', false, true)[1],
})
local zig_dir = first_existing_dir({
  exe_dir('zig'),
  vim.fn.fnamemodify(vim.fn.glob(winget_packages .. '/zig.zig_*/**/zig.exe', false, true)[1] or '', ':h'),
})

local path_parts = { nvim_tools_dir, tree_sitter_dir, zig_dir, vim.env.PATH }
vim.env.PATH = table.concat(vim.tbl_filter(function(part)
  return part and part ~= ''
end, path_parts), ';')
vim.env.CC = nvim_tools_dir .. '/cc.cmd'
vim.env.CXX = nvim_tools_dir .. '/c++.cmd'

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
        treesitter.install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown' })
      end

      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'lua', 'vim', 'javascript', 'typescript', 'typescriptreact', 'json', 'html', 'css', 'markdown' },
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

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-BS>'] = cmp.mapping(function()
      if cmp.visible() then
        cmp.close()
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>', true, false, true), 'n', false)
    end, { 'i' }),
    ['<C-H>'] = cmp.mapping(function()
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
  ensure_installed = { 'ts_ls', 'eslint', 'html', 'cssls', 'jsonls', 'lua_ls' },
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
```

## Bootstrap Plugins, LSPs, And Parsers

Run:

```powershell
nvim --headless "+Lazy! sync" +qa
nvim --headless "+MasonInstall typescript-language-server eslint-lsp html-lsp css-lsp json-lsp lua-language-server" +qa
nvim --headless "+lua require('nvim-treesitter').install({ 'lua', 'vim', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'css', 'markdown' }):wait(300000)" +qa
nvim --headless +qa
```

## Verify

Inside Neovim:

```vim
:Lazy
:Mason
:LspInfo
```

Useful checks:

```powershell
nvim --headless "+checkhealth" "+qa"
nvim --headless "+lua print(vim.fn.maparg('<A-Up>', 'v'))" "+qa"
nvim --headless "+lua print(vim.fn.maparg('<Tab>', 'v'))" "+qa"
```

Expected:

- `:Lazy` shows plugins installed
- `:Mason` shows the language servers installed
- `Alt+Up` in visual mode maps to moving the selection up
- `Tab` in visual mode maps to indenting the selection

## Clean Project Tree

Add this shortcut to your PowerShell profile:

```powershell
notepad $PROFILE
```

Paste this function:

```powershell
function ptree {
  param(
    [int]$Level = 3
  )

  $eza = (Get-Command eza.exe -ErrorAction SilentlyContinue).Source
  if (-not $eza -or (Get-Item -LiteralPath $eza -ErrorAction SilentlyContinue).Length -eq 0) {
    $eza = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter eza.exe -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $eza) {
    throw "eza.exe was not found. Install it with: winget install --id eza-community.eza --exact"
  }

  & $eza -T -L $Level --color=never -I "node_modules|.git|dist|build|coverage|.next|.nuxt|.turbo|.vite|.cache" .
}
```

Open a new terminal, then use:

```powershell
ptree
```

For a shorter overview:

```powershell
ptree 2
```

## Meowsky Workspace Shortcut

The `meowsky` command is a folder-level workflow shortcut, not a project-specific shortcut. It replaces the earlier `dev` command name so the workflow is safe and unambiguous on both Windows and Linux. On Linux, `/dev` is a real system directory for device files, so avoid using `/dev` as a project folder.

Expected behavior:

- `meowsky` jumps to the main workspace folder.
- `meowsky ./` opens the fullscreen split terminal layout for the current project folder, but only when the current folder is inside the main workspace folder.
- If `meowsky ./` is run from somewhere unrelated, it opens the layout at the main workspace folder instead of accidentally starting Codex in the wrong place.
- `meowsky some-folder` first tries `some-folder` as typed, then tries `some-folder` inside the main workspace folder.

The main workspace folder is called the work root. The function resolves it in this order:

1. `$env:WORK_HOME` on Windows, or `$WORK_HOME` on Linux, if set
2. `F:\dev` on Windows if it already exists, for compatibility with the current machine
3. `$HOME\work` on Windows, or `$HOME/work` on Linux, created automatically if needed

This makes the setup portable. On the current machine the expected root is `F:\dev`. On a new PC without an `F:` drive, the function will safely create something like `C:\Users\<you>\work` on Windows or `/home/<you>/work` on Linux.

To force a specific location on Windows, set `WORK_HOME` once:

```powershell
[Environment]::SetEnvironmentVariable('WORK_HOME', 'D:\work', 'User')
```

Then open a new terminal.

Add this function to your PowerShell profile:

```powershell
function meowsky {
  param(
    [string]$Action,
    [string]$Target
  )

  function Get-WorkRoot {
    if ($env:WORK_HOME) {
      $root = $env:WORK_HOME
    } elseif (Test-Path -LiteralPath 'F:\dev') {
      $root = 'F:\dev'
    } else {
      $root = Join-Path $HOME 'work'
    }

    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return (Resolve-Path -LiteralPath $root).Path
  }

  function Resolve-MeowskyPath {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Target,

      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    if (Test-Path -LiteralPath $Target) {
      return (Resolve-Path -LiteralPath $Target).Path
    }

    $rootTarget = Join-Path $Root $Target
    if (Test-Path -LiteralPath $rootTarget) {
      return (Resolve-Path -LiteralPath $rootTarget).Path
    }

    throw "Path was not found: $Target"
  }

  function Open-MeowskyMarkdownPreview {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Target
    )

    $pandoc = (Get-Command pandoc.exe -ErrorAction SilentlyContinue).Source
    if (-not $pandoc -and (Test-Path -LiteralPath 'C:\Program Files\Pandoc\pandoc.exe')) {
      $pandoc = 'C:\Program Files\Pandoc\pandoc.exe'
    }
    if (-not $pandoc -and (Test-Path -LiteralPath "$env:LOCALAPPDATA\Pandoc\pandoc.exe")) {
      $pandoc = "$env:LOCALAPPDATA\Pandoc\pandoc.exe"
    }

    if (-not $pandoc) {
      throw 'pandoc was not found. Install it with: winget install --id JohnMacFarlane.Pandoc --exact'
    }

    $previewDir = Join-Path ([System.IO.Path]::GetTempPath()) 'meowsky-preview'
    New-Item -ItemType Directory -Force -Path $previewDir | Out-Null

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Target) -replace '[^a-zA-Z0-9._-]', '_'
    if (-not $baseName) {
      $baseName = 'preview'
    }

    $htmlPath = Join-Path $previewDir "$baseName.html"
    & $pandoc --standalone --from gfm --metadata title=Preview --output $htmlPath $Target
    if ($LASTEXITCODE -ne 0) {
      throw "pandoc failed to render: $Target"
    }

    Start-Process $htmlPath
  }

  function Get-MeowskyPromptTree {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Root
    )

    $ignoredNames = @(
      'node_modules',
      '.git',
      'dist',
      'build',
      'coverage',
      '.next',
      '.nuxt',
      '.turbo',
      '.vite',
      '.cache'
    )

    $items = Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
      Where-Object { $ignoredNames -notcontains $_.Name } |
      Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('.')

    for ($i = 0; $i -lt $items.Count; $i++) {
      $prefix = if ($i -eq $items.Count - 1) { '`-- ' } else { '|-- ' }
      $lines.Add("$prefix$($items[$i].Name)")
    }

    return $lines -join "`r`n"
  }

  $workRoot = Get-WorkRoot

  if ($Action) {
    $normalizedAction = $Action.ToLowerInvariant()

    if ($normalizedAction -in @('md', 'markdown')) {
      if (-not $Target) {
        throw "Usage: meowsky md <file.md>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Open-MeowskyMarkdownPreview -Target $targetPath
      return
    }

    if ($normalizedAction -eq 'pdf') {
      if (-not $Target) {
        throw "Usage: meowsky pdf <file.pdf>"
      }

      $targetPath = Resolve-MeowskyPath -Target $Target -Root $workRoot
      Start-Process $targetPath
      return
    }
  }

  if ($Action -eq './' -or $Action -eq '.') {
    $current = (Get-Location).Path
    $workRootWithSlash = $workRoot.TrimEnd('\') + '\'
    $currentWithSlash = $current.TrimEnd('\') + '\'

    $root = if (
      $current.Equals($workRoot, [StringComparison]::OrdinalIgnoreCase) -or
      $currentWithSlash.StartsWith($workRootWithSlash, [StringComparison]::OrdinalIgnoreCase)
    ) {
      $current
    } else {
      $workRoot
    }

    $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source

    if (-not $wt) {
      throw 'Windows Terminal (wt.exe) was not found.'
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $promptTree = Get-MeowskyPromptTree -Root $root
    $codexPrompt = @"
Session context ($today):
Workspace root: $root

Top-level project tree:
$promptTree

Start by giving me a scoped orientation of this codebase from the tree above. Keep it concise: identify the likely main parts, what you would inspect first, and any setup files that look important. Do not make code changes unless I ask.
"@

    $promptEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexPrompt))
    $codexScript = ". `$PROFILE`r`n`$prompt = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$promptEncoded'))`r`ncodex -C . `$prompt`r`n"
    $treeScript = ". `$PROFILE`r`nptree`r`n"
    $meowskyScript = @(
      "Write-Host ''",
      "Write-Host ' /\_/\\   Meowsky' -ForegroundColor Green",
      "Write-Host '( o.o )  work mode' -ForegroundColor Green",
      "Write-Host ' > ^ <' -ForegroundColor Green",
      "Write-Host (Get-Location).Path -ForegroundColor Cyan"
    ) -join "`r`n"

    $codexEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codexScript))
    $treeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($treeScript))
    $meowskyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($meowskyScript))

    Set-Location $root
    Write-Host "Opening Meowsky layout for $root"

    $wtArgs = @(
      '--fullscreen',
      '-w', '-1',
      'new-tab', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $codexEncoded, ';',
      'split-pane', '-V', '--size', '0.70', '-d', $root, ';',
      'split-pane', '-H', '--size', '0.22', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $meowskyEncoded, ';',
      'move-focus', 'up', ';',
      'split-pane', '-V', '--size', '0.60', '-d', $root, 'powershell.exe', '-NoLogo', '-NoExit', '-EncodedCommand', $treeEncoded, ';',
      'split-pane', '-V', '--size', '0.45', '-d', $root, ';',
      'move-focus', 'left', ';',
      'move-focus', 'left', ';',
      'move-focus', 'left'
    )

    & $wt @wtArgs
    return
  }

  if ($Action) {
    if (Test-Path -LiteralPath $Action) {
      Set-Location $Action
      return
    }

    $workPath = Join-Path $workRoot $Action
    if (Test-Path -LiteralPath $workPath) {
      Set-Location $workPath
      return
    }

    throw "Path was not found: $Action"
    return
  }

  Set-Location $workRoot
}
```

Add menu-style Tab selection and project-folder completion:

```powershell
if (Get-Module -ListAvailable -Name PSReadLine) {
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

$meowskyCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

  function Get-MeowskyCompletionRoot {
    if ($env:WORK_HOME) {
      $root = $env:WORK_HOME
    } elseif (Test-Path -LiteralPath 'F:\dev') {
      $root = 'F:\dev'
    } else {
      $root = Join-Path $HOME 'work'
    }

    if (Test-Path -LiteralPath $root) {
      return (Resolve-Path -LiteralPath $root).Path
    }
  }

  $builtIns = @('.', './', 'md', 'markdown', 'pdf')
  foreach ($item in $builtIns) {
    if ($item -like "$wordToComplete*") {
      [System.Management.Automation.CompletionResult]::new($item, $item, 'ParameterValue', $item)
    }
  }

  $root = Get-MeowskyCompletionRoot
  if (-not $root) {
    return
  }

  Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$wordToComplete*" } |
    Sort-Object Name |
    ForEach-Object {
      $completionText = if ($_.Name -match '\s') { "'$($_.Name)'" } else { $_.Name }
      [System.Management.Automation.CompletionResult]::new($completionText, $_.Name, 'ParameterValue', $_.FullName)
    }
}

Register-ArgumentCompleter -CommandName meowsky -ParameterName Action -ScriptBlock $meowskyCompleter
Register-ArgumentCompleter -CommandName dev -ParameterName Action -ScriptBlock $meowskyCompleter
```

Optional Windows compatibility alias:

```powershell
Set-Alias dev meowsky
```

Use the alias only if you still want the old command to work locally. New setup docs should prefer `meowsky`.

Usage:

```powershell
meowsky          # go to $env:WORK_HOME, F:\dev, or $HOME\work
meowsky my-app   # go to .\my-app, or to my-app inside the work root
meowsky ./       # open a fullscreen Windows Terminal layout
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
```

Recommended project flow:

```powershell
meowsky
cd user-management-CRM
meowsky ./
```

Path examples:

```powershell
# If WORK_HOME is not set and F:\dev exists:
meowsky
# goes to F:\dev

# From F:\dev\user-management-CRM:
meowsky ./
# opens the layout at F:\dev\user-management-CRM

# From C:\Users\<you>\Downloads:
meowsky ./
# opens the layout at the work root, not Downloads

# From anywhere:
meowsky user-management-CRM
# goes to <work-root>\user-management-CRM if that folder exists

# Preview a Markdown file as rendered HTML in the default browser:
meowsky md .\README.md

# Open a PDF with the default PDF viewer:
meowsky pdf .\docs\spec.pdf
```

Why `meowsky ./` checks the folder:

The split layout automatically starts `codex ./` in the selected root. That is useful inside a project, but risky from random folders such as Downloads, Desktop, or a temporary extraction directory. The boundary check keeps the layout anchored to the work root unless the current directory is already inside it.

`meowsky ./` pane roles:

- left full-height pane: runs `codex ./` in the new fullscreen window
- middle-left pane: shell at the project root, ready for `nvim`
- middle-right pane: runs `ptree`
- right pane: shell at the project root
- bottom pane: project-root shell with a compact `Meowsky` banner

Preview notes:

- `meowsky md <file.md>` uses Pandoc to render GitHub-flavored Markdown to a temporary standalone HTML file, then opens it in the default browser.
- `meowsky pdf <file.pdf>` opens the PDF with the system default PDF viewer.
- Preview paths are resolved first as typed, then relative to the work root.
- Markdown preview files are written under the system temp directory in `meowsky-preview`.

## Linux Or Ubuntu Meowsky Shortcut

If you want the one-command Linux bootstrap, run:

```bash
bash ./scripts/install-meowsky.sh
```

The same workflow can work on Ubuntu with a shell function and `tmux`.

To force a specific work root on Linux, add this to `~/.bashrc` or `~/.zshrc`:

```bash
export WORK_HOME="$HOME/work"
```

Install `tmux` if it is not already installed:

```bash
sudo apt update
sudo apt install -y tmux pandoc xdg-utils
```

Add this function to `~/.bashrc` or `~/.zshrc`:

```bash
meowsky() {
  local action="$1"
  local target="$2"
  local work_root="${WORK_HOME:-$HOME/work}"

  mkdir -p "$work_root"
  work_root="$(cd "$work_root" && pwd -P)"

  meowsky_resolve_path() {
    local candidate="$1"

    if [ -e "$candidate" ]; then
      cd "$(dirname "$candidate")" >/dev/null 2>&1 || return 1
      printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")"
      return 0
    fi

    if [ -e "$work_root/$candidate" ]; then
      cd "$(dirname "$work_root/$candidate")" >/dev/null 2>&1 || return 1
      printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")"
      return 0
    fi

    return 1
  }

  if [ "$action" = "md" ] || [ "$action" = "markdown" ]; then
    if [ -z "$target" ]; then
      echo "Usage: meowsky md <file.md>" >&2
      return 1
    fi

    if ! command -v pandoc >/dev/null 2>&1; then
      echo "pandoc was not found. Install it with: sudo apt install -y pandoc" >&2
      return 1
    fi

    if ! command -v xdg-open >/dev/null 2>&1; then
      echo "xdg-open was not found. Install it with: sudo apt install -y xdg-utils" >&2
      return 1
    fi

    local target_path
    target_path="$(meowsky_resolve_path "$target")" || {
      echo "Path was not found: $target" >&2
      return 1
    }

    local preview_dir="${TMPDIR:-/tmp}/meowsky-preview"
    mkdir -p "$preview_dir"

    local name
    name="$(basename "${target_path%.*}" | tr -cd '[:alnum:]_.-')"
    if [ -z "$name" ]; then
      name="preview"
    fi

    local html_path="$preview_dir/$name.html"
    pandoc --standalone --from gfm --metadata title=Preview --output "$html_path" "$target_path" || return
    xdg-open "$html_path" >/dev/null 2>&1 &
    return
  fi

  if [ "$action" = "pdf" ]; then
    if [ -z "$target" ]; then
      echo "Usage: meowsky pdf <file.pdf>" >&2
      return 1
    fi

    if ! command -v xdg-open >/dev/null 2>&1; then
      echo "xdg-open was not found. Install it with: sudo apt install -y xdg-utils" >&2
      return 1
    fi

    local target_path
    target_path="$(meowsky_resolve_path "$target")" || {
      echo "Path was not found: $target" >&2
      return 1
    }

    xdg-open "$target_path" >/dev/null 2>&1 &
    return
  fi

  if [ "$action" = "./" ] || [ "$action" = "." ]; then
    local current
    current="$(pwd -P)"

    local root
    case "$current/" in
      "$work_root"/*) root="$current" ;;
      *) root="$work_root" ;;
    esac

    if ! command -v tmux >/dev/null 2>&1; then
      echo "tmux was not found. Install it with: sudo apt install -y tmux" >&2
      return 1
    fi

    cd "$root" || return

    local name
    name="$(basename "$root" | tr -cd '[:alnum:]_-')"
    local session="meowsky-$name"
    if tmux has-session -t "$session" 2>/dev/null; then
      tmux attach -t "$session"
      return
    fi

    local today
    today="$(date +%F)"
    local tree
    if command -v ptree >/dev/null 2>&1; then
      tree="$(ptree 1)"
    else
      tree="$(find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)"
    fi

    local codex_prompt
    codex_prompt="Session context ($today):
Workspace root: $root

Top-level project tree:
$tree

Start by giving me a scoped orientation of this codebase from the tree above. Keep it concise: identify the likely main parts, what you would inspect first, and any setup files that look important. Do not make code changes unless I ask."

    tmux new-session -d -s "$session" -c "$root" codex -C . "$codex_prompt"
    tmux split-window -h -t "$session:0" -c "$root"
    tmux split-window -v -t "$session:0.1" -c "$root" 'ptree 2 2>/dev/null || find . -maxdepth 2 -type d | sort'
    tmux select-pane -t "$session:0.0"
    tmux attach -t "$session"
    return
  fi

  if [ -n "$action" ]; then
    if [ -d "$action" ]; then
      cd "$action" || return
      return
    fi

    if [ -d "$work_root/$action" ]; then
      cd "$work_root/$action" || return
      return
    fi

    echo "Path was not found: $action" >&2
    return 1
  fi

  cd "$work_root" || return
}
```

Optional Linux compatibility alias:

```bash
alias dev='meowsky'
```

Then reload the shell:

```bash
source ~/.bashrc
```

Usage:

```bash
meowsky          # go to $WORK_HOME or $HOME/work
meowsky my-app   # go to ./my-app, or to my-app inside the work root
meowsky ./       # open a tmux layout
meowsky md ./README.md
meowsky pdf ./docs/spec.pdf
```

Recommended project flow:

```bash
meowsky
cd user-management-CRM
meowsky ./
```

Linux layout notes:

- The left pane starts `codex ./` at the selected root.
- The right pane is a shell at the selected root.
- The lower-right pane runs `ptree 2` if available, otherwise a compact `find` fallback.
- If the named tmux session already exists, `meowsky ./` reattaches to it instead of creating a duplicate session.

Linux preview notes:

- `meowsky md <file.md>` uses Pandoc to render GitHub-flavored Markdown to a temporary standalone HTML file, then opens it with `xdg-open`.
- `meowsky pdf <file.pdf>` opens the PDF with `xdg-open`.
- Preview paths are resolved first as typed, then relative to the work root.
- Markdown preview files are written under `${TMPDIR:-/tmp}/meowsky-preview`.

## Optional Add-Ons

For Prisma projects, add `prisma` to the Treesitter install list and `prismals` to `ensure_installed`, then install the server:

```powershell
nvim --headless "+MasonInstall prisma-language-server" +qa
```

For project-specific import alias completion such as `@/...`, prefer configuring that in the project itself through `tsconfig.json` / `jsconfig.json` path aliases and the TypeScript language server.

## Notes

- `Ctrl+Backspace` is terminal-dependent. If it does not work, try `Ctrl+H`.
- Shift+Arrow, Ctrl+Shift+Arrow, Shift+Home/End, and Alt+Arrow are terminal-dependent. If Windows Terminal does not pass those keycodes correctly, the terminal profile may need keybinding changes.
- `Ctrl+Shift+Left` / `Ctrl+Shift+Right` selects by word. `Ctrl+Shift+Up` / `Ctrl+Shift+Down` selects by block/paragraph.
- In visual mode, `Tab` indents the selected block and `Shift+Tab` outdents it while preserving the selection.
- `Alt+Up` / `Alt+Down` moves the current line in normal/insert mode and moves the selected block in visual mode.



