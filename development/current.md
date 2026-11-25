# Current state

The startup Git status batch is implemented and verified. It awaits the manual commit. The rest of the backlog is pending.

## Latest verified findings

- Bach and Launchpad verify the configured origin upstream at launch and show the successful fetch time. Launch paths without a successful upstream check label available counts as cached. A missing upstream reports unknown. The Windows PowerShell regression suite passed 365 checks, including local Git cases for behind, failed fetch, no fetch, and no upstream. [Workspace launcher](../features/workspace/workspace.ps1) · [Git summary](../core/git.ps1)
- Upstream Codex source supports skipping repository instruction discovery with `-c project_doc_max_bytes=0`. The prior review did not run a discovery test on the installed CLI. [Codex source](https://github.com/openai/codex/blob/main/codex-rs/core/src/agents_md.rs)
- Windows Terminal supports explicit launch titles and suppression of application title changes. The actual Alt+Tab label still needs a fullscreen layout test. [Launch options](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) · [Window title setting](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/appearance#use-active-terminal-title-as-application-title)

## Open decisions

- Decide whether to add opt-in auto-pull in a separate batch. The discussed behavior would use `git pull --ff-only` after a successful fetch, with a clean working tree and a branch strictly behind its configured upstream.
- Choose the name of the opt-in Codex launch flag when preparing its implementation batch.

## Next action

After the manual Git status commit is verified, trace the Codex launch argument path and prepare the opt-in repository instruction batch from [spec.md](spec.md).
