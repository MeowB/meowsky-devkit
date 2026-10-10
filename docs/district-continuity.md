# District continuity

This is a file convention for `WORK_HOME` (`F:\meowsky` on this machine), not a state service. The devkit and workspace root remain separate: the devkit is its own Git repository, and the workspace root has no Git repository or parent `AGENTS.md`. Projects under `dev/` keep independent repositories; `bach/` and `launchpad/` may each become private repositories. Meowsky creates the three district directories but does not create records, initialize repositories, or configure remotes.

## Files you maintain

Each district may use this small structure:

```text
district/
  current.md
  sessions/YYYY-MM-DD-topic.md
  capsules/topic-YYYY-MM-DD.md
  references/                  # original PDFs and Word documents
  notes/                       # generated working notes, if useful
```

These files and subdirectories are optional; the launcher does not create them. You decide when current state and session records are created or updated. An agent may document them at your direction, while capsules are written by you. Keep personal records in their district, and use links to refer to work in another district or an independent project repository. Keep evidence at its source instead of copying it into every summary.

### Current state

`current.md` is the entry point for a fresh session. Keep it short and dated. Record current goals, real commitments and deadlines, blockers, next actions, and links to the relevant evidence or session records. Update it at useful checkpoints: after a decision, a changed commitment, a newly discovered blocker, or a completed work block. A brief checkpoint before ending a session limits loss if the conversation cannot be resumed later.

If a session ends unexpectedly, the next session reads `current.md` first, then checks the latest relevant record and source evidence to reconstruct anything after the last checkpoint. A chat transcript may help, but it is not the durable state. If `current.md` does not exist yet, the agent reports that fact and asks what you want to work on; it does not invent state.

### Dated sessions

A session record says what actually happened: actions taken, observations, decisions made by you, unresolved questions, and links to evidence. Date the filename and use a short topic so older records can be found when relevant. Do not load all session records at startup. `current.md` points to the few that matter now.

### Manual capsules

You create capsules yourself from accumulated records. A capsule preserves durable decisions, findings, and source links for a topic or completed phase; it does not replace the originals or become another live task list. The agent must not automatically create a capsule or merge, rewrite, or delete history.

The agent may suggest consolidation when retrieval has become cumbersome: several records repeat or supersede the same facts, a phase's decisions are scattered, or understanding the present requires reading substantial old material. The suggestion should briefly name the actual friction, the records involved, and what knowledge is worth preserving. File count alone is not a reason.

## Original references and communication

PDFs and Word documents in `references/` are original context sources. Agents may read them but must not modify, overwrite, rename, or delete them without your explicit request. Keep generated notes and working files outside `references/`, such as in `notes/` or a session record.

Only you communicate with people. An agent may research, prepare, draft, and document; it must never send messages, submit applications, publish posts, contact people, book meetings, or make commitments on your behalf. Approval of a draft does not authorize sending it.

The `bach` and `launchpad` launch prompts explicitly direct the agent to read the district's `current.md` first, if present, then retrieve relevant older records. They do not rely on a parent instruction file. Applicable instructions in an independent district or project repository still apply.
