# Meowsky

Personal Windows-first devkit for web work, C programming, scripting, and fast project starts.

It is a small repo, but it does three concrete things:

1. Sets up the machine with the tools this workflow expects.
2. Sets up Neovim for web development with native editing controls.
3. Provides a `meowsky` terminal shortcut that opens a project-aware Codex layout.

## What It Does

| Area | Behavior |
| --- | --- |
| Machine setup | Installs the core Windows tools this workflow expects: Neovim, Git, Node.js, tree-sitter, Zig, GCC/GDB, eza, and Pandoc |
| GitHub CLI | Optional, only if you want terminal-first GitHub repo workflows |
| Editor setup | Loads a personal Neovim config with web and C language support, LSPs, Treesitter, and completion |
| Workspace flow | Adds `meowsky` to PowerShell so you can enter the workspace or dev district, open the fullscreen project layout, or start Codex directly |
| Codex instructions | Installs durable behavioral rules once in Codex's global `AGENTS.md`; project `AGENTS.md` files add local guidance, while the launch prompt supplies session context |
| Preview helpers | Uses Pandoc to preview Markdown and the default PDF viewer for PDFs |
| Linux support | Includes a lighter Ubuntu version using `tmux` |

## The Feel

This setup is meant to feel like:

- a personal dev machine template
- a project starter for coding sessions
- a Neovim workflow using native movement and selection controls
- a shareable repo that is easy to clone, inspect, and adapt later

## Repo Map

```text
.
|-- README.md
|-- docs/
|   |-- architecture.md
|   `-- new-pc-dev-setup.md
|-- core/                   # shared runtime infrastructure and CLI
|-- features/               # implementations, manifests and help
|   |-- bach/
|   |-- codex/
|   |-- color/
|   |-- identity/
|   |-- launchpad/
|   |-- matrix/
|   |-- md/
|   |-- pdf/
|   |-- tree/
|   `-- workspace/
|-- nvim/
|   |-- init.lua             # editor configuration
|   `-- lua/meowsky/c.lua    # C build, run, navigation, and GDB commands
|-- powershell/
|   `-- profile.ps1
|-- shell/
|   `-- meowsky.sh           # Linux runtime bootstrap
|-- tests/                  # behavior preservation checks
`-- scripts/
    |-- install-windows.ps1          # Windows setup entry point
    |-- installer/
    |   |-- windows-features.psd1 # explicit installation order and prerequisites
    |   |-- windows-environment.ps1 # PATH and environment operations
    |   |-- windows-files.ps1 # guarded profile and Neovim file updates
    |   |-- windows-process.ps1 # native commands and package operations
    |   |-- windows-verification.ps1 # fresh-shell and editor checks
    |   `-- features/       # package, compiler, Zig, Codex, Neovim, profile installers
    `-- install-linux.sh
```

## Quick Start

### Windows

Run the one-command bootstrap:

```powershell
.\scripts\install-windows.ps1
```

Run it from the checkout you want to keep. It installs or verifies the core tools and Codex CLI, copies the Neovim config, manages one Meowsky import in each installed PowerShell edition's user profile, installs global Codex instructions when no global `AGENTS.md` exists, and sets `MEOWSKY_DEVKIT_HOME` for the session-context template. Existing user instructions are preserved and reported. The installer verifies command discovery, a temporary C build, and headless C/TypeScript editor support before reporting success. Open a new terminal afterwards so it inherits the persistent PATH and profile changes.

On Windows, the workspace defaults to `C:\meowsky`. To use another workspace, set the user-level `WORK_HOME` to an absolute path and open a new terminal.

Rerunning the installer from the same or a relocated checkout repairs its managed PATH and profile entries without duplicating them. It preserves unrelated profile content and backs up an existing profile before changing it. It updates only known Meowsky-managed Neovim files; an unrelated or manually changed editor config and an unmarked Meowsky-style profile import require review rather than automatic replacement. To explicitly check package upgrades too, run:

```powershell
.\scripts\install-windows.ps1 -Upgrade
```

The longer manual setup is still documented in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md) if you want to see each piece separately.

For C exercises and small multi-file programs, see [docs/c-development.md](docs/c-development.md).

### Linux

Use the helper script as a starting point:

```bash
bash ./scripts/install-linux.sh
```

The full Linux workflow is documented in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md).

## Daily Flow

Run `meowsky -h` for the complete command reference, including actions and arguments.

