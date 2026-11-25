# Development workflow

Keep quick ideas in [development-notes.md](../development-notes.md). When an idea is selected for work that spans several iterations or sessions, give the phase a stable folder under `development/phases/`, such as `001-startup-git-status/`.

## Four-file handoff

| File | Purpose |
| --- | --- |
| `spec.md` | Define the outcome, scope, decisions, implementation order, and acceptance checks. |
| `goal.md` | Keep a ready-to-paste `/goal` prompt on one physical line. Point it to the phase spec and current state. |
| `current.md` | Record what works, the latest verified result, open decisions, and the next action. |
| `iterations.md` | Append what changed, what was verified, and what remains after each meaningful work block. |

Agree on the spec before implementation. In a new session, use the goal prompt, read the current state first, and check it against the checkout. Consult the spec and relevant iteration entries before resuming. Work in small, approved batches. Update the current state and append to the iteration log after each verified batch or meaningful partial result.

Track phase folders in Git and keep them after completion. Record implementation commit IDs and verification results in the iteration log so later fixes can trace the behavior to its original decisions and checks. Use `.meowsky/` for disposable local inputs and outputs such as screenshots, logs, and scratch scripts.

## Current backlog handoff

- [Specification and acceptance checks](spec.md)
- [Ready-to-paste goal](goal.md)
- [Current state and next action](current.md)
- [Iteration log](iterations.md)
