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

## Workspace folder name in Alt+Tab

- Set the same folder-name title on every Windows Terminal pane opened by `meowsky ./` and `meowsky bach`. Suppressed pane application title changes.
- All 384 checks in `tests/verify-refactor.ps1` passed. The launcher checks cover the three-pane layout, Bach's two-pane layout, and a folder name containing spaces.
- Fullscreen Alt+Tab inspection remains open. Verify the visible label for both commands before and after changing pane focus.

## Stopping point before wildcard previews

- Verified that the title change is committed as `cc79891`. Dropped the font-size change at the user's request.
- Agreed to cover both Markdown and PDF on PowerShell and Bash. Inspected the single-file handlers and paused at the implementation edit gate.
- Resume by confirming the preview batch. Fullscreen Alt+Tab and global instruction loading still need runtime checks. Opt-in auto-pull remains a separate decision.

## Wildcard Markdown and PDF previews

- Added current-directory wildcard selection to PowerShell and handled both literal patterns and Bash-expanded arguments. Each Markdown render uses a distinct temporary output directory.
- `tests/verify-refactor.ps1` passed 399 checks. `tests/verify-linux.sh` passed under Git Bash, with mocked rendering and viewer launch. Both suites exercised the public preview commands, including unquoted wildcards, filenames with spaces, mixed types, no matches, directories, and colliding Markdown names.
- On Codex 0.172.0, prompt inspection with the installed Codex home found global instructions with and without the skip option. Repository instructions appeared only without the option. Fullscreen Alt+Tab verification remains open.
- Next, commit this batch and prepare the documentation inventory and migration proposal.

## Documentation inventory and migration plan

- Confirmed the preview implementation commit (`fa89856`) and its separate handoff commit (`09b574e`).
- Inventoried the tracked guides, conventions, samples, and feature resources. Recorded proposed owners and link updates in [the spec](spec.md#devkit-documentation-cleanup), including the stale root checklist and the duplicated launcher guidance in README and setup.
- Verified the stable C guide and sample paths against code or test references. Actual guide migration is outside this plan batch. Fullscreen Alt+Tab inspection is still pending.

## Codex title updates in fullscreen workspaces

- A fresh launch still showed the Codex thread name and folder in Alt+Tab. The expected title is the original launch folder for `meowsky ./` or `bach` for `meowsky bach`, including after switching panes or changing directory.
- Passed `tui.terminal_title=[]` to Codex for these two launch commands. The PowerShell suite passed 402 checks, including both affected commands, the combined `--skip` arguments, and the Launchpad launch.
- You confirmed that the title works after updating your PowerShell profile. The desktop report did not specify a separate Bach run or pane-by-pane results. The regression suite covers the arguments for both launches.
