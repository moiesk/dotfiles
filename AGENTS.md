## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues in this repo (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Trust inventory

`TRUST.md` at the repo root tiers the third-party upstream inventory by
capability and records each authoritative pin. The first-party harnesses — the
`claude-code`/`codex` casks and Pi (`@earendil-works/pi-coding-agent`) —
deliberately roll to latest (no pin, no cooldown) and are documented in TRUST.md's
stance, not the third-party inventory. Update it when an upstream is added,
removed, or moves tier; authoritative pins live in `flake.lock` and
`agent-tools/package.json`. Neovim plugins are disclosed in TRUST.md but not
pinned: `lazy.nvim`'s lockfile only applies on an explicit `:Lazy restore`, so
it is untracked.

### AXI tool pins live in three places

Each `*-axi` tool is pinned three times and all three must name the same
release: the `flake.nix` input supplies its **skill**, `agent-tools/package.json`
supplies its **binary**, and its `TRUST.md` row **discloses** both. Bump all
three, or agents get a skill documenting a different version than the command
they run, or a trust inventory that no longer describes what is installed.
`./scripts/validate.sh` enforces the agreement.

Dependabot proposes npm changes after its cooldown, and the read-only AXI pin
alignment workflow deliberately marks an npm-only proposal red. A maintainer
must first establish release eligibility from `TRUST.md` and, where applicable,
`scripts/check-privileged-tool-releases.sh`; the helper does not make or bypass
that policy decision. Then run `./scripts/update-agent-tool-pin.sh <tool>
<version>`, review its coordinated pin diff, ship a replacement PR, and close
the incomplete Dependabot PR as superseded. A captain-approved rolling-Firstmate
floor exception uses the preflight and `--firstmate-commit` workflow in
`README.md`; no other early adoption is allowed. Such an exception is valid only
inside the cooldown it shortens: once the adopted release completes the
cooldown, `./scripts/check-firstmate-floor-exceptions.sh --retire-expired`
deletes the spent record and the removal must be shipped, or the daily
privileged-tool run fails on stale evidence. The helper performs only a
targeted Nix update (never a blanket `nix flake update`) and full validation.

Pins take effect only after the captain runs `./rebuild.sh`; agents must not run
it.

A bump must never require editing a test fixture. Fixtures derive their synthetic
versions from the live pins at run time and fail with a message naming themselves
when that derivation stops producing the scenario under test — so a fixture
failure after a bump means the fixture, never the checker (issue #61).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
