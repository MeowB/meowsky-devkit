# Feature architecture

`powershell/profile.ps1` remains the installed import. It loads core infrastructure, an explicit feature list, the small CLI dispatcher and completion. Dot-sourcing preserves interactive functions and Windows PowerShell 5.1 scope.

## Feature contract

Each PowerShell feature owns implementation, `help.txt` and `feature.psd1`. Manifest fields are `Name`, `Command`, `Aliases`, `EntryPoint`, `Handler`, `Help`, and `Description`. `Handler` names a function accepting `Target` and `WorkRoot`. Color is an explanatory compatibility command; project color overrides are retired.

Identity and Audit use two optional manifest flags: `SkipWorkRoot` bypasses work-root creation and passes no work root; `AcceptsArguments` forwards trailing CLI tokens in the handler's `Arguments` array. Features without those flags retain their existing dispatch behavior. `SkipWorkRoot` describes dispatch only; Identity may install a theme when explicitly requested without `--dry-run`.

The C feature uses `AcceptsAction` to receive the original command spelling, `CaseSensitive` to reject differently capitalized CLI actions, and `SkipWorkRoot` because builds act in the current directory. Its direct PowerShell functions check their own invocation spelling.

The loader validates resource paths, handlers and duplicate commands. Registration is explicit in `core/feature-loader.ps1`; there is no auto-discovery. Loading defines functions; the handler executes the command.

Folder names do not create commands: tree remains `ptree`, workspace remains `.` / `./`. Color owns `color`; Identity owns `identity`. Unknown actions still attempt directory navigation. Feature `-h` / `-Help` reads feature help; global help remains in `core/help.txt`. Identity also handles its positional `--help` through its feature handler.

## Ownership and dependencies

| Feature | Owns | Required core |
| --- | --- | --- |
| tree | Rendering and live panel | directory-tree, terminal |
| md | Pandoc preview | paths |
| c | GCC build and run commands in PowerShell | feature-loader |
| pdf | Viewer launch | paths |
| codex | Launchers, global instruction source, and primary/fallback session-context prompts | paths, git, directory-tree, terminal |
| bach | Bachelor district command, help, and startup context | workspace, paths |
| launchpad | Software opportunity district command, help, and startup context | workspace, paths |
| color | Explain retirement of project color overrides | none |
| identity | Semantic theme loading, validation, planning, Windows/Terminal/VS Code UI/syntax adapters, and help | feature-loader (help resource) |
| audit | Filesystem discovery, static checks, report/map rendering, input fingerprints, and saved stage state | feature-loader (help resource) |
| review | Current-audit gate, interactive read-only Codex launch, explicit validated JSON handoff, report/map/plan enrichment | audit discovery, reporting and state; codex launcher |
| refactor | Binds human approval to full-review findings, runs read-only planning before an approved write session, and validates completion against changed-file scope | audit state and plan; review handoff; codex launcher |
| matrix | Animation | terminal |
| workspace | Layout and status banner | feature-loader, terminal, git |

For a feature change, read that directory and the listed core files. Tree and Codex share enumeration but retain separate rendering. Terminal core only restores terminal-default foreground/background with ANSI SGR 39/49. Theme definitions own colors. Runtime panels use standard ANSI roles from the active palette: green Matrix glyphs/header, blue folders, cyan project path, and green/yellow clean/dirty working-tree status. Each colored segment restores the default foreground; panels do not load project colors. No generic configuration or event framework is introduced.

Audit's `audit.ps1` handles CLI options and dispatch. `discovery.ps1` inventories filesystem paths without Git, and `static-checks.ps1` emits verified issues, review candidates, and coverage limits. `report.ps1` and `map.ps1` render linked Markdown on every audit; `state.ps1` fingerprints relevant inventoried content and exclusions, then marks audit complete only after both outputs validate. A new audit first marks state pending. Review reuses the interactive Codex launcher with read-only arguments. Its `handoff.ps1` validates a copied session JSON, `plan.ps1` renders an unapproved checklist, and `review.ps1` updates artifacts before recording completion. Refactor keeps approval parsing and scope fingerprints in `approval.ps1`, validates planning and completion JSON in `handoff.ps1`, and dispatches the two interactive permission phases from `refactor.ps1`. Session exit does not complete review or refactoring. The old `semantic.ps1` remains loaded for migration and existing unit coverage but is not called by `meowsky audit`. The generated map is a snapshot, not a live index.

