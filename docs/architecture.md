# Feature architecture

`powershell/profile.ps1` remains the installed import. It loads core infrastructure, an explicit feature list, the small CLI dispatcher and completion. Dot-sourcing preserves interactive functions and Windows PowerShell 5.1 scope.

## Feature contract

Each PowerShell feature owns implementation, `help.txt` and `feature.psd1`. Manifest fields are `Name`, `Command`, `Aliases`, `EntryPoint`, `Handler`, `Help`, and `Description`. `Handler` names a function accepting `Target` and `WorkRoot`. Color also declares its `Completion` function.

Identity opts into two optional manifest flags: `SkipWorkRoot` bypasses work-root creation and passes no work root; `AcceptsArguments` forwards trailing CLI tokens in the handler's `Arguments` array. Features without those flags retain their existing dispatch behavior. `SkipWorkRoot` describes dispatch only; Identity may install a theme when explicitly requested without `--dry-run`.

The loader validates resource paths, handlers and duplicate commands. Registration is explicit in `core/feature-loader.ps1`; there is no auto-discovery. Loading defines functions; the handler executes the command.

Folder names do not create commands: tree remains `ptree`, workspace remains `.` / `./`. Color owns `color`; Identity owns `identity`. Unknown actions still attempt directory navigation. Feature `-h` / `-Help` reads feature help; global help remains in `core/help.txt`. Identity also handles its positional `--help` through its feature handler.

## Ownership and dependencies

| Feature | Owns | Required core |
| --- | --- | --- |
| tree | Rendering and live panel | directory-tree, terminal |
| md | Pandoc preview | paths |
| pdf | Viewer launch | paths |
| codex | Launchers and primary/fallback prompts | paths, git, directory-tree, terminal |
| color | Existing color command and completion | terminal |
| identity | Semantic theme loading, validation, planning, Windows/Terminal/VS Code UI/syntax adapters, and help | feature-loader (help resource) |
| matrix | Animation | terminal |
| workspace | Layout and status banner | feature-loader, terminal, git |

For a feature change, read that directory and the listed core files. Tree and Codex share enumeration but retain separate rendering. Terminal core owns color maps, persistence and signaling because several features use them. No generic configuration or event framework is introduced.

Workspace is the composition exception: it uses Codex context/launch functions, the tree panel and matrix dispatch. It checks those features before opening a window. Workspace registers a status-refresh scriptblock with terminal core; color calls that core hook without depending on workspace directly.

Identity follows the same manifest and handler contract. `identity.ps1` handles CLI syntax, `themes.ps1` resolves/loads/validates JSON definitions, and `plan.ps1` detects targets and builds an ordered plan plus display output; `apply.ps1` executes the existing adapters sequentially, isolates target failures, and formats results. `adapters/windows-normal.ps1` selects normal/contrast Windows mode and owns normal personalization planning, scoped registry backups, and verified writes; `adapters/windows-native.ps1` isolates documented contrast-state/transition APIs and refresh broadcasts. `adapters/windows.ps1` retains Windows Contrast Themes unchanged. The single `--windows-mode normal|contrast` override affects Windows only; Terminal and VS Code consume the same semantic palette. `adapters/terminal.ps1` owns Terminal palette generation, discovery, and planning; `terminal-settings.ps1` owns its scheme/profile merge. `adapters/vscode.ps1` owns VS Code UI mappings, settings discovery, and planning; `adapters/vscode-syntax.ps1` owns semantic/TextMate generation and the narrow syntax merge. Both settings adapters reuse `settings-jsonc.ps1` for narrow source-span edits and `settings-file.ps1` for exact backups, concurrency checks, and atomic replacement. Theme loading/validation happens once per command; the internal validated flag avoids repeated renderer validation, while standalone renderers still validate by default. Windows installation consumes its prebuilt definition. Renderers are shared by previews and application; dry-run never calls a writer. UI colors, syntax colors, and visual preferences remain separate; future identities need only another definition. See [identity.md](identity.md) for mappings and safety. VS Code syntax highlighting is implemented; Neovim integration is not implemented.

Removing an ordinary feature directory removes its registered commands on a fresh profile load. Other ordinary features continue loading. Workspace reports a missing composed feature before starting. An unregistered action may still navigate to a matching directory. Start a fresh shell after removals: old functions can remain in an already-running shell.

## Installation boundaries

Windows loads this checkout directly through the installed profile. `MEOWSKY_DEVKIT_HOME` still controls primary Codex template lookup. Configuration paths, temporary prompts and color signaling are unchanged.

Linux has a `shell/meowsky.sh` bootstrap and `.sh` implementations beside their features. Its installer copies those files to the existing runtime directory; the checkout is not needed at runtime. Linux retains its command subset and prompt. PowerShell manifests do not drive shell loading.

`nvim/init.lua` and the Windows installer are unchanged in this milestone. Neovim ownership can move in a separate structural change. Zig wrappers currently serve Treesitter; no C/C++ feature is introduced.

## Verification

```powershell
powershell -NoProfile -File tests/verify-refactor.ps1
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-terminal.ps1
powershell -NoProfile -File tests/verify-vscode.ps1
powershell -NoProfile -File tests/verify-vscode-syntax.ps1
powershell -NoProfile -File tests/verify-identity-apply.ps1
powershell -NoProfile -File tests/verify-windows-normal.ps1
```

```bash
bash tests/verify-linux.sh
```

Suites compare behavior with the original monoliths at the recorded pre-refactor Git revision. Override that baseline through PowerShell's `BaselineRevision` parameter or shell's `MEOWSKY_BASELINE_REVISION` variable if needed. Process boundaries are mocked: no GUI, installer, Codex session or live animation is started.

Manually verify Windows Terminal geometry, matrix resize/Ctrl+C, tree color refresh, status-pane color changes, actual Markdown/PDF previews and real Codex startup. apt, tmux and xdg-open integration requires Linux. Automated checks cover dispatch, output, persistence and launch scripts.
