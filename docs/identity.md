# Identity

Identity is Meowsky's system for a coherent visual identity across the development environment. It composes Windows, Windows Terminal, and VS Code UI/syntax adapters in a predictable sequence. Meo Matrix defaults to normal Windows personalization, preserving normal Windows/application color rendering. Its stronger Windows Contrast Theme remains available explicitly, with manual activation. No separate active-identity state is saved. The existing `meowsky color` command remains independent and unchanged.

## Commands

```powershell
. ./powershell/profile.ps1
meowsky identity
meowsky identity list
meowsky identity --help
meowsky identity apply meo-matrix --dry-run
meowsky identity apply meo-matrix
meowsky identity apply meo-matrix --target windows --dry-run
meowsky identity apply meo-matrix --target windows
meowsky identity apply meo-matrix --target windows --windows-mode contrast --dry-run
meowsky identity apply meo-matrix --target windows --windows-mode contrast
meowsky identity apply meo-matrix --target terminal --dry-run
meowsky identity apply meo-matrix --target terminal
meowsky identity apply meo-matrix --target vscode --dry-run
meowsky identity apply meo-matrix --target vscode
```

`identity` describes the system. `list` reads and validates flat `themes/<id>.json` and folder `themes/<id>/<id>.json` definitions, then prints IDs and display names sorted by ID. The directory is resolved relative to the feature, not the current project. An empty directory reports no identities; invalid definitions report the filename and reason. `--help`, `-h`, and `-Help` show feature help. Other actions report usage. Linux support is not implemented in this step.

`apply <id> --dry-run` loads and validates only the selected theme once, detects targets, and previews every detected adapter in Windows, Terminal, VS Code order. An unrelated invalid definition does not block it. The plan displays paths, mappings, availability/evidence, per-target planning errors, and confirmation that no changes were made. A detected target with invalid/missing/ambiguous settings reports a planning error while other previews continue. Dry-run displays these errors without raising an aggregate application failure. `--target windows --dry-run` previews only that adapter. Flags can appear in either order; unknown/duplicate flags and extra arguments are rejected. Even an absent work root is left untouched.

`apply <id> --target windows` applies the identity's Windows mode. Meo Matrix uses normal personalization; `--windows-mode normal|contrast` overrides only Windows for that invocation, including dry-run. Definitions without a `windows` section retain the original contrast behavior. `apply <id> --target terminal` backs up the discovered Terminal settings and updates the identity scheme and profile defaults. An unqualified apply composes all detected adapters; explicit targets limit application to one adapter. VS Code UI/syntax overrides are implemented; Neovim integration is not implemented.

## Complete application (Step 7)

`meowsky identity apply meo-matrix` composes the existing adapters. Execution is:

1. Parse arguments; resolve, load, and validate the selected definition once.
2. Detect Windows, Terminal, and VS Code using installation evidence.
3. Build each detected target plan independently, in that fixed order, before writing.
4. Execute every ready plan in the same order; skipped/error plans never call a writer.
5. Report each result and any path, backup, failure reason, or manual activation step.
6. If any target failed, raise one overall failure after all results have been printed.

VS Code UI and syntax are one settings-file application. A failed plan or write does not block remaining adapters. Successful targets remain applied; there is no cross-target rollback. Settings-file and contrast-theme writers retain their atomic-update safeguards; normal registry writes are verified individually and backed up, with partial failures reported. Reapplication reports `unchanged` for matching files and creates no settings backups. Theme validation failure occurs before detection/planning/writes.

Example summary (paths and backup details follow their respective rows):

```text
Meo Matrix
  Windows          applied
  Windows Terminal applied
  VS Code          applied
```

Missing applications report `skipped`; detected applications with unreadable, malformed, ambiguous, or absent settings report `error`. Explicit `--target` commands attempt that adapter even without installation evidence, preserving custom-settings workflows; their planning errors remain terminating. An all-skipped run completes without writes. Detection does not launch applications or create initial settings files.

In normal mode Windows configures supported personalization values and checks contrast state through the Windows API. Explicit contrast mode installs the generated theme file and reports **Settings > Accessibility > Contrast themes > Meo Matrix > Apply**, retaining manual activation. Terminal application removes conflicting palette/cursor overrides from defaults, individual profiles, and unfocused appearances so the identity scheme supplies colors. VS Code scoped overrides retain their existing precedence. Windows mode never changes their palette mappings or settings. Manually disabling contrast later does not remove their installed customizations, although accessibility behavior can affect rendering while contrast is active. No persistent active-identity record, automatic contrast activation, second identity, or Neovim adapter is introduced.