`.meowsky/state.json` version 1 stores the resolved target, audit status, completion time, SHA-256 fingerprint, coverage label, output hashes, review status, and an active review session ID/mode when launched. Completed full review records its PLAN.md hash. Refactor state adds selected approved findings, exact permitted files, approved concrete plan, execution session, approved-file baselines, and a fingerprint of discovered content outside the permitted scope. A write session may mark audit status stale; completion never silently reruns audit. The fingerprint covers inventoried file contents and paths, directory paths, recorded skips, warnings, and exclusion rules through `.meowskyignore`. Review recomputes it without Git. Excluded directory contents are outside this fingerprint and remain a stated coverage limit. Refactor scope checks detect unexpected discovered-file changes after execution; they cannot enforce edits within a permitted file or verify the truth of model-reported test results.

Workspace is the composition exception: its Windows development layout uses Codex context/launch functions and matrix dispatch, and checks those features before opening a window. The tree panel remains a standalone feature. All workspace panes restore terminal defaults on startup. Tree and Matrix no longer poll project-color files. Files, tree connectors, and ordinary Git metadata retain the default foreground.

`core/paths.ps1` and `core/paths.sh` also prepare the disposable project workspace. Project navigation and Codex/workspace launches create `.meowsky/` at the Git root when available, or at the opened directory otherwise, and ensure the root `.gitignore` has an equivalent of `/.meowsky/` without replacing existing rules. Audit also prepares a Git repository root before writing its generated reports; for other targets it retains its existing ignore behavior. This folder is excluded from audit discovery and is not a source of maintained application behavior. Removing it discards audit/review/refactor state; rerun `meowsky audit` before using those workflows again.

On Windows, `bach` and `launchpad` are registered features that select their own district under `WORK_HOME` and reuse the workspace's Terminal launcher. Both select the two-pane layout: one tab with Codex on the left (70%) and interactive PowerShell on the right (30%), both starting in their respective district, with initial focus on Codex. They share prompt-file creation and Codex/profile startup with the development layout, but require only the Codex feature and start no Matrix, status, tree, editor, or server commands. Bachelor's startup template directs Codex to read `current.md` when present and use relevant records while protecting original references and leaving human communication to the user. Launchpad's template directs Codex to read its repository instructions and run `node dist/cli.js briefing`; the right pane remains available for an optional `node dist/cli.js start` panel. The development `.` / `./` command opens three panes with Codex on the left (40%), Matrix and status on the right (60%), and retains its orientation prompt and current-directory behavior. Linux has no district launch commands in this stage.

The optional state, dated-session, and manual-capsule file convention is documented in [district-continuity.md](district-continuity.md). It is user-maintained data, not devkit persistence code.

Identity follows the same manifest and handler contract. `identity.ps1` handles CLI syntax, `themes.ps1` resolves/loads/validates JSON definitions, and `plan.ps1` detects targets and builds an ordered plan plus display output; `apply.ps1` executes the existing adapters sequentially, isolates target failures, and formats results. `adapters/windows-normal.ps1` selects normal/contrast Windows mode and owns normal personalization planning, scoped registry backups, and verified writes; `adapters/windows-native.ps1` isolates documented contrast-state/transition APIs and refresh broadcasts. `adapters/windows.ps1` retains Windows Contrast Themes unchanged. The single `--windows-mode normal|contrast` override affects Windows only; Terminal and VS Code consume the same semantic palette. `adapters/terminal.ps1` owns Terminal palette generation, discovery, and planning; `terminal-settings.ps1` owns its scheme/profile merge. `adapters/vscode.ps1` owns VS Code UI mappings, settings discovery, and planning; `adapters/vscode-syntax.ps1` owns semantic/TextMate generation and the narrow syntax merge. Both settings adapters reuse `settings-jsonc.ps1` for narrow source-span edits and `settings-file.ps1` for exact backups, concurrency checks, and atomic replacement. Theme loading/validation happens once per command; the internal validated flag avoids repeated renderer validation, while standalone renderers still validate by default. Windows installation consumes its prebuilt definition. Renderers are shared by previews and application; dry-run never calls a writer. UI colors, syntax colors, and visual preferences remain separate; future identities need only another definition. See [identity.md](identity.md) for mappings and safety. VS Code syntax highlighting is implemented; Neovim integration is not implemented.

Removing an ordinary feature directory removes its registered commands on a fresh profile load. Other ordinary features continue loading. Workspace reports a missing composed feature before starting. An unregistered action may still navigate to a matching directory. Start a fresh shell after removals: old functions can remain in an already-running shell.

