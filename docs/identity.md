# Identity

Identity is Meowsky's system for a coherent visual identity across the development environment. Step 6 adds VS Code semantic and TextMate syntax colors alongside the existing UI, Windows Contrast Theme, and Terminal integrations. Windows contrast activation remains manual; no separate active-identity state is saved. The existing `meowsky color` command remains independent and unchanged.

## Commands

```powershell
. ./powershell/profile.ps1
meowsky identity
meowsky identity list
meowsky identity --help
meowsky identity apply meo-matrix --dry-run
meowsky identity apply meo-matrix --target windows --dry-run
meowsky identity apply meo-matrix --target windows
meowsky identity apply meo-matrix --target terminal --dry-run
meowsky identity apply meo-matrix --target terminal
meowsky identity apply meo-matrix --target vscode --dry-run
meowsky identity apply meo-matrix --target vscode
```

`identity` describes the system. `list` reads and validates every JSON file in `features/identity/themes/`, then prints IDs and display names sorted by ID. The directory is resolved relative to the feature, not the current project. An empty directory reports no identities; invalid definitions report the filename and reason. `--help`, `-h`, and `-Help` show feature help. Other actions report usage. Linux support is not implemented in this step.

`apply <id> --dry-run` loads only the selected theme, so an unrelated invalid definition does not block it. The plan displays the identity, absolute theme path, target availability and evidence, major palette values, cursor preference, Windows theme destination and color mapping, and confirmation that no changes were made. `--target windows --dry-run` previews the Windows installation. The flags can appear in either order. Unknown/duplicate flags and extra arguments are rejected. Even an absent work root is left untouched.

`apply <id> --target windows` installs the generated contrast-theme file without activation. `apply <id> --target terminal` backs up the discovered Terminal settings and updates the identity scheme and profile defaults. An explicit target is required for writes; an unqualified apply is rejected. VS Code UI/syntax overrides are implemented; Neovim integration is not implemented.

## Loading and planning

The flow is theme definition → loader/validator → application plan → target adapter. `identity.ps1` parses commands; `themes.ps1` validates lowercase slug IDs before resolving filenames, parses JSON, and checks metadata, UI/syntax colors, and cursor preferences. Errors distinguish nonexistent identities, unreadable files, malformed JSON, missing semantic values, invalid colors, and unsupported preferences. `plan.ps1` returns a structured plan and formats its preview. `adapters/windows.ps1` owns the Windows renderer/installer. `adapters/terminal.ps1` owns Terminal palette generation, discovery, and planning; `terminal-settings.ps1` handles the scheme/profile merge. `adapters/vscode.ps1` owns VS Code UI mapping, discovery, and planning; `adapters/vscode-syntax.ps1` generates and merges semantic/TextMate syntax rules. Both settings adapters share `settings-jsonc.ps1` for narrow JSONC edits and `settings-file.ps1` for backups and atomic writes. Dry-run never calls a writer. Selecting Terminal or VS Code does not install or activate a Windows contrast theme.

