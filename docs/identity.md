# Identity

Identity is Meowsky's system for a coherent visual identity across the development environment. Step 3 adds Windows Contrast Theme generation and installation to semantic theme loading and dry-run planning. Activation remains manual; no active identity is saved. The existing `meowsky color` command remains independent and unchanged.

## Commands

```powershell
. ./powershell/profile.ps1
meowsky identity
meowsky identity list
meowsky identity --help
meowsky identity apply meo-matrix --dry-run
meowsky identity apply meo-matrix --target windows --dry-run
meowsky identity apply meo-matrix --target windows
```

`identity` describes the system. `list` reads and validates every JSON file in `features/identity/themes/`, then prints IDs and display names sorted by ID. The directory is resolved relative to the feature, not the current project. An empty directory reports no identities; invalid definitions report the filename and reason. `--help`, `-h`, and `-Help` show feature help. Other actions report usage. Linux support is not implemented in this step.

`apply <id> --dry-run` loads only the selected theme, so an unrelated invalid definition does not block it. The plan displays the identity, absolute theme path, target availability and evidence, major palette values, cursor preference, Windows theme destination and color mapping, and confirmation that no changes were made. `--target windows --dry-run` previews the Windows installation. The flags can appear in either order. Unknown/duplicate flags and extra arguments are rejected. Even an absent work root is left untouched.

`apply <id> --target windows` installs the generated contrast-theme file without activation. An explicit target is required for installation; an unqualified apply is rejected. Windows Terminal, VS Code, and Neovim adapters are not implemented.

## Loading and planning

The flow is theme definition → loader/validator → application plan → target adapter. `identity.ps1` parses commands; `themes.ps1` validates lowercase slug IDs before resolving filenames, parses JSON, and checks metadata, UI/syntax colors, and cursor preferences. Errors distinguish nonexistent identities, unreadable files, malformed JSON, missing semantic values, invalid colors, and unsupported preferences. `plan.ps1` returns a structured plan and formats its preview. `adapters/windows.ps1` owns the pure Windows renderer and guarded installer. Dry-run uses the renderer and never calls the installer.

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

## Multiple identities and planned integrations

Add another definition such as `themes/meo-evil.json` with its own matching `id`, name, palette, and preferences. Discovery reads it automatically; no Identity engine or command registration change is needed. Tests use a temporary second identity to verify this.

Windows contrast-theme installation is implemented. Windows Terminal, VS Code, Neovim, automatic activation, and persistent selection belong to later steps. Future adapters will translate semantic roles and supported preferences into each tool's settings. No generic plugin system is needed.

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

Related menu, border, title, and tooltip colors use the same semantic roles. Syntax colors and the block/bar/underline editing cursor preference have no mapping in this adapter. The theme includes the required desktop section with no wallpaper, as Windows contrast themes do; installing the file alone does not change the desktop.

Meo Matrix installs at `%LOCALAPPDATA%\Microsoft\Windows\Themes\meowsky-meo-matrix.theme`, displayed as **Meo Matrix**. Paths are resolved for the current user. The file is UTF-16LE with a BOM. No built-in themes, registry entries, or unrelated application configuration are edited.

Repeated installation leaves identical content and its timestamp untouched. Changes update only the dedicated file with a matching Meowsky ownership marker. A collision with an unrelated file, a directory, or a redirected file/directory fails clearly. Updates use a staged file and atomic replacement; failures leave existing files intact and remove the staging file. The generated theme is managed by Identity; customize its JSON definition rather than editing the installed file.

Automatic activation is not implemented. After installation, use **Settings > Accessibility > Contrast themes > Meo Matrix > Apply**. This is the [documented Windows activation flow](https://support.microsoft.com/en-US/accessibility/windows/change-color-contrast-in-windows). Reopen Settings if it was already open. The actual dropdown discovery and visual appearance need manual verification on your Windows version; the tests validate generation and installation without activating contrast mode. If Meo Matrix does not appear, report that behavior rather than modifying built-in themes or registry entries.

## Verification

```powershell
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-refactor.ps1
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