## Installation boundaries

`scripts/install-windows.ps1` is the Windows entry point and retains `-Upgrade` and `-Msys2Root`. Its `scripts/installer/windows-features.psd1` manifest lists installation order separately from technical prerequisites. The installer validates every step and handler before executing the first step. Install-specific modules live in `scripts/installer/features/`; shared Windows environment, guarded file, and process operations live beside the manifest. The final fresh-shell, compiler/debugger, and headless editor checks live in `scripts/installer/windows-verification.ps1`. These installation modules are separate from runtime `features/*/feature.psd1` registration. The standalone Codex instruction installer remains available at `features/codex/install-instructions.ps1`.

Windows loads this checkout directly through the installed profile. `MEOWSKY_DEVKIT_HOME` still controls primary Codex session-context template lookup. The installer copies `features/codex/global-instructions.md` to `CODEX_HOME/AGENTS.md` (or `~/.codex/AGENTS.md` when `CODEX_HOME` is unset) only when absent; it never overwrites an existing user's file. Codex itself discovers global and project `AGENTS.md` files in precedence order. Meowsky's prompt contains only the launch snapshot and project orientation, while the shared Codex launch arguments and temporary prompt path remain unchanged. Legacy project-color files are ignored and left untouched.

Linux has a `shell/meowsky.sh` bootstrap and `.sh` implementations beside their features. Its installer copies those files to the existing runtime directory and installs global Codex instructions without replacing an existing file; the checkout is not needed at runtime. Linux retains its command subset and context-only prompt. PowerShell manifests do not drive shell loading.

`nvim/init.lua` owns shared editor setup. `nvim/lua/meowsky/c.lua` owns C-only build, run, navigation, and GDB commands. The Windows installer copies both files, reuses a healthy MinGW-w64 GCC/GDB pair or installs MSYS2 UCRT64, and adds clangd and the C Treesitter parser. Zig wrappers still serve Treesitter. See [C development](c-development.md) for the learning workflow.

`features/c/` owns the PowerShell `:CBuild` and `:CRun` commands, both directly and through `meowsky`. The feature uses the current directory and GCC on PATH; it does not start Neovim. The CLI forwards the original action spelling for the feature's exact-case check. Neovim's same-named commands use the current buffer and retain editor quickfix output.

## Verification

```powershell
powershell -NoProfile -File tests/verify-c.ps1
powershell -NoProfile -File tests/verify-refactor.ps1
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-terminal.ps1
powershell -NoProfile -File tests/verify-vscode.ps1
powershell -NoProfile -File tests/verify-vscode-syntax.ps1
powershell -NoProfile -File tests/verify-identity-apply.ps1
powershell -NoProfile -File tests/verify-windows-normal.ps1
powershell -NoProfile -File tests/verify-audit.ps1
powershell -NoProfile -File tests/verify-audit-e2e.ps1
```

```bash
bash tests/verify-linux.sh
```

Suites compare retained behavior with the original monoliths at the recorded pre-refactor Git revision, with explicit assertions for the intentional retirement of color overrides. Override that baseline through PowerShell's `BaselineRevision` parameter or shell's `MEOWSKY_BASELINE_REVISION` variable if needed. Process boundaries are mocked: no GUI, installer, Codex session or live animation is started.

Manually verify Windows Terminal geometry, matrix resize/Ctrl+C, theme colors and foreground restoration across all panes, actual Markdown/PDF previews and real Codex startup. apt, tmux and xdg-open integration requires Linux. Automated checks cover dispatch, output, persistence and launch scripts.

Theme discovery supports flat `themes/<id>.json` and folder `themes/<id>/<id>.json` definitions, rejecting duplicate IDs across the two layouts. Wallpapers and icons beside a definition are visual references only; the runtime reads JSON alone.

The optional `ansi` group owns a complete 16-color semantic palette independently of UI branding and syntax. The loader validates every slot. Terminal maps `magenta` to `purple`; VS Code maps the same values to its integrated-terminal ANSI keys. Version-1 themes without this group retain the previous fallback behavior.

Optional `ui.border`, `ui.accentActive`, and `ui.onAccent` roles separate structural outlines, active indicators, and control labels. Windows contrast and VS Code adapters preserve legacy mappings when these roles are absent. Normal Windows accent still resolves through `windows.accent`; all palette values remain in theme JSON. Runtime pane accents use the active ANSI palette, with terminal defaults for ordinary text.
