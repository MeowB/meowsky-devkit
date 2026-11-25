# DevKit backlog specification

## Recommended implementation order

1. Clarify startup Git status.
2. Add the opt-in Codex launch flag.
3. Set the Alt+Tab title.
4. Add wildcard previews for Markdown and PDF.
5. Inventory the docs and propose a migration plan.

## Startup Git status

A Bach launch reported a clean `main` with `ahead 0, behind 0 vs origin/main`. A later push was rejected with `fetch first`. The report alone cannot establish when the remote changed or whether the initial comparison used cached refs.

Carry the remote check result into the startup summary. Show when the configured upstream was last verified by this launch. If the check fails, label available counts as cached and pull status as unverified. If there is no upstream to compare, report that status as unknown. A successful fetch should inform the summary without merging or rebasing.

**Acceptance.** Check a successful fetch against a behind branch, a failed fetch with cached counts, and a branch without an upstream. Confirm that the current branch and working tree are preserved.

## Skip repository instructions at launch

Add an opt-in flag to `meowsky ./` that skips automatic loading of repository `AGENTS.md` instructions. The Codex config override under consideration applies to the full repository instruction chain, including nested files.

**Acceptance.** On the installed CLI, verify default discovery and verify that the opt-in launch skips root and nested project instructions while still loading global instructions.

## Project directory in the Alt+Tab title

For `meowsky ./` and `meowsky bach`, show only the final folder name of the directory that the command opens. For example, a launch from `C:\meowsky\my-app` shows `my-app`, and a Bach launch shows `bach`.

**Acceptance.** Launch both commands and verify the Alt+Tab label in the fullscreen layout before and after switching panes.

## Windows Terminal font size

Dropped. Use `Ctrl+-` manually when needed.

## Preview Markdown and PDF files in the current directory

Running `meowsky md *` did not open the Markdown files as expected. On PowerShell and Bash, support `meowsky md *` and `meowsky md *.md`, plus `meowsky pdf *` and `meowsky pdf *.pdf`. Keep single-file usage working for the command's file type. Bash must accept unquoted wildcards by processing the arguments Bash expands, as well as literal patterns passed to the command. Wildcards cover the current directory without recursing.

**Acceptance.** On both shells, open only matching files from a directory with mixed file types, filenames with spaces, and subdirectories. Check single-file usage, both wildcard forms, the no-match message, and distinct output paths for Markdown files whose names normalize to the same HTML name.

## DevKit documentation cleanup

Inventory the DevKit docs by audience and ownership. Flag overlap, stale guidance, and misplaced material. Propose a structure and migration plan before reorganizing the docs.

**Acceptance.** The plan maps each affected document to its proposed location or owner and lists links that need to change.

### Inventory and target ownership

| Current document or section | Audience | Proposed location and link changes |
| --- | --- | --- |
| `README.md` | New and returning users | Keep the project overview, quick start, and guide index here. Replace repeated setup links with one entry per purpose. Link daily workflows to `docs/workspace.md`, audit procedures to `docs/workspace-audit.md`, and detailed theme setup to `docs/identity.md`. Retain a direct Terminal troubleshooting link to the setup guide. |
| `docs/new-pc-dev-setup.md` | Users installing or repairing the DevKit | Keep Windows and Linux installation, execution policy, Terminal configuration, and verification here. Move daily command examples, launcher behavior, and preview guidance to `docs/workspace.md` and link to it. Preserve the README's Terminal troubleshooting link by updating its fragment if the relevant heading changes. |
| Daily workflow in `README.md` and `docs/new-pc-dev-setup.md` | Users running Meowsky | Consolidate detailed launcher, preview, and prompt behavior in the proposed `docs/workspace.md`. Move the setup guide's district continuity and Codex template references into this guide, preserving their current targets. Keep command syntax in feature help. |
| Workspace Audit section in `README.md` | Users auditing and reviewing projects | Put the audit, review, and refactor procedures in the proposed `docs/workspace-audit.md`. Link to it from the README and architecture guide. The README's link to `features/audit/refactor-prompt.md` moves with the procedures and gains a `../` prefix. |
| `docs/c-development.md` | Windows C learners | Keep its path. README, setup, and architecture links stay valid, as do references in the Codex launcher, installer, C feature, and tests. |
| `docs/district-continuity.md` | Bach and Launchpad users | Keep its path. Link from the workspace guide. Preserve the README, architecture, and Bach help references wherever the surrounding material remains. |
| `docs/identity.md` and `docs/samples/` | Theme users and syntax testers | Keep current theme application, verification, and adapter behavior in the Identity guide. Point the README's detailed theme examples here. Keep sample paths used by Identity help and `tests/verify-vscode-syntax.ps1`. |
| `docs/meo-matrix-implementation-report.md` | Maintainers researching past theme decisions | Move the dated report to `docs/archive/`. No tracked file links to its current path. Change its relative theme definition link from `../features/` to `../../features/`. |
| `docs/architecture.md` | DevKit maintainers | Keep module ownership, installer boundaries, and verification here. Add links to the workspace and audit guides for procedures. |
| `AGENTS.md`, `conventions/*.md`, and feature prompts or help | Agents and contributors | Keep repository policy and reusable conventions in place. Keep launcher prompts and command help with their features. Preserve links to these resources when moving surrounding prose. |
| `development-notes.md` and `development/` | DevKit maintainers and returning agents | Replace the stale root checklist with links to `development/current.md` and `development/spec.md`. Keep active state, backlog, goal, and iteration history in `development/`. |

### Migration sequence

1. Make the root development notes a pointer to the handoff. The current checklist duplicates the backlog and still presents completed items and the dropped font-size change as pending.
2. Consolidate daily launch and preview guidance in the workspace guide. Add the verified wildcard forms and remove duplicated launcher detail from the setup guide. Update README navigation and check the Terminal troubleshooting anchor.
3. Move user-facing audit procedures into their own guide. Add the README and architecture links and verify the relocated prompt link.
4. Trim duplicated theme application detail in the README, then archive the dated Meo Matrix report and update its relative links.
5. Check local links and heading fragments from every edited document. Compare documented commands with feature help and check the unchanged C guide, theme sample, and prompt paths against their runtime or test references.

This plan covers inventory and ownership. Apply the migration in separately approved batches.
