# Trust inventory

This repository wires third-party tooling directly into the agent harnesses and
the macOS build. This file names **every** third-party upstream, records the
capability each one is granted, and states why it is trusted. It exists so an
adopter can see — at a glance — how much power flows from where before applying
any of this to their own machine.

## The overarching stance: a consciously accepted single point of failure

Nine of the upstreams below are published by a **single** account,
[`kunchenguid`](https://github.com/kunchenguid). That includes the most
privileged tools in the stack (GitHub write, browser control, git push + PR)
**and** the agent distro that supervises the whole system (`firstmate`). This
concentration is a **deliberate, accepted** single point of failure. If that one
account were compromised or turned hostile, it could reach a large share of what
runs here.

The chosen mitigation is **tiered gating + disclosure, not de-concentration.**
There is **no vendoring** and no attempt to spread trust across more publishers.
Instead:

- Third-party source inputs and npm agent tools are **pinned** to an exact
  release/commit in [`flake.lock`](flake.lock) and
  [`agent-tools/package.json`](agent-tools/package.json). Rolling exceptions are
  called out below. A new upstream release does nothing until the pin is moved
  on purpose. (The first-party harnesses — the `claude-code`/`codex` casks and
  Pi — deliberately roll to latest instead; see the stance footnote below.)
- Neovim plugins are **disclosed but not pin-enforced**.
  [`home/.config/nvim/lazy-lock.json`](home/.config/nvim/lazy-lock.json) records
  the commit each plugin currently resolves to; lazy.nvim applies it only on an
  explicit `:Lazy restore`, so a fresh install clones the plugin's branch head
  and rewrites the lockfile to whatever it fetched. Treat those commits as
  reproducible *state* to review and restore from, not as a gate that holds a
  new upstream release back.
- The privileged and code-exec/workflow tiers (A and B below) sit behind a
  **cooldown + review gate**: `scripts/check-privileged-tool-releases.sh` only
  surfaces a newer stable release after a **seven-day cooldown**
  (`TOOL_UPDATE_COOLDOWN_DAYS`, default 7), so a freshly-published — possibly
  malicious — release is not ordinarily adopted on the day it drops. The only
  early-adoption path is the exact-commit Firstmate dependency-floor exception
  described below; package-only updates still wait.
- This document is the disclosure half: the trust is written down, tiered, and
  reviewable rather than implicit.

Among the **pin-enforced** tiers, `firstmate` is the one *third-party* upstream
that escapes the pinning discipline — it is **accept-as-rolling** (see its
section). That exception is the loudest single fact in this file. The directly
configured Neovim plugins sit outside those tiers entirely, under the separate
disclosed-but-not-pin-enforced stance described in the bullet above.

### First-party harnesses — deliberately rolling ⚠️

The agent harnesses this repo treats as **first-party** — the `claude-code` and
`codex` Homebrew casks and the Pi npm runtime
(`@earendil-works/pi-coding-agent`) — are **deliberately not pinned**. They roll
to the latest published release on every rebuild, with **no pin and no cooldown**
(decisions #34/#36). Pi is therefore **absent from the third-party inventory
below** — it carries no row; it joins the casks.

The asymmetry is intentional, not an oversight. These are first-party /
lab-grade vendors shipping frequent bug-fixes to daily-driver tools, so holding a
new release through a cooldown would mostly *delay the fixes the cooldown exists
to deliver* — for these upstreams rolling is the safer path. The pinned +
cooldown-gated discipline is reserved for the **third-party** `kunchenguid` +
`mattpocock` surface, whose larger blast radius and lower familiarity justify the
hold. (`firstmate` also rolls, but for the distinct reason in its own section.)

---

## Tier A — Privileged

Wired into **every** agent harness. These can act on GitHub, drive a real
browser, or read local provider auth. A compromised Tier A tool is the highest-
impact failure in the stack, so all three sit **behind the cooldown/review
gate** and are pinned to exact releases.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/gh-axi`](https://github.com/kunchenguid/gh-axi) | `gh-axi-v0.1.30` (flake input + npm `gh-axi@0.1.30`) | **GitHub write** — files/edits issues and PRs, merges, triggers workflows, manages Actions secrets/variables, raw API access, all under the local `gh` auth. | Pinned to an exact release; behind the cooldown/review gate. It is the sanctioned GitHub path for every agent, so its behavior is exercised constantly and any regression surfaces fast. |
| [`kunchenguid/chrome-devtools-axi`](https://github.com/kunchenguid/chrome-devtools-axi) | `chrome-devtools-axi-v0.1.29` (flake input + npm `chrome-devtools-axi@0.1.29`) | **Browser control** — navigates, clicks, fills forms, runs arbitrary JavaScript, and reads console/network in a real Chrome session. | Pinned to an exact release; behind the cooldown/review gate. Scoped to a driven browser session rather than the whole machine. |
| [`kunchenguid/quota-axi`](https://github.com/kunchenguid/quota-axi) | `quota-axi-v0.1.25` (flake input + npm `quota-axi@0.1.25`) | **Reads local provider auth sources** — inspects Claude/Codex/Cursor/Copilot/Grok/Kimi quota windows from on-disk auth. Read-only: no routing, no provider mutation. | Pinned to an exact release; behind the cooldown/review gate. The current early adoption is bound to its exact Firstmate floor evidence in `security/firstmate-floor-exceptions.json`. Documented as read-only, but it touches local credential material, which is why it is rated privileged rather than low-capability. |

## Tier B — Code-exec / workflow

Can execute code and move commits into the world (git push + PR). Pinned and
**behind the cooldown/review gate** — `scripts/check-privileged-tool-releases.sh`
is written specifically around these two.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/treehouse`](https://github.com/kunchenguid/treehouse) | `v2.1.1` (flake input) | **Code-exec / workflow** — provides disposable git worktrees that agents build and run code inside. | Pinned to an exact release; explicitly covered by the cooldown/review gate (`check_release treehouse …`). |
| [`kunchenguid/no-mistakes`](https://github.com/kunchenguid/no-mistakes) | `v1.48.0` (flake input, `flake = false`) | **git push + PR** — the validation pipeline that runs review/tests/lint and then pushes branches and opens pull requests. | Pinned to an exact release; explicitly covered by the cooldown/review gate (`check_release no-mistakes …`). It is the mandatory gate every change passes through, so its output is reviewed on every run. |

## Tier C — Low-capability

No GitHub write, no push, no browser, no credential access. Low blast radius, so
these are pinned but not placed behind the release cooldown.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/lavish-axi`](https://github.com/kunchenguid/lavish-axi) | `lavish-axi-v0.1.46` (flake input + npm `lavish-axi@0.1.46`) | Renders agent responses into reviewable HTML artifacts. | Pinned to an exact release; output-only presentation, no privileged capability. |
| [`kunchenguid/tasks-axi`](https://github.com/kunchenguid/tasks-axi) | `tasks-axi-v0.2.5` (flake input + npm `tasks-axi@0.2.5`) | Manages a local, hand-editable `backlog.md` task list. | Pinned to an exact release; operates on a local text backlog, no privileged capability. |
| [`kunchenguid/tap/baby-menu`](https://github.com/kunchenguid/homebrew-tap) | Homebrew cask (unversioned; `greedyCasks` converges to latest) | Native macOS menu-bar app installed via Homebrew. | From the same `kunchenguid` tap. Rated low-capability as an ordinary user-space menu-bar app. Note: as a `greedyCask` it is **not** pinned to a version and self-updates to Homebrew's latest — the concentration risk applies, but the capability is low. |

## firstmate — accept-as-rolling ⚠️

> **Among the pin-enforced third-party upstreams inventoried here, this is the
> one that is NOT pinned.** (The first-party harnesses roll too, but by the
> separate, deliberate decision described in the stance above; the directly
> configured Neovim plugins are disclosed rather than pin-enforced, per the
> stance above.)

[`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate) is an agent
**distro** — the supervisor that dispatches and manages the crewmate agents doing
work in this repo. Unlike every tool above, it is **not** a pinned flake input or
a pinned npm version:

- `scripts/post-switch.sh` **clones** `kunchenguid/firstmate` into `~/firstmate`
  **once**, then deliberately leaves that clone in place on every subsequent
  rebuild (it only verifies the origin remote; it never replaces the checkout).
- The clone contains **mutable configuration and state** and updates itself
  **under firstmate's own update workflow**, on firstmate's own cadence.

The practical consequence: **trust in firstmate is continuous, not a pinned
snapshot.** There is no `flake.lock` line that freezes which firstmate code runs
here. Whatever firstmate's own workflow pulls in becomes what supervises this
machine — and firstmate holds the most reach of anything in the stack, because it
orchestrates the agents that wield the Tier A and Tier B tools. An adopter must
accept that ongoing, rolling trust in the `kunchenguid` account explicitly; the
pinning + cooldown protections above **do not apply to firstmate.**

A rolling Firstmate commit can nevertheless declare a hard dependency floor
above a dotfiles pin. To avoid an availability deadlock without discarding the
cooldown generally,
[`security/firstmate-floor-exceptions.json`](security/firstmate-floor-exceptions.json)
may authorize exactly the lowest released version satisfying that floor. Each
record binds the previous and adopted pins, required floor, expected repository,
and full candidate commit SHA. `scripts/check-firstmate-floor-exceptions.sh`
reads the declaration from that immutable GitHub object, checks release
metadata, rejects unrelated or broader records, and rejects the record once the
ordinary cooldown has elapsed. A spent record is therefore retired, not kept:
each validation run reports the remaining hours and warns inside the last two
days, and `scripts/check-firstmate-floor-exceptions.sh --retire-expired` deletes
every record whose adopted release has completed the cooldown (see `README.md`).
`scripts/check-privileged-tool-releases.sh` therefore rejects every fresh
committed privileged pin unless that evidence is currently valid, including when
the fresh pin happens to equal npm `latest`.

This is an availability exception, not a safety attestation. It deliberately
reduces observation time for one dependency release and does not prove either
the Firstmate commit or package is benign. The cooldown retains independent
value against an npm-publisher/package-only compromise and for every use of the
tool outside Firstmate; integrity, signature, vulnerability, exact-pin, and
review gates remain unchanged.

Why it is nonetheless trusted: it is the intended supervisor for this exact
setup, its clone/update behavior is verified by `scripts/doctor.sh`, and its
state is kept separate from the tracked, pinned portable configuration.

---

## Other third-party upstreams (non-`kunchenguid`)

Neovim coverage in this table is scoped to the upstreams **this repository adds
itself** in `home/.config/nvim/lua/plugins/`. Plugins that LazyVim already ships
and that this repository only reconfigures there (for example `catppuccin/nvim`
and `render-markdown.nvim`), along with the rest of the LazyVim distribution's
plugin graph — everything else `lazy-lock.json` resolves — are inherited from
LazyVim and deliberately not inventoried here.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`mattpocock/skills`](https://github.com/mattpocock/skills) | flake input (locked to a commit in `flake.lock`; tracks the default branch — advanced only when `nix flake update matt-pocock-skills` is run) | Supplies agent **skills** (instructions/workflows) exposed from `~/.agents/skills` and linked into Claude and Pi. Skills are prompts/workflows, not independently privileged binaries, but they can *instruct* the privileged tools above. | Well-known author (Matt Pocock); locked in `flake.lock` so updates are explicit. Deprecated and in-progress skills are deliberately excluded. |
| [`OXY2DEV/markview.nvim`](https://github.com/OXY2DEV/markview.nvim) | resolves to `5d9fc2aa6dd1c2fbdc7a68bc79b300e9967b21ff` (recorded in `lazy-lock.json`, not enforced — see the Neovim bullet above) | Runs Lua inside Neovim to parse open Markdown buffers and draw preview extmarks. It has the same local-process access as any Neovim plugin, but no separate credentials or external service access. | Established upstream selected as the required rendering host for smart tables; its resolved commit is recorded so what is running stays reviewable and restorable. |
| [`gunasekar/markview-smart-tables.nvim`](https://github.com/gunasekar/markview-smart-tables.nvim) | resolves to `01134a5bf48f1b7abe27b26a6b89262685bb309f` (recorded in `lazy-lock.json`, not enforced — see the Neovim bullet above) | Runs Lua inside Neovim to replace Markview's table renderer with fitted, wrapped virtual text. It operates on open Markdown buffers and window layout only. | User-selected, narrowly scoped display extension, adopted as a trial while it is evaluated, with its required renderer hook covered by a health check. |

## Foundational Nix inputs (community infrastructure)

For completeness, the build also depends on standard, widely-used Nix community
inputs, all recorded in `flake.lock`: `nixpkgs` (`nixpkgs-26.05-darwin`),
[`nix-darwin`](https://github.com/nix-darwin/nix-darwin) (`nix-darwin-26.05`),
[`home-manager`](https://github.com/nix-community/home-manager)
(`release-26.05`), and [`nix-homebrew`](https://github.com/zhaofengli/nix-homebrew)
(plus Homebrew's `brew-src`). `brew-src` deliberately advances to the latest
upstream revision at the start of every rebuild so Homebrew can parse the latest
formula and cask DSL; the selected revision remains reproducible in
`flake.lock`. These are the ecosystem's foundational infrastructure —
high-trust, broadly reviewed, and outside the `kunchenguid` concentration that is
this document's concern — but they are named here so the trust inventory is
complete.

---

*Maintaining this file: when a third-party upstream is added, removed, or moved
between capability tiers, update the matching table here in the same change.
Version pins in the tables are illustrative of the pinning discipline — the
authoritative pins live in [`flake.lock`](flake.lock) and
[`agent-tools/package.json`](agent-tools/package.json).
[`home/.config/nvim/lazy-lock.json`](home/.config/nvim/lazy-lock.json) is not an
authoritative pin — it records the commits Neovim plugins currently resolve to.*
