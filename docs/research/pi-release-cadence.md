# Research: Pi (`@earendil-works/pi-coding-agent`) release cadence and fix-heaviness

**Ticket:** [#37](https://github.com/moiesk/dotfiles/issues/37) (feeds decision [#36](https://github.com/moiesk/dotfiles/issues/36); context [#34](https://github.com/moiesk/dotfiles/issues/34))
**Date:** 2026-07-24
**Current pin:** `@earendil-works/pi-coding-agent@0.81.1` (exact, in `agent-tools/package.json`; recorded in `TRUST.md` Tier D)

## Question

Does Pi behave like the first-party harnesses (claude-code / codex) — frequent, fix-heavy
releases where waiting is the riskier path — or more like a stable third-party tool where an
exact pin costs little? Needed to decide whether Pi should roll-to-latest or keep its exact pin.

## Sources (primary)

- npm registry publish timestamps: `npm view @earendil-works/pi-coding-agent time --json`
- npm registry version list: `npm view @earendil-works/pi-coding-agent versions --json`
- npm registry metadata: `npm view @earendil-works/pi-coding-agent maintainers author repository license _npmUser dist.fileCount`
- GitHub releases: `gh release list -R earendil-works/pi`
- GitHub repo metadata: `gh repo view earendil-works/pi --json ...`
- Upstream CHANGELOG: `packages/coding-agent/CHANGELOG.md` in `earendil-works/pi`
  (https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/CHANGELOG.md)

All figures below are pulled directly from the npm registry and the upstream repo; no secondary write-ups.

## 1. Release cadence

The package's entire published history is **36 versions from 0.74.0 (2026-05-07) to 0.82.0
(2026-07-24)** — a span of ~78 days (~2.6 months). The npm `created` date is 2026-05-07, so
this window is essentially the package's full life under its current scope.

Overall rate: **36 releases / 2.6 months ≈ ~14 releases per month.**

By calendar month:

| Month | Releases | Notes |
|---|---|---|
| May 2026 (from 05-07) | 12 | 0.74.0, .1, 0.75.0–.5, 0.74.2, 0.76.0, 0.77.0, 0.78.0 |
| June 2026 | 15 | 0.78.1, 0.79.0–.10, 0.80.1, .2, .3 |
| July 2026 (through 07-24) | 9 | 0.80.5–.10, 0.81.0, .1, 0.82.0 (partial month, ~11–12/mo pace) |

**Bottom line on cadence: roughly 12–15 releases/month (~14 avg).** Frequently multiple
releases in a single day (e.g. three 0.80.x on 2026-07-16; 0.75.1/.2/.3 all on 2026-05-18).
This is a very high, harness-style cadence — on par with or exceeding a daily-driver tool like
claude-code / codex.

## 2. Patch vs minor vs major (fix-heaviness)

Semver bump breakdown across the 35 version-increments (baseline 0.74.0 excluded):

| Bump type | Count | Share |
|---|---|---|
| Major (x.0.0) | 0 | 0% |
| Minor (0.MINOR.0) | 8 | ~23% |
| Patch (0.x.PATCH) | 27 | ~77% |

Minor bumps: 0.75.0, 0.76.0, 0.77.0, 0.78.0, 0.79.0, 0.80.x, 0.81.0, 0.82.0. Everything else is a patch.

The changelog confirms fix-heaviness qualitatively and strongly: **every release — including the
minor bumps — is dominated by a large "Fixed" section.** Examples pulled from the upstream CHANGELOG:

- **0.82.0** (a minor): 3 New Features / ~6 Added, but **~18 "Fixed" entries** (DNS-retry, cache
  breakpoints, Codex WebSocket retries, TUI log paths, a `protobufjs` security bump for
  GHSA-j3f2-48v5-ccww, etc.).
- **0.81.0** (a minor): a handful of features, but **~20 "Fixed" entries**.
- **0.80.10 / 0.80.9** (patches): almost entirely "Fixed" (provider/thinking-level/pricing fixes).

So even feature-carrying minors ship mostly as fix batches. Reliability/compat fixes to
providers, TUI, retries, and sessions are the bulk of the churn.

**Caveat (semver):** Pi is still pre-1.0 (0.x). Under semver, a 0.MINOR bump may legitimately
carry a breaking change, so the 8 minors are not guaranteed non-breaking — "minor" here means
"feature release," not "safe upgrade." Pin/roll policy should account for the possibility that any
0.x→0.(x+1) carries an incompatibility (the changelog does note extension-API adjustments, e.g.
"Restored the default stream fallback for extensions using the pre-0.81 agent-core API").

Minor detail: GitHub tags 0.80.0 and 0.80.4 exist as releases but were **not** published to npm
(npm skips straight to 0.80.1 and 0.80.5), indicating quickly-superseded builds — npm is the
authoritative distribution surface for the pin.

## 3. Vendor size / reputation (pin-vs-roll trust signal)

- **Repo:** `earendil-works/pi` — a monorepo ("AI agent toolkit: unified LLM API, agent loop, TUI,
  coding agent CLI"); the npm package is `packages/coding-agent`. Created 2025-08-09. **MIT
  licensed. ~77,000 GitHub stars** — a large, well-established, actively-developed project.
- **Author / maintainers (npm):**
  - `badlogic` — **Mario Zechner** (npm `author`), creator of libGDX; long-established OSS author.
  - `mitsuhiko` — **Armin Ronacher**, creator of Flask / Jinja / and Sentry co-founder.
  - `rwachtler`.
  These are high-reputation, long-track-record maintainers.
- **Publishing integrity:** npm `_npmUser` is `GitHub Actions <npm-oidc-no-reply@github.com>` —
  releases are published via **GitHub Actions OIDC trusted publishing**, not a personal token.
  0.81.1+ also ship **deterministic, checksummed source archives** on GitHub releases for
  rebuild verification (per the 0.81.1 changelog). Both are positive supply-chain signals.
- Active external contribution: many changelog entries credit outside contributors' PRs.

Reputation is high on every axis (author track record, project scale, trusted-publisher pipeline).
The residual supply-chain risk is not "unknown/untrusted vendor" but rather "high release velocity +
pre-1.0 + full local agent capability," which is a change-surface/blast-radius concern, not a
vendor-trust concern.

## Bottom-line read (for decision #36)

**Pi behaves like claude-code / codex, not like a stable pinned tool.** It ships ~14 releases/month,
~77% of them patches, and the changelog is overwhelmingly bug-fix driven even in minor bumps —
exactly the "frequent fix-heavy daily-driver harness where waiting is the riskier path" profile that
justified rolling the first-party casks to latest in #34/#36. The vendor is reputable and publishes
through a trusted-publisher pipeline, so the trust cost of rolling is low.

The one asymmetry vs the claude/codex casks: Pi is **pre-1.0**, so 0.MINOR bumps can technically be
breaking, and it is a **full local agent runtime** (Tier D capability). If Pi rolls-to-latest, the
recommendation is to keep it behind the same npm-release **cooldown / review gate** the other Tier-A/D
tools use (see `TRUST.md` and #31) rather than tracking `latest` unconditionally — capturing the
"don't wait on fixes" benefit while bounding the pre-1.0 breakage / blast-radius risk.
