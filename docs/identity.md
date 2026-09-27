# Identity

Identity is Meowsky's system for a coherent visual identity across the development environment. Step 2 loads and validates themes and previews application plans through the existing PowerShell feature CLI. It does not apply an identity, save an active identity, or modify application settings. The existing `meowsky color` command remains independent and unchanged.

## Commands

```powershell
. ./powershell/profile.ps1
meowsky identity
meowsky identity list
meowsky identity --help
meowsky identity apply meo-matrix --dry-run
```

`identity` describes the system. `list` reads and validates every JSON file in `features/identity/themes/`, then prints IDs and display names sorted by ID. The directory is resolved relative to the feature, not the current project. An empty directory reports no identities; invalid definitions report the filename and reason. `--help`, `-h`, and `-Help` show feature help. Other actions report usage. Linux support is not implemented in this step.

`apply <id> --dry-run` loads only the selected theme, so an unrelated invalid definition does not block it. The exact `--dry-run` flag is required; missing flags, unknown flags, and extra arguments are rejected. The plan displays the identity, absolute theme path, target availability and evidence, major palette values, cursor preference, and confirmation that no changes were made. Even an absent work root is left untouched.

## Loading and planning

The flow is theme definition → loader/validator → application plan → future adapters. `identity.ps1` parses commands; `themes.ps1` validates lowercase slug IDs before resolving filenames, parses JSON, and checks metadata, UI/syntax colors, and cursor preferences. Errors distinguish nonexistent identities, unreadable files, malformed JSON, missing semantic values, invalid colors, and unsupported preferences. `plan.ps1` returns a structured plan and formats its preview. No adapters are implemented.

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

Planned integrations are Windows appearance, Windows Terminal, VS Code, and Neovim. Future adapters will translate semantic roles and preferences into each tool's settings. Neovim detection, persistent selection, application, and adapters belong to later steps. No generic plugin system is needed.

## Verification

```powershell
powershell -NoProfile -File tests/verify-identity.ps1
powershell -NoProfile -File tests/verify-refactor.ps1
```

The Identity suite uses temporary themes and configuration directories; no external applications are launched.

Invalid command examples (all read-only):

```powershell
meowsky identity apply missing-identity --dry-run
meowsky identity apply ../meo-matrix --dry-run
meowsky identity apply meo-matrix
meowsky identity apply meo-matrix --force
```

The test suite also checks malformed JSON, missing colors, invalid hex values, bad metadata/cursor preferences, second identities, and missing targets using temporary fixtures.
