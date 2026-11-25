# Current state

The backlog is captured in [spec.md](spec.md). Implementation and runtime acceptance checks are pending.

## Latest verified findings

- Bach runs `git fetch --quiet origin` before launch. A fetch failure produces a warning, and the startup summary can still compare the local upstream tracking ref. The fetch outcome and time are available to capture at the launcher boundary. [Workspace launcher](../features/workspace/workspace.ps1) · [Git summary](../core/git.ps1)
- Upstream Codex source supports skipping repository instruction discovery with `-c project_doc_max_bytes=0`. The prior review did not run a discovery test on the installed CLI. [Codex source](https://github.com/openai/codex/blob/main/codex-rs/core/src/agents_md.rs)
- Windows Terminal supports explicit launch titles and suppression of application title changes. The actual Alt+Tab label still needs a fullscreen layout test. [Launch options](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments) · [Window title setting](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/appearance#use-active-terminal-title-as-application-title)

## Open decisions

- Decide whether to add opt-in auto-pull in a separate batch. The discussed behavior would use `git pull --ff-only` after a successful fetch, with a clean working tree and a branch strictly behind its configured upstream.
- Choose the name of the opt-in Codex launch flag when preparing its implementation batch.

## Next action

Confirm the proposed order and acceptance checks in [spec.md](spec.md). For the first batch, trace the Bach fetch result into the startup summary and prepare the edit gate for reporting its freshness.
