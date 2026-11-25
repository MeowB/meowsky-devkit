# Iterations

## Feasibility review and handoff setup

- Reviewed all backlog items. Checked the Bach fetch path and local upstream comparison, Codex's project instruction override, and Windows Terminal's title controls.
- Recorded the requested Alt+Tab behavior for both launch commands and the one-step terminal font reduction. Captured auto-pull as an open decision.
- Moved the backlog into the four-file handoff and kept the root notes as the workflow entry point.
- Next, confirm the spec and investigate the first Git status batch. Verify Codex discovery and the Alt+Tab title at runtime in their respective batches.

## Startup Git status freshness

- Carried the verified origin upstream and fetch time from the Windows district launcher into the startup summary. The summary labels cached counts and reports unknown when an upstream comparison is unavailable.
- Ran `powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-refactor.ps1`. All 365 checks passed. Local Git checks verified a fresh behind comparison, a failed fetch, a summary without fetch, and a missing upstream. They also checked that HEAD, branch, and working tree stayed unchanged.
- Next, commit this batch and prepare the opt-in Codex launch flag.

## Opt-in workspace instruction skip

- Added Windows workspace flags `-s` and `--skip`. Removed the `-ShowHelp` parameter that captured `-s` and documented `-h` and `--help`. Kept `-Help` for compatibility.
- All 382 checks in `tests/verify-refactor.ps1` passed. An installed Codex 0.171.0 prompt inspection found both repository instruction fixtures on a default launch and omitted both with the override.
- A runtime check with a global instruction file remains open. Next, commit the batch, verify that case, and review the Alt+Tab batch.
