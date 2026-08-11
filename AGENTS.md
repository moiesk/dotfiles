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

### AXI tool pins live in three places

Each `*-axi` tool is pinned three times and all three must name the same
release: the `flake.nix` input supplies its **skill**, `agent-tools/package.json`
supplies its **binary**, and its `TRUST.md` row **discloses** both. Bump all
three, or agents get a skill documenting a different version than the command
they run, or a trust inventory that no longer describes what is installed.
`./scripts/validate.sh` enforces the agreement.

To advance a pin: edit `flake.nix`, run a targeted `nix flake update <input> …`
(never a blanket `nix flake update` — it drags `nixpkgs` and friends along), edit
`agent-tools/package.json`, regenerate with `npm install --package-lock-only` in
`agent-tools/`, refresh the matching `TRUST.md` row, then run
`./scripts/validate.sh`.

Which tools may be bumped when is a `TRUST.md` question, not a preference: look
up the tool's tier there first. Tier A sits behind a release cooldown enforced by
`scripts/check-privileged-tool-releases.sh`; Tier C does not. Pins take effect
only after the captain runs `./rebuild.sh`; agents must not run it.

A bump must never require editing a test fixture. Fixtures derive their synthetic
versions from the live pins at run time and fail with a message naming themselves
when that derivation stops producing the scenario under test — so a fixture
failure after a bump means the fixture, never the checker (issue #61).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