PowerShell feature help is available with commands such as `meowsky ptree -h` or `meowsky codex -Help`. Each feature owns its help and manifest. See [docs/architecture.md](docs/architecture.md) for ownership, dependencies and verification.

```powershell
meowsky
```

Enter the workspace or dev district, then open the project layout from the directory you want to work in:

```powershell
meowsky dev
meowsky my-app
meowsky ./
```

Open the bachelor or income exploration environment in its own district:

```powershell
meowsky bach
meowsky launchpad
```

These commands read district-specific startup guidance. They ask the agent to read `current.md` if present; they do not create personal records. PDFs and Word documents in a district's `references/` are original sources, not working files. See [district continuity](docs/district-continuity.md) for the optional state, session, and manual capsule convention.

Start Codex directly with the project session context and native `AGENTS.md` instructions:

```powershell
meowsky codex
meowsky codex my-app
meowsky codex ./
```

Use the preview and tree helpers:

```powershell
meowsky md .\README.md
meowsky pdf .\docs\spec.pdf
meowsky ptree 5
```

When `meowsky ./` runs in any folder, it opens a fullscreen Windows Terminal layout with:

- a Codex session given the dynamic context from [features/codex/codex-orientation.md](features/codex/codex-orientation.md); durable behavior comes from Codex's global and project `AGENTS.md` files
- a shell at the project root
- a tree view pane
- a compact status pane

## PowerShell Command Reference

| Command | What it does |
| --- | --- |
| `meowsky` | Ensure the workspace directories exist, then enter `WORK_HOME`. |
| `meowsky dev` | Ensure the workspace directories exist, then enter `dev/`. |
| `meowsky bach` | Open one Windows Terminal tab in `WORK_HOME\bach` with Codex left (70%), interactive PowerShell right (30%), and bachelor context instructing Codex to read `current.md` first if present. |
| `meowsky launchpad` | Open one Windows Terminal tab in `WORK_HOME\launchpad` with Codex left (70%), interactive PowerShell right (30%), and income context instructing Codex to read `current.md` first if present. |
| `meowsky <directory>` | Change to a directory, checking the current location and then the work root. |
| `meowsky .` or `meowsky ./` | Open the fullscreen Windows Terminal layout in the current directory. |
| `meowsky codex [directory]` | Start Codex with the Meowsky orientation prompt; defaults to the current directory. |
| `meowsky color` | Explain retired project color overrides; all panels inherit the active Terminal theme. |
| `meowsky identity` | Describe the Identity system; no settings are applied. |
| `meowsky identity list` | Discover available semantic identity themes. |
| `meowsky identity --help` | Show Identity help. |
| `meowsky identity apply <id>` | Apply detected Windows, Terminal, and VS Code adapters sequentially; summarize each result. |
| `meowsky identity apply <id> --dry-run` | Validate a theme and preview targets and palette without changing settings. |
| `meowsky identity apply <id> --target windows` | Apply configured Windows personalization; Meo Matrix defaults to normal dark mode. |
| `meowsky identity apply <id> --windows-mode contrast` | Use the existing Windows contrast theme instead; activate it manually. |
| `meowsky identity apply <id> --target terminal` | Back up Terminal settings, merge the identity scheme, and set default scheme/cursor. |
| `meowsky identity apply <id> --target vscode` | Back up VS Code settings, merge UI/syntax colors, and set visual preferences. |
| `meowsky color <color>` | Compatibility command; changes no colors or settings. |
| `meowsky color reset` or `meowsky color default` | Compatibility command; saved project colors are ignored. |
| `meowsky matrix` | Run the animated matrix display; stop it with `Ctrl+C`. |
| `meowsky ptree [level]` | Print the current directory tree; defaults to 3 levels and accepts a positive integer such as `15`. |
| `meowsky md <file.md>` or `meowsky markdown <file.md>` | Render Markdown with Pandoc and open the HTML preview. |
| `meowsky pdf <file.pdf>` | Open a PDF in the default viewer. |
| `meowsky -h`, `meowsky -Help`, `meowsky help`, or `meowsky --help` | Print the built-in command manual. |

`ptree [level]` also works as a standalone command. On Windows, the workspace defaults to `C:\meowsky`; an optional `WORK_HOME` override must be an absolute path. Bare `meowsky` and `meowsky dev` create only missing `dev/`, `bach/`, and `launchpad/` directories under it; they do not create repositories or records. Linux retains its existing work-root behavior. Run `meowsky -h` for the terminal manual.

## Identity