The composition suite uses temporary settings and theme directories. It checks one load/validation/detection pass, ordering, dry-run protection, missing targets, idempotence, targeted isolation, planning failures, and write failures at each sequence position. Live system appearance and Windows manual activation still require user verification.

## Loading and planning

The flow is theme definition → loader/validator → application plan → target adapter. `identity.ps1` parses commands; `themes.ps1` validates lowercase slug IDs before resolving filenames, parses JSON, and checks metadata, UI/syntax colors, and cursor preferences. Errors distinguish nonexistent identities, unreadable files, malformed JSON, missing semantic values, invalid colors, and unsupported preferences. `plan.ps1` returns a structured plan with ordered target entries and formats its preview; `apply.ps1` executes entries independently and formats final results. `adapters/windows-normal.ps1` selects Windows mode and owns normal personalization/backups; `adapters/windows-native.ps1` isolates the Win32 API boundary. `adapters/windows.ps1` retains the contrast renderer/installer. `adapters/terminal.ps1` owns Terminal palette generation, discovery, and planning; `terminal-settings.ps1` handles the scheme/profile merge. `adapters/vscode.ps1` owns VS Code UI mapping, discovery, and planning; `adapters/vscode-syntax.ps1` generates and merges semantic/TextMate syntax rules. Both settings adapters share `settings-jsonc.ps1` for narrow JSONC edits and `settings-file.ps1` for backups and atomic writes. Dry-run never calls a writer. Selecting Terminal or VS Code does not install or activate a Windows contrast theme.

