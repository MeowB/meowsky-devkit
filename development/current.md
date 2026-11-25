# Current state

Startup Git status freshness (`0f71fb7`), the workspace skip flag (`db1af56`), and the workspace title (`cc79891`) are committed. Development-first Codex orientation is committed as `da697d4`. Wildcard previews are committed in `fa89856`, with their handoff recorded in `09b574e`. The font-size change was dropped in favor of the manual shortcut.

## Latest verified findings

- Bach and Launchpad verify the configured origin upstream at launch and show the successful fetch time. Launch paths without a successful upstream check label available counts as cached. A missing upstream reports unknown. The Windows PowerShell regression suite passed 365 checks, including local Git cases for behind, failed fetch, no fetch, and no upstream. [Workspace launcher](../features/workspace/workspace.ps1) · [Git summary](../core/git.ps1)
- `meowsky ./ -s` and `meowsky ./ --skip` pass `-c project_doc_max_bytes=0` to Codex. The Windows suite passed 382 checks, including both flags, help, and the default launch. Prompt inspection on Codex 0.171.0 verified that the override omits root and nested instructions. A follow-up prompt inspection on Codex 0.172.0 with the installed Codex home verified that global instructions load both with and without the override. [Codex source](https://github.com/openai/codex/blob/main/codex-rs/core/src/agents_md.rs)
- The launcher passes the workspace folder name to every pane for `meowsky ./` and `meowsky bach` and suppresses application title changes. The PowerShell suite passed 384 checks, including a workspace name with spaces. The actual fullscreen Alt+Tab label still needs a desktop test with Windows Terminal's application-title setting enabled. [Launch options](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) · [Window title setting](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/appearance#use-active-terminal-title-as-application-title)

- The Windows and Bash preview entry points accept bare `*` and their type-specific wildcard. Both suites verified selection, filenames with spaces, exclusion of directories, no-match errors, single-file behavior, and distinct Markdown output paths. The suites mock the renderer and viewer.

## Open decisions

- Decide whether to add opt-in auto-pull in a separate batch. The discussed behavior would use `git pull --ff-only` after a successful fetch, with a clean working tree and a branch strictly behind its configured upstream.

## Next action

The documentation inventory and approved migration plan are recorded in [spec.md](spec.md#devkit-documentation-cleanup). Actual guide migration requires its own edit batches. The fullscreen Alt+Tab check remains open for `meowsky ./` and `meowsky bach`.