Detection uses read-only installation evidence: Windows is detected from the OS platform; Windows Terminal from `wt.exe` on PATH or a current-user Terminal package; VS Code from `code` on PATH or standard Windows user/system installation paths. These follow the documented [Terminal execution alias](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) and [VS Code installation locations](https://code.visualstudio.com/docs/setup/windows). No target is launched. Undetected targets are reported as skipped and do not fail the plan. Detection does not prove that an application can launch; custom locations without a PATH command may not be detected. Linux shell command support remains outside this step.

## Semantic theme model

`meo-matrix.json` is the first definition. The palette in that file is the source of truth; [Identity-meo-matrix.png](Identity-meo-matrix.png) is a design reference, not a color extraction source.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Format version; currently `1`. |
| `id` | Stable lowercase slug matching the filename without `.json`. |
| `name` | Human-readable display name. |
| `ui` | General interface roles: background, surface, surfaceRaised, text, muted, accent, accentBright, accentSoft, selection, warning, error. |
| `syntax` | Code roles: text, comment, keyword, function, type, string, number, constant, operator, error, warning. |
| `preferences.cursor.style` | Visual behavior: block, bar, or underline. Meo Matrix uses block. |

All listed color roles are required six-digit `#RRGGBB` values. UI and syntax roles are separate even when their colors coincide. Preferences hold visual behavior rather than color values; additional preferences can be introduced when an integration needs them.

`ui.terminalText` is an optional six-digit hex role for default terminal text. Meo Matrix sets it to green `#39FF14`, while general Windows UI text stays pale `ui.text` (`#C7F9CC`). This distinction helps identify a terminal versus a Windows window at a glance. Themes without `terminalText` fall back to `ui.accent` for Terminal foreground; ANSI white and Windows normal text continue using `ui.text`.

## Multiple identities and planned integrations

Add another definition such as `themes/meo-evil.json` with its own matching `id`, name, palette, and preferences. Discovery reads it automatically; no Identity engine or command registration change is needed. Tests use a temporary second identity to verify this.

Windows contrast-theme installation, Windows Terminal schemes/defaults, and VS Code UI/syntax overrides are implemented. Neovim, automatic Windows contrast activation, and separate persistent identity selection belong to later steps. Future adapters will translate semantic roles and supported preferences into each tool's settings. No generic plugin system is needed.

## Windows Contrast Theme

The adapter generates the name from the identity's `name` field and converts semantic hex values into decimal RGB triples. It never contains an identity-specific palette. The generated file uses the [Windows theme-file format](https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview), with `HighContrast=1` and the AeroLite visual style/selector used by the built-in contrast themes on this machine.

| Windows concept | Theme key | Semantic source |
| --- | --- | --- |
| Background | `Background`, `Window` | `ui.background` |
| Normal text | `WindowText` | `ui.text` |
| Hyperlinks | `HotTrackingColor` | `ui.accent` |
| Disabled text | `GrayText` | `ui.muted` |
| Selected text foreground | `HilightText` | `ui.text` |
| Selected text background | `Hilight` | `ui.selection` |
| Button foreground | `ButtonText` | `ui.text` |
| Button background | `ButtonFace` | `ui.surface` |
| Inactive title text | `InactiveTitleText` | `ui.muted` |
| Window frame/active border | `WindowFrame`, `ActiveBorder` | `ui.selection` |
| Inactive border | `InactiveBorder` | `ui.muted` |

Related menu, border, title, and tooltip colors use the same semantic roles. Syntax colors and the block/bar/underline editing cursor preference have no mapping in this adapter. The theme includes the required desktop section with no wallpaper, as Windows contrast themes do; installing the file alone does not change the desktop.

Windows and VS Code active outer borders share `ui.selection` (`#204D27` for Meo Matrix), giving a darker outline while links and focus accents remain bright. Inactive outer borders continue using `ui.muted`. Reinstalling the Windows theme updates its file; reapply Meo Matrix in Contrast themes to activate the new border colors.

Meo Matrix installs at `%LOCALAPPDATA%\Microsoft\Windows\Themes\meowsky-meo-matrix.theme`, displayed as **Meo Matrix**. Paths are resolved for the current user. The file is UTF-16LE with a BOM. No built-in themes, registry entries, or unrelated application configuration are edited.

Repeated installation leaves identical content and its timestamp untouched. Changes update only the dedicated file with a matching Meowsky ownership marker. A collision with an unrelated file, a directory, or a redirected file/directory fails clearly. Updates use a staged file and atomic replacement; failures leave existing files intact and remove the staging file. The generated theme is managed by Identity; customize its JSON definition rather than editing the installed file.

Automatic activation is not implemented. After installation, use **Settings > Accessibility > Contrast themes > Meo Matrix > Apply**. This is the [documented Windows activation flow](https://support.microsoft.com/en-US/accessibility/windows/change-color-contrast-in-windows). Reopen Settings if it was already open. The actual dropdown discovery and visual appearance need manual verification on your Windows version; the tests validate generation and installation without activating contrast mode. If Meo Matrix does not appear, report that behavior rather than modifying built-in themes or registry entries.

## Windows Terminal

The scheme name comes from the identity's `name` field: **Meo Matrix**. Background, foreground, selection background, and cursor color map to `ui.background`, `ui.terminalText` (falling back to `ui.accent`), `ui.selection`, and `ui.accentBright` respectively. The ANSI scheme retains category distinctions:

| ANSI category | Normal | Bright | Source/derivation |
| --- | --- | --- | --- |
| Black | `#050806` | `#66806A` | `ui.background` / `ui.muted` |
| Red | `#FF5C57` | `#FF8581` | `ui.error` / lightened |
| Green | `#39FF14` | `#4AFF64` | `ui.accent` / `ui.accentBright` |
| Yellow | `#FFD866` | `#FFE28C` | `ui.warning` / lightened |
| Blue | `#7295E5` | `#95B0EC` | `syntax.constant` hue +60 degrees / lightened |
| Purple/magenta | `#C765D9` | `#D58CE2` | `syntax.type` hue +160 degrees / lightened |
| Cyan | `#72E5C2` | `#95ECD1` | `syntax.constant` / lightened |
| White | `#C7F9CC` | `#D5FAD9` | `ui.text` / lightened |

Hue rotation preserves the source color's HSV saturation/value; lightening blends each RGB channel 25% toward white. The table describes Meo Matrix's generated result, not a second palette stored in the adapter. Other identities use their own semantic values. Errors stay red, warnings stay yellow, and cool blue/magenta/cyan remain distinct from green. Terminal keys follow the documented [color-scheme format](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes).

Cursor preferences map `block` → `filledBox`, `bar` → `bar`, and `underline` → `underscore`. The adapter sets `profiles.defaults.colorScheme` and `profiles.defaults.cursorShape`, following [Terminal profile appearance settings](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance). Individual profile overrides and direct color overrides retain precedence; they are not removed.

Discovery first honors an existing `WT_SETTINGS_DIR/settings.json`. Otherwise it checks existing packaged Stable/Preview directories under the current user's Packages folder, unpackaged settings, and portable settings beside a discovered executable with a `.portable` marker. These match the documented [distribution locations](https://learn.microsoft.com/en-us/windows/terminal/distributions). Missing settings fail without creating files. Multiple matches fail without choosing a file. To disambiguate, open the desired Terminal's Settings > Open JSON file, then set `$env:WT_SETTINGS_DIR` to that file's parent directory before rerunning.

Application adds or updates only the matching scheme's requested fields and the two default profile properties. Other schemes, custom fields, profile lists, commands, startup actions, layouts, fonts, effects, comments, and unrelated source text remain intact. The existing Meowsky Matrix animation, cat/header, workspace geometry, and commands are not edited. A JSONC span reader supports comments and trailing commas so the settings file is not serialized wholesale. Invalid/ambiguous JSON, duplicate scheme names/properties, and legacy array-shaped profiles fail clearly without writes.

Before a changed application, an exact original-byte backup is created beside settings.json as `settings.json.meowsky-<UTC timestamp>-<unique id>.bak`. Encoding/BOM are preserved, replacement is atomic, redirected files/directories are rejected, and concurrent edits cause failure rather than overwriting newer content. A failed replacement retains the backup. Repeated application with identical values performs no write and creates no backup. Dry-run displays the resolved path, palette, cursor/default changes, and backup intent without writing anything.

To restore manually, close Terminal, copy the reported backup over its original settings.json, and reopen Terminal. Test the actual appearance with ordinary ANSI output and `meowsky ./`; explicit profile overrides may intentionally retain another scheme.

## VS Code UI

`apply <id> --target vscode [--dry-run]` translates UI and syntax roles plus visual preferences into User settings. It leaves `workbench.colorTheme`, unrelated token customizations/styles, extensions, fonts, keybindings, language overrides, and other editor preferences intact. The reference image guides presentation; JSON remains the color source. The base theme continues supplying unspecified scopes and styles.

The exact owned properties are enumerated in `Get-MeowskyVSCodeDefinition` in `features/identity/adapters/vscode.ps1` and printed by dry-run. Mapping groups cover:

| UI area | Properties and semantic sources |
| --- | --- |
| Editor | `editor.background` = background; `editor.foreground` = syntax.text; gutter/line highlight = surface; line numbers = muted/accentSoft. |
| Cursor | `editorCursor.foreground` = accentBright; cursor glyph background = background. `editor.cursorStyle`: block → block, bar → line, underline → underline. |
| Selections | Workbench/editor/list/terminal selections = selection; selection occurrences use selection with alpha `80`. Selection text in lists = text. |
| Sidebar/activity bar | Background = surface, text = text, inactive icons = muted, borders = selection; active indicator = accent. |
| Status/title bars | Background = surface; foreground = text, inactive title = muted; debugging status = warning/background. |
| Native window border | `window.activeBorder` = selection; `window.inactiveBorder` = muted; `window.border` = `default` enables the theme border. |
| Tabs/panels | Active tab = background/text; inactive tab = surface/muted; hover = surfaceRaised/text; panel = surface; active indicators = accent; borders = selection. |
| Inputs/dropdowns | Background = surface, text = text, placeholders = muted, borders = selection, focused controls = accent. |
| Lists | Selected/focused background = selection; hover = surfaceRaised; text = text; focus outline = accent. |
| Widgets/quick input | Background = surfaceRaised; text = text; widget borders = selection. |
| Buttons/badges/links | Primary buttons/badges = accent/background; hover = accentBright; secondary buttons = surfaceRaised/text; links = accent/accentBright. |
| Scrollbars | Idle/hover = muted with alpha `66`/`99`; active = accentSoft with alpha `99`. |
| Integrated terminal | Background = background, foreground = terminalText (fallback accent), cursor = accentBright/background, selection = selection; cursor style maps directly to block/bar/underline. ANSI colors remain unchanged. |
| General UI | Foreground = text; disabled/descriptions = muted; errors = error; focus border = accent. |

These use the documented [VS Code color customization keys](https://code.visualstudio.com/api/references/theme-color); transparency is an adapter presentation choice derived from the semantic color. No palette is duplicated in the adapter.

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
| Comments | `comment` | comment `#52705A` |
| Keywords / directives | `keyword`; TextMate `storage.modifier`, directive keywords and `#` punctuation | keyword `#39FF14` |
| Functions / methods | `function`, `method`; named/support functions | function `#8FFFA0` |
| Types | type/class/struct/enum/interface/typeParameter/namespace; recognized type scopes | type `#65D97A` |
| Strings / regex | `string`, `regexp`; string/character scopes | string `#B8D96C` |
| Numbers | `number`; numeric constants | number `#D7FF87` |
| Constants / macros | `enumMember`, `macro`, readonly variables/properties/parameters; language constants and macro names | constant `#72E5C2` |
| Variables / parameters / fields | `variable`, `parameter`, `property`; identifier scopes | text `#C7F9CC` |
| Operators | `operator`; `keyword.operator` | operator `#91AA96` |
| Errors / warnings | `invalid.illegal` / `invalid.deprecated`; `editorError.foreground` / `editorWarning.foreground` | error `#FF5C57` / warning `#FFD866` |
| HTML/CSS | Tags and class/ID selectors use type; attribute/property names use text; quoted values use string | Existing syntax roles |
| Markdown | Headings use keyword; raw/inline code uses string; fenced code uses its embedded grammar | Existing syntax roles |

Variables, parameters, and fields deliberately share the text role because the schema does not define separate colors. This leaves strong distinctions between control flow, calls, constants, strings, comments, and ordinary identifiers without inventing colors. Literal quote marks and ordinary punctuation use text. No font styling is forced.

Semantic highlighting is enabled through `editor.semanticHighlighting.enabled` and `editor.semanticTokenColorCustomizations.enabled`. Language providers supply symbol classifications; the adapter cannot manufacture them. Semantic colors overlay TextMate colors where available, following [VS Code's semantic highlighting model](https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide). No universal semantic error/warning types exist; diagnostics use red/yellow squiggles, and invalid/deprecated lexical scopes use the corresponding colors when emitted. Diagnostic availability depends on the language service.

The merge owns only its exact semantic selectors' foregrounds and TextMate rules named `Meowsky Identity: <role>`. It preserves unrelated selectors, named user rules, theme/language-specific overrides, comments, and existing bold/italic/underline/fontStyle fields. It does not replace the token-customization objects or arrays wholesale. Matching Identity rules are updated in place; missing rules are appended once. Duplicate owned names or malformed customization containers fail without writing. User rules with more specific scopes/selectors or theme-scoped overrides can take precedence; the token inspector identifies the winning rule.

Samples in `docs/samples/` cover C, JavaScript, TypeScript, Python, HTML, CSS, SCSS, PowerShell, Bash, JSON, YAML, Dockerfile, SQL, and Markdown. They are editor samples, not programs to execute/build. The C sample includes headers, macros, typedef/struct, pointers, const, variables, declarations/calls, parameters, strings, numbers, NULL, comments, if/else, and return. Markdown/HTML also exercise embedded languages.

`tests/verify-vscode-syntax.ps1` checks mappings, preservation, ownership, idempotence, malformed settings, and preview output. With Node and an installed VS Code, it additionally uses that installation's TextMate/Oniguruma engines and built-in grammars to check actual token foregrounds in all 14 samples. Missing grammars are explicitly skipped. Supply `-VSCodeAppDirectory '<installation>/resources/app'` for a nonstandard installation. These checks do not run language servers or verify pixels in the editor.

Known grammar limitations found in the installed tokenizer: C's user-defined `Item` type is unclassified and keeps text color until a semantic provider classifies it; SQL's NULL is a keyword and uses keyword color. C's built-in types, control flow, calls, macro definition, literals and operators remain distinguished. Const/readonly classification and call/field/type distinctions vary by language provider. CSS units, preprocessor contents, and Markdown embedded syntax follow the scopes emitted by their grammars. Python, C/C++, PowerShell and other languages need appropriate installed language services for richer semantics; JavaScript/TypeScript have built-in providers. Identity does not install them.

For visual evaluation, open every sample with its intended language mode. Inspect C first: subdued comments, green keywords/directives, soft-green function names, cyan macro/NULL constants, distinct string/number colors, neutral operators, and pale identifiers. Inspect HTML tags/attributes, CSS selectors/properties, JSON/YAML keys/scalars, shell variables/strings, SQL keywords, and Markdown headings/fenced C. Use **Developer: Inspect Editor Tokens and Scopes** to check the winning foreground and whether it comes from a semantic token or TextMate scope. Errors/warnings need actual diagnostics; samples intentionally remain valid and do not fabricate diagnostics. Evaluate readability before changing any palette values.

## Verification

```powershell
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-refactor.ps1
powershell -NoProfile -File tests/verify-terminal.ps1
powershell -NoProfile -File tests/verify-vscode.ps1
powershell -NoProfile -File tests/verify-vscode-syntax.ps1
```

The Identity suite uses temporary themes and configuration directories, including installation/collision fixtures; no external applications are launched or themes activated. It verifies mapping, idempotence, atomic updates, unrelated-file preservation, and dry-run behavior.

Invalid command examples (all read-only):

```powershell
meowsky identity apply missing-identity --dry-run
meowsky identity apply ../meo-matrix --dry-run
meowsky identity apply meo-matrix
meowsky identity apply meo-matrix --force
```

The test suite also checks malformed JSON, missing colors, invalid hex values, bad metadata/cursor preferences, second identities, and missing targets using temporary fixtures.
