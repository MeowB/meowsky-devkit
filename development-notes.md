# Development notes

## Four-file development handoff

Use this workflow for work that will span several iterations or sessions. Keep the four files together in the project's development notes, such as a root-level `development/` folder. Reserve `.meowsky/` for machine-specific files such as local snapshots, caches, and per-computer state.

| File | Purpose |
| --- | --- |
| `spec.md` | Define the outcome, scope, decisions, implementation order, and acceptance checks. |
| `goal.md` | Store a ready-to-paste `/goal` prompt on one physical line. Point it to the spec and current state. |
| `current.md` | Record what works today, the latest verified result, open decisions, and the exact next action. |
| `iterations.md` | Append what changed, what was verified, and what remains after each meaningful work block. |

Agree the spec before implementation. Use the goal sheet to start a fresh session. Read the current state first, then consult the spec and relevant iteration entries. Work in small, approved batches and verify each result. Update the current state and append to the iteration log after each verified batch or meaningful partial result. The next session checks that state against the workspace before resuming.

## DevKit documentation cleanup

Inventory the DevKit docs and identify who each document is for and what it owns. Flag overlap, stale guidance, and misplaced material. Propose a structure and a migration plan, including which links need updating, before reorganizing the docs.


## Startup Git status can be stale

A Bach launch reported `main`, a clean working tree, and `ahead 0, behind 0 vs origin/main`. Later in the same session, `git push` to GitHub rejected `main -> main (fetch first)` because the remote contained work absent locally.

The startup sync line is meant to help decide whether to pull. Check whether startup fetches the upstream branch before calculating ahead and behind. A cached tracking ref can be stale, and even a fresh check describes the remote only at the time it ran. The observed output alone does not establish which happened.

Expected behavior: show whether the comparison was freshly verified and when. If the remote cannot be checked, label the comparison as cached and make clear that pull status is unverified. A successful fetch should inform the status without merging or rebasing.
