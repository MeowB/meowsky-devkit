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

Running `meowsky md *` did not open the Markdown files as expected. On PowerShell and Bash, support `meowsky md *` and `meowsky md *.md`, plus `meowsky pdf *` and `meowsky pdf *.pdf`. Keep single-file usage working.

**Acceptance.** On both shells, open only matching files from a directory with mixed file types, filenames with spaces, and subdirectories. Check single-file usage, both wildcard forms, the no-match message, and distinct output paths for Markdown files whose names normalize to the same HTML name.

## DevKit documentation cleanup

Inventory the DevKit docs by audience and ownership. Flag overlap, stale guidance, and misplaced material. Propose a structure and migration plan before reorganizing the docs.

**Acceptance.** The plan maps each affected document to its proposed location or owner and lists links that need to change.