Identity defines semantic UI colors, syntax colors, and visual preferences independently of tools. Add themes under `features/identity/themes/`; see [docs/identity.md](docs/identity.md) for the model and integrations. Use `meowsky identity apply meo-matrix --dry-run` to preview all detected targets without writes, then `meowsky identity apply meo-matrix` to apply Windows, Terminal, and VS Code in that order. Meo Matrix defaults to normal Windows rendering with dark system/apps, its semantic accent, and transparency. `--windows-mode contrast` retains the stronger contrast theme with manual activation. Terminal and VS Code remain independent of the Windows mode. Missing applications are skipped; per-target failures are reported while other targets continue. Targeted application remains available through `--target windows|terminal|vscode`.

`meowsky identity apply meo-matrix --target terminal --dry-run` previews the Terminal scheme and settings changes. Remove `--dry-run` to apply with a backup. The existing Matrix animation, cat/header, layouts, and commands are preserved; conflicting profile palette/cursor overrides are removed; unrelated profile settings are preserved.

Meo Matrix uses neon Matrix green `#39FF14` for ordinary terminal text, with black backgrounds and dark forest surfaces, muted green structure, and restrained `#58CB70` cursor/emphasis accents. Windows accent is fixed at `#265934`. Syntax uses neon-green keywords, cyan functions, bright-blue types, yellow strings, orange numbers, and magenta constants; syntax errors are bright red and warnings yellow. Matrix glyphs and the status header use ANSI green; folders use ANSI blue; the project path uses ANSI cyan. Working-tree status uses green when clean and yellow when dirty. Files, tree connectors, and other Git metadata retain ordinary terminal text. Normal Windows mode retains Windows-managed text colors.

Terminal backgrounds use `ui.terminalBackground` (`#000000`); ANSI black uses green-charcoal `ansi.black` (`#1A2720`) in both Windows Terminal and VS Code's integrated terminal. Windows/editor backgrounds remain `ui.background` (`#000000`). The explicit `ansi` palette uses neon green and pale-green text, red errors, yellow warnings, and bright blue/magenta/cyan output, supplying all 16 ANSI colors in Windows Terminal and VS Code; older definitions without `ansi` retain their existing fallback behavior.

`meowsky identity apply meo-matrix --target vscode --dry-run` previews VS Code UI and syntax overrides. Remove `--dry-run` to apply with a backup. Editor text uses `syntax.text`; UI text uses `ui.text`; integrated-terminal text uses `ui.terminalText`. Semantic and TextMate colors come from the JSON syntax palette. The selected base theme, unrelated token rules/styles, fonts, extensions, keybindings, and other settings are preserved. See [Identity](docs/identity.md) for mappings, settings discovery, and the 14 language samples under `docs/samples/`.

## Neovim Highlights

The editor config in [nvim/init.lua](nvim/init.lua) is tuned for:

- `tokyonight.nvim` styling
- Treesitter parsing for Lua, Vim, JavaScript, TypeScript, TSX, JSON, HTML, CSS, Markdown, and Prisma
- Mason-managed LSPs for TypeScript, ESLint, HTML, CSS, JSON, Lua, and Prisma
- completion from language servers, snippets, paths, and buffers
- auto-pairs for brackets and quotes
- automatic HTML/React closing tags

The configuration defines no custom key mappings. Use native Neovim commands and any defaults supplied by plugins.

## Sharing

This is designed to stay personal but portable.

If you want to move it to another machine, the repo is the source of truth:

```powershell
git clone <your-repo-url>
cd meowsky-devkit
```

It does not need packaging yet. A GitHub repo is the right shape for this because it is a mix of docs, prompt text, shell setup, and editor config.

## Details

The longer manual setup guide lives in [docs/new-pc-dev-setup.md](docs/new-pc-dev-setup.md).

The terminal color direction follows `features/identity/themes/meo-matrix/terminal-view-aim.png`: true black and mostly luminous Matrix-green terminal text. ANSI output retains red/yellow alerts and bright blue, magenta, and cyan; syntax uses bright, distinct colors for functions, types, constants, strings, and numbers. The reference is a visual guide, not a source of layout or runtime behavior.

PowerShell command input uses bright ANSI highlighting from `powershell/profile.ps1`: cyan commands, yellow strings, magenta numbers, blue parameters/types, and green keywords. Open a new PowerShell session or reload the profile to activate it. VS Code syntax uses its own bright semantic palette; reapply the VS Code target to update highlighting.
