# Current state

Startup Git status freshness is committed as `0f71fb7`; the workspace skip flag is committed as `db1af56`. The workspace title change awaits the manual commit. The remaining features are pending.

## Latest verified findings

- Bach and Launchpad verify the configured origin upstream at launch and show the successful fetch time. Launch paths without a successful upstream check label available counts as cached. A missing upstream reports unknown. The Windows PowerShell regression suite passed 365 checks, including local Git cases for behind, failed fetch, no fetch, and no upstream. [Workspace launcher](../features/workspace/workspace.ps1) · [Git summary](../core/git.ps1)
- `meowsky ./ -s` and `meowsky ./ --skip` pass `-c project_doc_max_bytes=0` to Codex. The Windows suite passed 382 checks, including both flags, help, and the default launch. Prompt inspection on Codex 0.171.0 verified that the override omits root and nested instructions. The global instruction runtime check is pending because this environment has no global instruction file. [Codex source](https://github.com/openai/codex/blob/main/codex-rs/core/src/agents_md.rs)
- The launcher passes the workspace folder name to every pane for `meowsky ./` and `meowsky bach` and suppresses application title changes. The PowerShell suite passed 384 checks, including a workspace name with spaces. The actual fullscreen Alt+Tab label still needs a desktop test with Windows Terminal's application-title setting enabled. [Launch options](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) · [Window title setting](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/appearance#use-active-terminal-title-as-application-title)

## Open decisions

- Decide whether to add opt-in auto-pull in a separate batch. The discussed behavior would use `git pull --ff-only` after a successful fetch, with a clean working tree and a branch strictly behind its configured upstream.

## Next action

After the title batch is committed, verify the fullscreen Alt+Tab behavior for both launch commands and review the font-size batch in [spec.md](spec.md). The skip flag still needs a runtime check on a Codex installation with global instructions.
