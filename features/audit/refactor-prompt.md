# Audit-guided refactoring plan

Target workspace: {{TARGET}}
Selected audit finding IDs: {{FINDING_IDS}}

Work in the target workspace. Read `.meowsky/AUDIT.md` and `.meowsky/MAP.md` first. Use the map for navigation, then inspect the current source, tests, configuration, and relevant documentation. Treat generated reports as leads, not as authority over current code. If either file is absent or an ID is absent, stop and explain what is missing.

For **only** the selected IDs:

1. Recheck each finding against current source. Record its status as supported, unresolved due to insufficient evidence, or invalidated by current code. Cite exact files and lines. Do not infer dead code or architectural relationships from missing references alone.
2. Identify callers, dependencies, affected tests, external behavior, and regression risks. Respect the project's own `AGENTS.md` and conventions. When working in Meowsky DevKit, also consult `{{DEVKIT_ROOT}}/conventions/architecture.md`, `{{DEVKIT_ROOT}}/conventions/filesystem.md`, and `{{DEVKIT_ROOT}}/conventions/code-style.md`. For other projects, apply those Meowsky principles where compatible with the project's established architecture.
3. Propose the smallest justified change for supported findings. Preserve application behavior and public commands unless the user authorizes a behavior change. Avoid structural migration for its own sake, unnecessary abstractions, and splitting cohesive files into tiny pieces.
4. Present a scoped plan listing the findings addressed, exact files to edit, intended changes, dependencies, expected benefit, regression risks, and relevant verification. Identify findings that should be left alone or need more evidence.

**Stop after the plan. Do not edit files, run a refactoring command, stage changes, or commit until the user explicitly approves the proposed edit batch.** Selecting finding IDs authorizes planning only. If the approved scope changes, seek a new approval before editing.

After an approved change, run relevant tests or checks, explain any checks that could not run, and report each selected ID as resolved, unresolved, or invalidated with source evidence. Do not mark a finding resolved merely because its report text disappeared. Do not start unrelated refactoring.

This checklist also works without Codex: a human can verify the IDs and source, write the plan, obtain approval, make the scoped edits, then run the same verification and status review.
