@{
  Version = 1
  # Execution order is explicit. Requires below records technical prerequisites.
  Order = @(
    'checkout', 'packages', 'compiler', 'nvim-runtime', 'zig',
    'codex-cli', 'codex-instructions', 'zig-wrappers', 'nvim-config',
    'profile-import', 'nvim-plugins', 'nvim-mason', 'nvim-parsers'
  )
  Steps = @{
    checkout = @{ Label = 'Set DevKit checkout location'; Script = 'profile.ps1'; Handler = 'Install-MeowskyCheckoutLocation'; Requires = @() }
    packages = @{ Label = 'Install or verify Windows packages'; Script = 'packages.ps1'; Handler = 'Install-MeowskyWindowsPackages'; Requires = @() }
    compiler = @{ Label = 'Install or verify C compiler and debugger'; Script = 'compiler.ps1'; Handler = 'Install-MeowskyCCompiler'; Requires = @('packages') }
    'nvim-runtime' = @{ Label = 'Repair Neovim runtime environment'; Script = 'nvim.ps1'; Handler = 'Install-MeowskyNvimRuntimeRepair'; Requires = @() }
    zig = @{ Label = 'Resolve Zig compiler'; Script = 'zig.ps1'; Handler = 'Install-MeowskyZig'; Requires = @() }
    'codex-cli' = @{ Label = 'Check Codex CLI'; Script = 'codex.ps1'; Handler = 'Install-MeowskyCodexCli'; Requires = @('packages') }
    'codex-instructions' = @{ Label = 'Install Codex global instructions'; Script = 'codex.ps1'; Handler = 'Install-MeowskyCodexInstructions'; Requires = @() }
    'zig-wrappers' = @{ Label = 'Create Zig compiler wrappers'; Script = 'zig.ps1'; Handler = 'Install-MeowskyZigWrappers'; Requires = @('zig') }
    'nvim-config' = @{ Label = 'Install Neovim config'; Script = 'nvim.ps1'; Handler = 'Install-MeowskyNvimConfig'; Requires = @() }
    'profile-import' = @{ Label = 'Update PowerShell profile'; Script = 'profile.ps1'; Handler = 'Install-MeowskyProfile'; Requires = @('checkout') }
    'nvim-plugins' = @{ Label = 'Sync Neovim plugins with lazy.nvim'; Script = 'nvim.ps1'; Handler = 'Install-MeowskyNvimPlugins'; Requires = @('nvim-config', 'zig-wrappers', 'packages') }
    'nvim-mason' = @{ Label = 'Install Mason language servers'; Script = 'nvim.ps1'; Handler = 'Install-MeowskyMason'; Requires = @('nvim-plugins') }
    'nvim-parsers' = @{ Label = 'Install Treesitter parsers'; Script = 'nvim.ps1'; Handler = 'Install-MeowskyTreesitter'; Requires = @('nvim-plugins') }
  }
}