Detection uses read-only installation evidence: Windows is detected from the OS platform; Windows Terminal from `wt.exe`/`WindowsTerminal.exe` on PATH or a current-user Terminal package; VS Code from `code`/`code-insiders` on PATH or standard Windows user/system installation paths. These follow the documented [Terminal execution alias](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) and [VS Code installation locations](https://code.visualstudio.com/docs/setup/windows). No target is launched. Undetected targets are skipped during complete application; explicit targets can still attempt their settings discovery. Detection does not prove that an application can launch; custom locations without a PATH command may not be detected. These PowerShell adapters require Windows; Linux shell command support remains outside this step.

## Semantic theme model

`meo-matrix.json` is the first definition. The palette in that file is the source of truth; the three wallpapers and three desktop icons in `features/identity/themes/meo-matrix/` are visual references only, never runtime inputs or color extraction sources.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Format version; currently `1`. |
| `id` | Stable lowercase slug matching the filename without `.json`. |
| `name` | Human-readable display name. |
| `ui` | General interface roles: background, surface, surfaceRaised, text, muted, accent, accentBright, accentSoft, selection, warning, error. |
| `ansi` | Optional complete 16-color terminal palette: black/red/green/yellow/blue/magenta/cyan/white and their bright variants. Semantic hues are independent of UI and syntax colors. |
| `syntax` | Code roles: text, comment, keyword, function, type, string, number, constant, operator, error, warning. |
| `preferences.cursor.style` | Visual behavior: block, bar, or underline. Meo Matrix uses block. |
| `windows` | Optional Windows-specific mode, system/app theme, semantic accent reference, and transparency. |

All listed color roles are required six-digit `#RRGGBB` values. UI and syntax roles are separate even when their colors coincide. Preferences hold visual behavior rather than color values; additional preferences can be introduced when an integration needs them.

`ui.terminalText` is an optional six-digit hex role for default terminal text. Meo Matrix uses neon Matrix green `#39FF14` for ordinary terminal text on black. Tree files, connectors, and ordinary status text inherit this foreground; Matrix rain and headers use ANSI green. UI and syntax text have independent roles. Themes without `terminalText` fall back to `ui.accent` for Terminal foreground; Legacy ANSI white uses `ui.text`; explicit ANSI white uses `ansi.white`. Windows normal text remains OS-managed.

`ui.terminalBackground` and `ui.terminalBlack` are optional six-digit hex roles. Meo Matrix uses true black `#000000` for terminal backgrounds and green-charcoal `#1A2720` for ANSI black, separating black output from its background. Windows/editor backgrounds retain `ui.background` (`#000000`). Terminal/cursor backgrounds fall back to `ui.background`. The explicit `ansi.black` takes precedence over `ui.terminalBlack`. Without `ansi`, Windows Terminal falls back to `ui.background` for missing ANSI black, while VS Code leaves ANSI black untouched when `terminalBlack` is absent.

`ui.border`, `ui.accentActive`, and `ui.onAccent` are optional six-digit hex roles. They separate dark structure, active indicators, and readable labels on colored controls. Meo Matrix uses `#1A2720`, `#34784A`, and `#E8EEE9` respectively. Existing definitions retain their original adapter mappings when these roles are absent. The light control label ensures readable text on both the fixed `#265934` accent and active hover fill.

PowerShell command-input highlighting is configured in `powershell/profile.ps1` using bright ANSI slots through [Set-PSReadLineOption](https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption?view=powershell-5.1). Commands and members use cyan, strings yellow, numbers magenta, types/parameters blue, variables/operators pale green, keywords green, and errors red. Other input uses the terminal default foreground; comments use ANSI bright black. Reload the profile or open a new PowerShell session to activate it. This colors input as you type; programs choose their own output categories. The prompt itself is not configured. Palette-based shell output follows the host terminal; explicit RGB output can bypass the scheme. Linux/tmux has no Identity integration and eza trees disable color. Neovim uses its independent Tokyo Night theme with true-color highlights, so terminal palette changes do not retheme it.

## Multiple identities and planned integrations

Add another definition such as `themes/meo-evil/meo-evil.json` (flat `themes/meo-evil.json` remains supported) with its own matching `id`, name, palette, and preferences. Discovery reads it automatically; no Identity engine or command registration change is needed. Tests use a temporary second identity to verify this.

Normal Windows personalization, Windows contrast-theme installation, Windows Terminal schemes/defaults, and VS Code UI/syntax overrides are implemented. Neovim, automatic Windows contrast activation, and separate persistent identity selection belong to later steps. Future adapters will translate semantic roles and supported preferences into each tool's settings. No generic plugin system is needed.

## Normal Windows personalization

Normal mode is the recommended Meo Matrix experience. It keeps standard Windows rendering, including ordinary application colors, images, and color pickers. Contrast mode offers stronger system-wide color control but applications can override their usual colors or suppress images to meet accessibility requirements.

The identity's Windows preferences are:

```json
"windows": {
  "mode": "normal",
  "systemTheme": "dark",
  "appTheme": "dark",
  "accent": "ui.accent",
  "transparency": true
}
```

The optional section preserves compatibility with version-1 themes: absent sections default to contrast. When present, all five fields are required and validated. Modes are `normal`/`contrast`, system/app themes are `dark`/`light`, transparency must be a JSON boolean, and accent must reference an existing UI color (`ui.<role>`), rather than duplicate a hex value. Normal overrides require these preferences. Unsupported values produce useful validation errors before writes.

`adapters/windows-normal.ps1` selects the Windows mode, plans normal settings, and applies only the following current-user values. `adapters/windows-native.ps1` contains the small Win32 boundary; the existing `adapters/windows.ps1` contrast generator/installer remains intact. Other adapters receive the same semantic identity regardless of the Windows mode.

| Registry path under `HKEY_CURRENT_USER` | Value | Meo Matrix normal mode |
| --- | --- | --- |
| `Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `SystemUsesLightTheme` (DWORD) | `0` (dark Windows) |
| Same | `AppsUseLightTheme` (DWORD) | `0` (dark applications) |
| Same | `EnableTransparency` (DWORD) | `1` |
| `Control Panel\Desktop` | `AutoColorization` (DWORD) | `0` (manual identity accent rather than wallpaper-derived accent) |
| `Software\Microsoft\Windows\DWM` | `AccentColor` (DWORD) | `0xFF345926` (ABGR from `ui.accent`) |
| Same | `ColorizationColor` (DWORD) | RGB `0x265934` from `ui.accent`, preserving the existing high byte (fallback `FF` when absent) |
| `Software\Microsoft\Windows\CurrentVersion\Explorer\Accent` | `AccentColorMenu` (DWORD) | `0xFF345926` (ABGR from `ui.accent`) |
| Same | `AccentPalette` (binary) | Seven RGB/reserved-byte accent slots: three lighter shades, the exact accent, three darker shades. Preserve the existing eighth slot. |

Registry dark/transparency preferences and manual accent selection are described in Microsoft's [Windows settings reference](https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/develop/settings/settings-common.md). Windows' [accent color system information](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdperp/bc6975ee-c630-4414-ba10-04eecbb6fccc) documents the DWM/Explorer accent registry names. This is an established current-user registry mechanism, not a transactional public accent setter API. No private DLL ordinals, administrator privileges, Explorer restarts, or global color overrides are used. Unknown existing value types or an unexpected palette size are refused rather than overwritten.

Accent shades are derived from the identity accent, using white blends of 65%, 40%, and 20%, then the base color, then black blends of 20%, 40%, and 65%. No extra identity colors are hardcoded. Windows and applications decide where accents appear and can use shades instead of the exact base hex. Existing switches controlling accent visibility on title bars/borders or Start/taskbar are preserved. Normal mode cannot force arbitrary Explorer backgrounds, global text/button/selection colors, application themes, or application-owned borders. Apps that ignore the Windows app-theme preference remain unchanged.

Before any registry change or contrast transition, save an exclusive, timestamped `.reg` backup under `%LOCALAPPDATA%\Meowsky\Identity\Backups`. It records only the eight owned values, their original DWORD/binary contents, deletion instructions for values previously absent, and a comment with the prior contrast state. Matching reapplication creates no backup, registry write, or refresh. Planning detects concurrent changes before application; all owned values are verified after the refresh broadcast, with up to six reads spaced 100 ms apart (at most 500 ms of settling). Only DWM `ColorizationColor` tolerates a changed high byte; its RGB must match exactly, and all other values retain exact type/value checks. Registry writes are not atomic as a group: a failure reports the retained backup and possible partial changes. Other targets continue independently.

For restoration, inspect the reported `.reg` file and import it with Registry Editor under the same Windows user. Its original values replace only those eight properties; previously absent properties are deleted. Close/reopen affected applications or use Windows Personalization Settings afterward to refresh their rendering. The backup does not restore contrast activation; select the previous contrast theme manually if needed. No general rollback command is added.

Normal application queries `SPI_GETHIGHCONTRAST`. If active, it clears `HCF_HIGHCONTRASTON` using documented `SPI_SETHIGHCONTRAST`, preserving other accessibility flags and the scheme; Windows handles restoring normal rendering. Then normal preferences are applied, since the transition may restore earlier settings. If querying or disabling fails, the summary says **manual action required** and gives **Settings > Accessibility > Contrast themes > None > Apply** (then reapply if disabling failed). No contrast registry hacks are used. See Microsoft's [contrast API](https://learn.microsoft.com/en-us/windows/win32/winauto/high-contrast-parameter).

Normal → contrast remains installation followed by manual selection of **Meo Matrix > Apply** in Contrast themes. Contrast → normal attempts the documented transition automatically, with the manual fallback above. Neither direction deletes or rewrites the existing contrast theme from normal mode.

After changed application, a bounded `WM_SETTINGCHANGE` broadcast with `ImmersiveColorSet` notifies applications. Some apps cache colors or ignore notifications; reopen them if necessary. A notification failure is reported separately; stored values are still verified afterward. Verification never retries writes. A persistent mismatch reports the registry path, expected and observed values/types, and retained backup; it remains an application failure. No logout/reboot is forced. Dry-run displays mode, themes, resolved accent, transparency, registry values, backup directory, and the planned contrast transition without creating files/backups, writing registry values, broadcasting, or toggling contrast.

`tests/verify-windows-normal.ps1` uses mocked registry/native operations and isolated file fixtures. It exercises normal previews/application/reapplication, explicit contrast installation, simulated contrast transitions and failures, unchanged Terminal/VS Code plans between modes, backups, concurrent edits, invalid definitions, unusual existing registry types, refresh failures, preserved/normalized DWM high bytes, delayed RGB settlement, persistent RGB rejection, and changes during refresh. Live appearance and a real contrast transition still require user verification.

## Windows Contrast Theme

The adapter generates the name from the identity's `name` field and converts semantic hex values into decimal RGB triples. It never contains an identity-specific palette. The generated file uses the [Windows theme-file format](https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview), with `HighContrast=1` and the AeroLite visual style/selector used by the built-in contrast themes on this machine.

| Windows concept | Theme key | Semantic source |
| --- | --- | --- |
| Background | `Background`, `Window` | `ui.background` |
| Normal text | `WindowText` | `ui.text` |
| Hyperlinks | `HotTrackingColor` | `ui.accentSoft` when accentActive exists; otherwise `ui.accent` |
| Disabled text | `GrayText` | `ui.muted` |
| Selected text foreground | `HilightText` | `ui.text` |
| Selected text background | `Hilight` | `ui.selection` |
| Button foreground | `ButtonText` | `ui.text` |
| Button background | `ButtonFace` | `ui.surface` |
| Inactive title text | `InactiveTitleText` | `ui.muted` |
| Window frame | `WindowFrame` | `ui.border`, falling back to `ui.selection` |
| Active border | `ActiveBorder` | `ui.accentActive`, falling back to `ui.selection` |
| Inactive border | `InactiveBorder` | `ui.border`, falling back to `ui.muted` |

Related menu, border, title, and tooltip colors use the same semantic roles. Syntax colors and the block/bar/underline editing cursor preference have no mapping in this adapter. The theme includes the required desktop section with no wallpaper, as Windows contrast themes do; installing the file alone does not change the desktop.

Meo Matrix separates dark structural borders (`ui.border`, `#1A2720`) from active borders (`ui.accentActive`, `#34784A`) and selection fills (`ui.selection`, `#233C2B`). Links use readable muted green (`ui.accentSoft`). VS Code outer window-border colors are supported only on macOS/Linux with a custom title bar, not Windows; internal panel/tab/focus borders remain configurable. Reinstalling the Windows theme updates its file; reapply Meo Matrix in Contrast themes to activate the new border colors.

Meo Matrix installs at `%LOCALAPPDATA%\Microsoft\Windows\Themes\meowsky-meo-matrix.theme`, displayed as **Meo Matrix**. Paths are resolved for the current user. The file is UTF-16LE with a BOM. No built-in themes, registry entries, or unrelated application configuration are edited.

Repeated installation leaves identical content and its timestamp untouched. Changes update only the dedicated file with a matching Meowsky ownership marker. A collision with an unrelated file, a directory, or a redirected file/directory fails clearly. Updates use a staged file and atomic replacement; failures leave existing files intact and remove the staging file. The generated theme is managed by Identity; customize its JSON definition rather than editing the installed file.

Automatic activation is not implemented. After installation, use **Settings > Accessibility > Contrast themes > Meo Matrix > Apply**. This is the [documented Windows activation flow](https://support.microsoft.com/en-US/accessibility/windows/change-color-contrast-in-windows). Reopen Settings if it was already open. The actual dropdown discovery and visual appearance need manual verification on your Windows version; the tests validate generation and installation without activating contrast mode. If Meo Matrix does not appear, report that behavior rather than modifying built-in themes or registry entries.

## Windows Terminal

The scheme name comes from the identity's `name` field: **Meo Matrix**. Background, foreground, selection background, and cursor color map to `ui.terminalBackground` (falling back to `ui.background`), `ui.terminalText` (falling back to `ui.accent`), `ui.selection`, and `ui.accentBright` respectively. The ANSI scheme makes green dominant, with pale-green white slots and bright secondary hues. Red errors and yellow warnings retain category distinctions:

| ANSI category | Normal | Bright |
| --- | --- | --- |
| Black | `#1A2720` | `#738078` |
| Red | `#E84848` | `#FF7070` |
| Green | `#39FF14` | `#4AFF64` |
| Yellow | `#E6C52F` | `#FFE45C` |
| Blue | `#408CFF` | `#79B0FF` |
| Magenta | `#E05CFF` | `#FF79E6` |
| Cyan | `#00CFE8` | `#00E5FF` |
| White | `#8FFFA0` | `#C7F9CC` |

These are explicit JSON values shared by Windows Terminal and VS Code. Terminal uses the key `purple` for JSON `magenta`; VS Code uses `terminal.ansiMagenta`. No hue rotation or white blending is applied to an explicit palette. Changing branding or syntax cannot change these semantic slots. Definitions without `ansi` keep the previous hue-rotation/lightening behavior in Windows Terminal and preserve non-black ANSI settings in VS Code. An explicit `ansi` object must contain all 16 valid six-digit hex colors.

Cursor preferences map `block` → `filledBox`, `bar` → `bar`, and `underline` → `underscore`. The adapter sets `profiles.defaults.colorScheme` and `profiles.defaults.cursorShape`, following [Terminal profile appearance settings](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance). Direct foreground, background, selection, cursor color, scheme, and cursor-shape overrides are removed from individual profiles and unfocused appearances. Defaults use the identity scheme and cursor shape; unrelated settings stay intact.

Discovery first honors an existing `WT_SETTINGS_DIR/settings.json`. Otherwise it checks existing packaged Stable/Preview directories under the current user's Packages folder, unpackaged settings, and portable settings beside a discovered executable with a `.portable` marker. These match the documented [distribution locations](https://learn.microsoft.com/en-us/windows/terminal/distributions). Missing settings fail without creating files. Multiple matches fail without choosing a file. To disambiguate, open the desired Terminal's Settings > Open JSON file, then set `$env:WT_SETTINGS_DIR` to that file's parent directory before rerunning.

Application adds or updates only the matching scheme's requested fields and the two default profile properties. Other schemes, custom fields, profile lists, commands, startup actions, layouts, fonts, effects, comments, and unrelated source text remain intact. The existing Meowsky Matrix animation, cat/header, workspace geometry, and commands are not edited. A JSONC span reader supports comments and trailing commas so the settings file is not serialized wholesale. Invalid/ambiguous JSON, duplicate scheme names/properties, and legacy array-shaped profiles fail clearly without writes.

Before a changed application, an exact original-byte backup is created beside settings.json as `settings.json.meowsky-<UTC timestamp>-<unique id>.bak`. Encoding/BOM are preserved, replacement is atomic, redirected files/directories are rejected, and concurrent edits cause failure rather than overwriting newer content. A failed replacement retains the backup. Repeated application with identical values performs no write and creates no backup. Dry-run displays the resolved path, palette, cursor/default changes, and backup intent without writing anything.

To restore manually, close Terminal, copy the reported backup over its original settings.json, and reopen Terminal. Test the actual appearance with ordinary ANSI output and `meowsky ./`; all Meowsky panes should use the same neutral green-grey foreground. Semantic ANSI errors, warnings, and application output retain their theme palette colors.

## VS Code UI

`apply <id> --target vscode [--dry-run]` translates UI and syntax roles plus visual preferences into User settings. It leaves `workbench.colorTheme`, unrelated token customizations/styles, extensions, fonts, keybindings, language overrides, and other editor preferences intact. The reference image guides presentation; JSON remains the color source. The base theme continues supplying unspecified scopes and styles.

The exact owned properties are enumerated in `Get-MeowskyVSCodeDefinition` in `features/identity/adapters/vscode.ps1` and printed by dry-run. Mapping groups cover:

| UI area | Properties and semantic sources |
| --- | --- |
| Editor | `editor.background` = background; `editor.foreground` = syntax.text; gutter/line highlight = surface; line numbers = muted/accentSoft. |
| Cursor | `editorCursor.foreground` = accentBright; cursor glyph background = background. `editor.cursorStyle`: block → block, bar → line, underline → underline. |
| Selections | Workbench/editor/list/terminal selections = selection; selection occurrences use selection with alpha `80`. Selection text in lists = text. |
| Sidebar/activity bar | Background = surface, text = text, inactive icons = muted, borders = border; active indicator = accentActive. |
| Status/title bars | Background = surface; foreground = text, inactive title = muted; debugging status = warning/background. |
| Native window border | `window.activeBorder` = accentActive; `window.inactiveBorder` = border. Outer border colors are unsupported on Windows; supported only on macOS/Linux with a custom title bar. |
| Tabs/panels | Active tab = background/text; inactive tab = surface/muted; hover = surfaceRaised/text; panel = surface; active indicators = accentActive; borders = border. |
| Inputs/dropdowns | Background = surface, text = text, placeholders = muted, borders = border, focused controls = accentActive. |
| Lists | Selected/focused background = selection; hover = surfaceRaised; text = text; focus outline = accentActive. |
| Widgets/quick input | Background = surfaceRaised; text = text; widget borders = border. |
| Buttons/badges/links | Primary buttons/badges = accent/onAccent; button hover = accentActive; secondary buttons = surfaceRaised/text; links = accentSoft/accentBright. |
| Scrollbars | Idle/hover = muted with alpha `66`/`99`; active = accentSoft with alpha `99`. |
| Integrated terminal | Background/cursor glyph background = terminalBackground (fallback background), foreground = terminalText (fallback accent), cursor foreground = accentBright, selection = selection; cursor style maps directly to block/bar/underline. All 16 ANSI slots use `ansi` when present; older themes override only ANSI black from terminalBlack when defined. |
| General UI | Foreground = text; disabled/descriptions = muted; errors = error; focus border = accentActive. |

The table describes themes with the optional roles. Older themes retain selection-based structural borders, accent-based focus/links, accentBright button hover, and background-colored button labels. These use the documented [VS Code color customization keys](https://code.visualstudio.com/api/references/theme-color); transparency is an adapter presentation choice derived from the semantic color. No palette is duplicated in the adapter.

Discovery checks existing Stable/Insiders User settings under `%APPDATA%`, portable `data/user-data/User` beside a discovered executable, and existing named-profile settings. `VSCODE_PORTABLE`, when set, selects its portable data root. Missing settings fail without creating a configuration. Multiple files fail rather than guessing the active installation/profile. Locations follow [User settings and profiles](https://code.visualstudio.com/docs/configure/settings) and [portable mode](https://code.visualstudio.com/docs/setup/portable).

For named profiles, custom `--user-data-dir`, or ambiguous installations, open **Preferences: Open User Settings (JSON)** in the desired VS Code window, copy the full file path, then select it explicitly:

```powershell
$env:MEOWSKY_VSCODE_SETTINGS_PATH = 'C:\absolute\path\to\settings.json'
meowsky identity apply meo-matrix --target vscode --dry-run
meowsky identity apply meo-matrix --target vscode
```

The listed UI colors, syntax foreground/diagnostic colors, cursor settings, `window.border`, semantic-highlighting enablement, and syntax rules described below are managed. Existing values for these owned properties are replaced; other properties, theme-specific blocks, comments, and source text are preserved by span edits. Scoped theme, language, workspace, and remote overrides are preserved and may take precedence. The adapter does not remove overrides to force a visual match.

Recent VS Code versions support native Windows border colors through these properties. Identity colors only the VS Code window; the system-wide Windows accent remains unchanged. Restart VS Code when changing `window.border`; see the [VS Code native-border implementation notes](https://github.com/microsoft/vscode/issues/263838).

Changed application uses the same exact-byte backup, encoding/BOM preservation, redirected-path checks, concurrent-edit protection, and atomic replacement as Terminal. The backup path is printed; identical application leaves timestamps unchanged and creates no backup. Malformed JSONC, duplicate properties, or non-object color customizations fail before writing. Dry-run displays every owned UI/syntax color, cursor value, syntax selector/scope, and backup intent without writing. To restore, close VS Code and copy the reported backup over the original file. Visual appearance still needs verification in VS Code; automated tests use temporary settings only.

## VS Code syntax (Step 6)

The same `--target vscode` command applies syntax alongside UI. No theme or language extension is installed, and the selected base theme is retained. Colors come only from `syntax`; adding another identity changes the generated rules without changing the adapter.

| Category | Semantic selectors / fallback | Semantic source (Meo Matrix) |
| --- | --- | --- |
| Comments | `comment` | comment `#8AA890` |
| Keywords / directives | `keyword`; TextMate `storage.modifier`, directive keywords and `#` punctuation | keyword `#39FF14` |
| Functions / methods | `function`, `method`; named/support functions | function `#00E5FF` |
| Types | type/class/struct/enum/interface/typeParameter/namespace; recognized type scopes | type `#66B3FF` |
| Strings / regex | `string`, `regexp`; string/character scopes | string `#FFE45C` |
| Numbers | `number`; numeric constants | number `#FFB454` |
| Constants / macros | `enumMember`, `macro`, readonly variables/properties/parameters; language constants and macro names | constant `#FF79E6` |
| Variables / parameters / fields | `variable`, `parameter`, `property`; identifier scopes | text `#E8FFE8` |
| Operators | `operator`; `keyword.operator` | operator `#C7F9CC` |
| Errors / warnings | `invalid.illegal` / `invalid.deprecated`; `editorError.foreground` / `editorWarning.foreground` | error `#FF7070` / warning `#FFE45C` |
| HTML/CSS | Tags and class/ID selectors use type; attribute/property names use text; quoted values use string | Existing syntax roles |
| Markdown | Headings use keyword; raw/inline code uses string; fenced code uses its embedded grammar | Existing syntax roles |

Variables, parameters, and fields deliberately share the text role because the schema does not define separate colors. This leaves strong distinctions between control flow, calls, constants, strings, comments, and ordinary identifiers without inventing colors. Literal quote marks and ordinary punctuation use text. No font styling is forced.

Semantic highlighting is enabled through `editor.semanticHighlighting.enabled` and `editor.semanticTokenColorCustomizations.enabled`. Language providers supply symbol classifications; the adapter cannot manufacture them. Semantic colors overlay TextMate colors where available, following [VS Code's semantic highlighting model](https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide). No universal semantic error/warning types exist; diagnostics use red/yellow squiggles, and invalid/deprecated lexical scopes use the corresponding colors when emitted. Diagnostic availability depends on the language service.

The merge owns only its exact semantic selectors' foregrounds and TextMate rules named `Meowsky Identity: <role>`. It preserves unrelated selectors, named user rules, theme/language-specific overrides, comments, and existing bold/italic/underline/fontStyle fields. It does not replace the token-customization objects or arrays wholesale. Matching Identity rules are updated in place; missing rules are appended once. Duplicate owned names or malformed customization containers fail without writing. User rules with more specific scopes/selectors or theme-scoped overrides can take precedence; the token inspector identifies the winning rule.

Samples in `docs/samples/` cover C, JavaScript, TypeScript, Python, HTML, CSS, SCSS, PowerShell, Bash, JSON, YAML, Dockerfile, SQL, and Markdown. They are editor samples, not programs to execute/build. The C sample includes headers, macros, typedef/struct, pointers, const, variables, declarations/calls, parameters, strings, numbers, NULL, comments, if/else, and return. Markdown/HTML also exercise embedded languages.

`tests/verify-vscode-syntax.ps1` checks mappings, preservation, ownership, idempotence, malformed settings, and preview output. With Node and an installed VS Code, it additionally uses that installation's TextMate/Oniguruma engines and built-in grammars to check actual token foregrounds in all 14 samples. Missing grammars are explicitly skipped. Supply `-VSCodeAppDirectory '<installation>/resources/app'` for a nonstandard installation. These checks do not run language servers or verify pixels in the editor.

Known grammar limitations found in the installed tokenizer: C's user-defined `Item` type is unclassified and keeps text color until a semantic provider classifies it; SQL's NULL is a keyword and uses keyword color. C's built-in types, control flow, calls, macro definition, literals and operators remain distinguished. Const/readonly classification and call/field/type distinctions vary by language provider. CSS units, preprocessor contents, and Markdown embedded syntax follow the scopes emitted by their grammars. Python, C/C++, PowerShell and other languages need appropriate installed language services for richer semantics; JavaScript/TypeScript have built-in providers. Identity does not install them.

For visual evaluation, open every sample with its intended language mode. Inspect C first: sage comments, neon-green keywords/directives, cyan function names, magenta macro/NULL constants, yellow strings, orange numbers, pale-green operators, and pale green-white identifiers. Inspect HTML tags/attributes, CSS selectors/properties, JSON/YAML keys/scalars, shell variables/strings, SQL keywords, and Markdown headings/fenced C. Use **Developer: Inspect Editor Tokens and Scopes** to check the winning foreground and whether it comes from a semantic token or TextMate scope. Errors/warnings need actual diagnostics; samples intentionally remain valid and do not fabricate diagnostics. Evaluate readability before changing any palette values.

## Verification

```powershell
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-refactor.ps1
powershell -NoProfile -File tests/verify-terminal.ps1
powershell -NoProfile -File tests/verify-vscode.ps1
powershell -NoProfile -File tests/verify-vscode-syntax.ps1
powershell -NoProfile -File tests/verify-identity-apply.ps1
powershell -NoProfile -File tests/verify-windows-normal.ps1
```

The Identity suite uses temporary themes and configuration directories, including installation/collision fixtures; no external applications are launched or themes activated. It verifies mapping, idempotence, atomic updates, unrelated-file preservation, and dry-run behavior.

Invalid command examples (all read-only):

```powershell
meowsky identity apply missing-identity --dry-run
meowsky identity apply ../meo-matrix --dry-run
meowsky identity apply meo-matrix --target unsupported
meowsky identity apply meo-matrix --force
```

The test suite also checks malformed JSON, missing colors, invalid hex values, bad metadata/cursor preferences, second identities, and missing targets using temporary fixtures.

## Visual coherence

The final left, center, and right wallpapers and folder/recycle-bin icons under `features/identity/themes/meo-matrix/` establish the design direction. JSON remains the sole programmatic palette; assets are neither sampled nor read by adapters.

True black backgrounds and dark forest surfaces mirror the desktop shadows. Emerald accents echo the skyline, keyboard, and icon edges; magenta constants add a clear syntax distinction. UI and code text retain their independent roles; ordinary terminal content uses neon Matrix green. The fixed Windows anchor is `#265934`; dark borders use `#1A2720`, active structure uses `#34784A`, and bright emphasis is restrained to `#58CB70`. The terminal direction is mostly luminous green with bright secondary hues; application output determines actual proportions.

Deliberate differences: text and comments are lighter than photographic shadows for sustained reading; syntax keeps yellow strings, orange numbers, blue types, and magenta constants distinct. Errors remain unmistakable red and syntax warnings yellow. Terminal retains explicit blue/cyan/magenta ANSI categories for command output; normal Windows mode retains OS-managed rendering. The palette uses flat semantic colors, not the images' glow or gradients.

Identity colors communicate branding and hierarchy; semantic colors communicate meaning. Neon green carries ordinary terminal information, pale greens fill ANSI white slots, and bright secondary hues distinguish output categories. Terminal ANSI errors use saturated red and warnings use yellow; blue, green, cyan, and magenta remain recognizable. Syntax and UI diagnostic colors keep their separate roles. Bright red and yellow alerts, blue types, cyan functions, and magenta constants distinguish meaning against black. The assets never override functional meaning.

The terminal color direction follows `features/identity/themes/meo-matrix/terminal-view-aim.png`: true black and mostly luminous Matrix-green terminal text. ANSI output retains red/yellow alerts and bright blue, magenta, and cyan; syntax uses bright, distinct colors for functions, types, constants, strings, and numbers. The reference is a visual guide, not a source of layout or runtime behavior.

Syntax colors retain their existing distinctions; terminal ANSI colors favor neon/pale green with bright secondary hues. Keywords are neon green, functions cyan, types bright blue, strings yellow, numbers orange, and constants magenta. Ordinary code text is pale green-white (#E8FFE8), comments are readable sage (#8AA890), and operators are pale green (#C7F9CC). Terminal ordinary text stays neon green (#39FF14); black backgrounds, structural greens, and the Windows accent retain their existing roles.
