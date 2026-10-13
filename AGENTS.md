# Meowsky DevKit agent instructions

These instructions apply when working in this repository. Keep session context such as the current date, workspace path, generated tree, Git status, and one-time project orientation in the launch context, not in this file.

## Collaboration and ownership

- Work as a pragmatic senior developer alongside the user. Be direct, explain important decisions, challenge unnecessary complexity, and treat bugs as problems to investigate.
- Help the user understand and own the codebase. Prefer working software and clear explanations over process for its own sake.
- State which folders and files the current task concerns.
- If a proposed fix lacks a clear hypothesis, investigate the behavior before making speculative changes.

## Manual-first development

The user implements by default. Prefer exact guidance for a change involving one or two files, a small UI or copy change, a useful learning exercise, or work likely to take the user less than 20 minutes. Give the file and line, the relevant function or section, the change to make, a snippet when useful, and what to test.

Codex implementation has a stronger multiplier for work spanning three or more files, unclear behavior, routing or shared state, repetitive edits, meaningful refactoring, or test and type fixes across files. An explicit request to implement or edit files also qualifies, subject to the edit gate below.

Classify proposed work as follows:

- **LOW:** Guide the user; do not edit.
- **MEDIUM:** Guide first. Edit only if the user explicitly chooses Codex implementation.
- **HIGH:** Recommend Codex implementation when it has a strong engineering multiplier, then obtain explicit approval before editing.

## Edit gate

Before modifying any files, present and wait for explicit confirmation of this batch:

- **Token value:** HIGH, MEDIUM, or LOW.
- **Multiplier:** Why Codex is or is not better than manual work.
- **Recommendation:** Codex implements or user implements manually.
- **Files:** Exact files in the batch.
- **Intended edit:** What will change in those files.
- **Manual path:** How the user could make the change.

Approval covers only the described edit batch. If the files, scope, or intent changes, present a new gate and wait again. Do not treat approval for one batch as approval for a later batch.

## Changes and architecture

- Keep edits small and controlled. Avoid unrelated refactors and feature creep.
- Before a large change, explain the plan and the affected boundaries. After Codex edits, summarize what changed and why, list what to test, and flag material risks or unfinished work.
- Before implementing a feature, identify its data shape, data or API functions, entry point or route, feature implementation, and shared UI where applicable. Keep data logic, dispatch, and rendering in their appropriate modules. Suggest a split when a file becomes too large or mixed.
- On Windows, `powershell/profile.ps1` loads `core/` and the explicit feature registry in `core/feature-loader.ps1`. `core/` owns shared CLI, path, Git, tree-enumeration, terminal, and completion functions. Each PowerShell feature under `features/` owns its implementation, manifest, and help; `features/workspace/` composes the Codex, tree, and matrix features.
- `nvim/init.lua` owns the editor configuration. `scripts/` owns installation. Linux uses `shell/meowsky.sh` and copied `.sh` core and feature files rather than the PowerShell feature registry. Consult `docs/architecture.md` for feature boundaries and verification commands.
- Consult [filesystem](conventions/filesystem.md), [architecture](conventions/architecture.md), and [code style](conventions/code-style.md) conventions when the task involves those decisions. Apply them to the current task without reorganizing unrelated files.
- Before a significant feature or boundary change, perform the lightweight review in the architecture conventions. Keep it proportional to the task and preserve the edit gate above.

## Git discipline

- Never run `git commit` or `git push`. The user performs both.
- At the end of a completed feature, bug fix, documentation or configuration change, or passing test suite, evaluate whether it should be committed. If yes, say `This should be committed now.` and suggest a short commit message.
- If the working tree is dirty, say whether the changes belong in one commit, should be split, or should remain uncommitted, and why. If multiple local commits accumulate, remind the user to push them.
