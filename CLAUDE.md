## Verification

**Prove a change with `pwsh -File tools/build.ps1`, or, for logic alone, `godot_console --headless --path . -- --check`
read by its output.** The check exits 0 even when an `assert` fails, printing only `SCRIPT ERROR`, so judge by that
line and by `CHECK flow ok`, as `build.ps1` does. A script that fails to compile hangs Godot instead of exiting
(2026-10-25), so run the check under a timeout.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
