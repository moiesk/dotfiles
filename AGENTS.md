## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues in this repo (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Trust inventory

`TRUST.md` at the repo root tiers every third-party upstream (nine `kunchenguid`
sources + `mattpocock/skills`) by capability. The first-party harnesses — the
`claude-code`/`codex` casks and Pi (`@earendil-works/pi-coding-agent`) —
deliberately roll to latest (no pin, no cooldown) and are documented in TRUST.md's
stance, not the third-party inventory. Update it when an upstream is added,
removed, or moves tier; authoritative pins live in `flake.lock` and
`agent-tools/package.json`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
