# Trust inventory

This repository wires third-party tooling directly into the agent harnesses and
the macOS build. This file inventories the direct upstream trust decisions the
repository makes: agent tools and support libraries, deliberately added
editor/plugin upstreams, and foundational build inputs. It records the
capability each one is granted and states why it is trusted, so an adopter can
see — at a glance — how much power flows from where before applying any of this
to their own machine. Transitive package-manager dependencies and inherited
plugin graphs are represented by their lockfiles or upstream manifests rather
than repeated row by row; explicitly scoped exceptions are called out below.

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

- Third-party source inputs and npm agent tools/support packages are **pinned**
  to an exact release/commit in [`flake.lock`](flake.lock),
  [`agent-tools/package.json`](agent-tools/package.json), or the separate
  [`home/.config/opencode/package.json`](home/.config/opencode/package.json)
  manifest. Rolling exceptions are called out below. A new upstream release
  does nothing until the matching pin is moved on purpose. (The first-party
  harnesses — the `claude-code`/`codex` casks and Pi — deliberately roll to
  latest instead; see the stance footnote below.)
  <!-- markdownlint-disable-next-line MD033 -->
- <a id="nvim-stance"></a>Neovim plugins are **disclosed but not pinned**.
  This bullet is the single authoritative statement of that stance; every other
  mention in this file points back here. lazy.nvim applies its `lazy-lock.json`
  only on an explicit `:Lazy restore`, so a fresh install clones the plugin's
  branch head and rewrites the lockfile to whatever it fetched. It never holds
  a release back, so this repository does not track it (see `.gitignore`).
  Neovim plugins are disclosed by upstream and purpose instead, under
  [Neovim plugins](#neovim-plugins).
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
section). That exception is the loudest single fact in this file. The Neovim
upstreams sit outside these tiers entirely, under the
[disclosed-but-not-pinned stance](#nvim-stance).

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
to deliver* — for these upstreams rolling is the safer path. The rolling
exception is narrow: the `kunchenguid` tools retain their capability-tiered
pin/cooldown treatment, Matt Pocock's skills stay pinned, and OpenCode's official
plugin-authoring package stays exact-pinned under the Tier C posture below.
(`firstmate` also rolls, but for the distinct reason in its own section.)

---

## Tier A — Privileged

Wired into **every** agent harness. These can act on GitHub, drive a real
browser, or read local provider auth. A compromised Tier A tool is the highest-
impact failure in the stack, so all three sit **behind the cooldown/review
gate** and are pinned to exact releases.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/gh-axi`](https://github.com/kunchenguid/gh-axi) | `gh-axi-v0.1.33` (flake input + npm `gh-axi@0.1.33`) | **GitHub write** — files/edits issues and PRs, merges, triggers workflows, manages Actions secrets/variables, raw API access, all under the local `gh` auth. Since 0.1.31 its `stack` command also reaches the **local Git work tree**: it is a non-interactive adapter over the separate [`github/gh-stack`](https://github.com/github/gh-stack) `gh` extension, which restacks and rebases branches in the current working directory. gh-axi ships no stack engine of its own and the command is inert unless that extension is installed, which this configuration does not install. | Pinned to an exact release; behind the cooldown/review gate. It is the sanctioned GitHub path for every agent, so its behavior is exercised constantly and any regression surfaces fast. The delegated stack extension is first-party GitHub, and the Git mutation it performs stays inside the repository the agent is already working in. |
| [`kunchenguid/chrome-devtools-axi`](https://github.com/kunchenguid/chrome-devtools-axi) | `chrome-devtools-axi-v0.1.29` (flake input + npm `chrome-devtools-axi@0.1.29`) | **Browser control** — navigates, clicks, fills forms, runs arbitrary JavaScript, and reads console/network in a real Chrome session. | Pinned to an exact release; behind the cooldown/review gate. Scoped to a driven browser session rather than the whole machine. |
| [`kunchenguid/quota-axi`](https://github.com/kunchenguid/quota-axi) | `quota-axi-v0.1.30` (flake input + npm `quota-axi@0.1.30`) | **Reads local provider credentials and queries provider quota APIs** — reports Claude/Codex/Cursor/Copilot/Grok/Kimi/Z.AI/Antigravity quota windows. For most providers it reads the credential from on-disk auth and calls that provider's own quota endpoint with it (`api.anthropic.com`, `api2.cursor.sh`, `api.github.com`, `api.kimi.com`, …). Antigravity, added in 0.1.30, has no on-disk quota file, so it is instead **discovered from the running process table**: quota-axi runs `ps` to find the local Antigravity process and read its `--extension_server_port` and `--extension_server_csrf_token` arguments, runs `lsof` to confirm that port is listening, then calls that endpoint on `127.0.0.1` with the token it found. Read-only in every case: it reports quota and performs no routing and no provider mutation. | Pinned to an exact release; behind the cooldown/review gate. The 0.1.29 pin was adopted early under a Firstmate dependency-floor exception; that release has since completed the ordinary cooldown, so the record was retired and no exception is in force for it. Documented as read-only, but it touches local credential material, which is why it is rated privileged rather than low-capability. The 0.1.30 Antigravity path widens that reach from on-disk auth to process enumeration and a loopback call carrying a token lifted from another process's command line; it was reviewed and approved on adoption as equivalent in kind to the on-disk-credential reads the row already covers, and the harvested token is sent only to `127.0.0.1`, never off the machine. The tier is unchanged. |

## Tier B — Code-exec / workflow

Can execute code and move commits into the world (git push + PR). Pinned and
**behind the cooldown/review gate** — `scripts/check-privileged-tool-releases.sh`
is written specifically around these two.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/treehouse`](https://github.com/kunchenguid/treehouse) | `v2.1.1` (flake input) | **Code-exec / workflow** — provides disposable git worktrees that agents build and run code inside. | Pinned to an exact release; explicitly covered by the cooldown/review gate (`check_release treehouse …`). The newer `v2.3.0` is held out of adoption in `security/blocked-tool-releases.json` because its released flake omits Python and fails the darwin-rebuild build gate; the pin stays at the last reviewed buildable release until an exact fixed release clears cooldown. |
| [`kunchenguid/no-mistakes`](https://github.com/kunchenguid/no-mistakes) | `v1.48.0` (flake input, `flake = false`) | **git push + PR** — the validation pipeline that runs review/tests/lint and then pushes branches and opens pull requests. | Pinned to an exact release; explicitly covered by the cooldown/review gate (`check_release no-mistakes …`). It is the mandatory gate every change passes through, so its output is reviewed on every run. |

## Tier C — Low-capability

No direct GitHub write, push, browser control, credential access, or arbitrary
workflow execution in their configured use. Their lower blast radius does not
require the fail-closed privileged release checker. A narrower update delay may
still be retained for a particular manifest, as noted below.

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`kunchenguid/lavish-axi`](https://github.com/kunchenguid/lavish-axi) | `lavish-axi-v0.1.59` (flake input + npm `lavish-axi@0.1.59`) | Renders agent responses into reviewable HTML artifacts. | Pinned to an exact release; output-only presentation, no privileged capability. |
| [`kunchenguid/tasks-axi`](https://github.com/kunchenguid/tasks-axi) | `tasks-axi-v0.2.5` (flake input + npm `tasks-axi@0.2.5`) | Manages a local, hand-editable `backlog.md` task list. | Pinned to an exact release; operates on a local text backlog, no privileged capability. |
| [`kunchenguid/tap/baby-menu`](https://github.com/kunchenguid/homebrew-tap) | Homebrew cask (unversioned; `greedyCasks` converges to latest) | Native macOS menu-bar app installed via Homebrew. | From the same `kunchenguid` tap. Rated low-capability as an ordinary user-space menu-bar app. Note: as a `greedyCask` it is **not** pinned to a version and self-updates to Homebrew's latest — the concentration risk applies, but the capability is low. |
| [`anomalyco/opencode` (`@opencode-ai/plugin`)](https://github.com/anomalyco/opencode/tree/v1.18.19/packages/plugin) | npm `@opencode-ai/plugin@1.18.19` (exact, in [`home/.config/opencode/package.json`](home/.config/opencode/package.json); locked beside it) | **OpenCode plugin-authoring support.** In this checkout it is installed but not loaded: there is no tracked OpenCode plugin/custom-tool source or import, and its public runtime entry points are schema/identity and TUI helpers while the shell, SDK, auth, permission, and tool-hook surfaces are TypeScript interfaces for plugin authors. The separate package pin therefore has no direct privileged reach today. | The official package is published from the same monorepo and release train as the OpenCode harness. The repository's `npm ci` path disables lifecycle scripts and verifies lock integrity, vulnerabilities, and registry signatures. Tier C reflects its effective configured use; adding a runtime import or local plugin must re-evaluate the tier. The manifest retains its existing seven-day Dependabot delay for routine update proposals, but is not subject to the privileged release checker. |

### OpenCode package boundary

OpenCode's [official plugin documentation](https://github.com/anomalyco/opencode/blob/v1.18.19/packages/web/src/content/docs/plugins.mdx)
and [config bootstrap](https://github.com/anomalyco/opencode/blob/v1.18.19/packages/opencode/src/config/config.ts)
explain why the package is present: OpenCode makes the official authoring API
available in each config directory so local plugins and custom tools can import
its types and `tool()` helper. The package is not itself a configured plugin.
At the current pin, its [runtime root](https://github.com/anomalyco/opencode/blob/v1.18.19/packages/plugin/src/index.ts)
only re-exports the small `tool()` helper; the broad hook context describes what
*plugin code* can receive from the OpenCode host.

That distinction sets the present boundary. A future local plugin or custom tool
would execute as the OpenCode user and can be given Bun shell execution, the
OpenCode SDK client, provider auth callbacks, and permission/tool hooks. Adding
such code — or importing this package at runtime — therefore changes the granted
capability and requires reclassification. Until then, the committed OpenCode
directory contains only the npm manifests and `.npmrc`, whose `ignore-scripts`
setting also prevents the repository's `npm ci` from creating an install-time
execution path.

Both halves of that boundary are mechanically enforced by
[`scripts/check-opencode-trust.sh`](scripts/check-opencode-trust.sh), which
`./scripts/validate.sh` and the pull-request
[pin-alignment workflow](.github/workflows/agent-tool-pins.yml) both run: the
row above and the release permalinks cited in this section must name the
version that
[`home/.config/opencode/package.json`](home/.config/opencode/package.json)
installs, and while that row sits under Tier C the committed OpenCode directory
must hold nothing but `package.json`, `package-lock.json`, and `.npmrc`. A
Dependabot bump or a newly tracked plugin/tool file therefore turns the pull
request red until the inventory is brought back in line, and the checker itself
fails if that workflow ever stops covering these paths.

Tier C does not require extending
[`scripts/check-privileged-tool-releases.sh`](scripts/check-privileged-tool-releases.sh),
which enforces the stronger fail-closed gate only for Tiers A and B. No existing
control is removed: the separate Dependabot entry for this manifest still delays
routine proposals by seven days, security updates still bypass that delay, and
the exact pin, lockfile, audit, signature, and PR review controls remain.

## firstmate — accept-as-rolling ⚠️

> **Among the pin-enforced third-party upstreams inventoried here, this is the
> one that is NOT pinned.** (The first-party harnesses roll too, but by the
> separate, deliberate decision described in the stance above; the Neovim
> upstreams are disclosed rather than pin-enforced, per the
> [stance bullet](#nvim-stance).)

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

| Upstream | Pinned at | Capability granted | Why it is trusted |
|---|---|---|---|
| [`mattpocock/skills`](https://github.com/mattpocock/skills) | flake input (locked to a commit in `flake.lock`; tracks the default branch — advanced only when `nix flake update matt-pocock-skills` is run) | Supplies agent **skills** (instructions/workflows) exposed from `~/.agents/skills` and linked into Claude and Pi. Skills are prompts/workflows, not independently privileged binaries, but they can *instruct* the privileged tools above. | Well-known author (Matt Pocock); locked in `flake.lock` so updates are explicit. Deprecated and in-progress skills are deliberately excluded. |

## Neovim plugins

This section covers the Neovim upstreams **this repository adds itself**: the
plugin manager and base distribution bootstrapped in
[`home/.config/nvim/lua/config/lazy.lua`](home/.config/nvim/lua/config/lazy.lua),
plus the plugins declared under `home/.config/nvim/lua/plugins/`. LazyVim's own
downstream plugin graph is inherited rather than chosen here and is deliberately
not inventoried individually — that includes plugins LazyVim already ships and
that this repository only reconfigures under `lua/plugins/`, for example
`catppuccin/nvim` and `render-markdown.nvim`.

They are listed by upstream and purpose rather than by revision, because nothing
pins them — see the [disclosed-but-not-pinned stance](#nvim-stance). Naming them
here keeps the explicitly added editor/plugin portion of the direct-upstream
inventory complete.

| Upstream | Where it is declared | Capability granted | Why it is trusted |
|---|---|---|---|
| [`folke/lazy.nvim`](https://github.com/folke/lazy.nvim) | `lua/config/lazy.lua:4` — git-cloned from `--branch=stable` on first launch, then self-managed. | **Plugin manager** — resolves, clones, updates and loads every other Neovim plugin from GitHub, and runs their build steps. The broadest reach of anything in this section: everything below arrives through it. | Widely used, actively maintained plugin manager by folke, who also authors LazyVim. Tracks the `stable` branch rather than the default branch. |
| [`LazyVim/LazyVim`](https://github.com/LazyVim/LazyVim) | `lua/config/lazy.lua:20`, imported as the base spec (`{ "LazyVim/LazyVim", import = "lazyvim.plugins" }`). | **Base distribution** — supplies the options, keymaps, autocmds and plugin graph this configuration builds on, and therefore decides which further upstreams get installed. | Same author as lazy.nvim and the mainstream Neovim starter distribution. Adopted wholesale and deliberately: its inherited plugin graph is the reason the section above scopes individual inventory to what this repository adds on top. |
| [`OXY2DEV/markview.nvim`](https://github.com/OXY2DEV/markview.nvim) | [`home/.config/nvim/lua/plugins/markview-smart-tables.lua`](home/.config/nvim/lua/plugins/markview-smart-tables.lua), as a dependency. It is the Markdown previewer, replacing `render-markdown.nvim`. | Runs Lua inside Neovim to parse open Markdown buffers and draw preview extmarks. It has the same local-process access as any Neovim plugin, but no separate credentials or external service access. | Established, widely used Neovim Markdown renderer, and the required rendering host for smart tables. |
| [`gunasekar/markview-smart-tables.nvim`](https://github.com/gunasekar/markview-smart-tables.nvim) | The same file, as the top-level spec. It is wired into Markview's `renderers.markdown_table` hook, without which it does nothing. | Runs Lua inside Neovim to replace Markview's table renderer with fitted, wrapped virtual text. It operates on open Markdown buffers and window layout only. | Small, narrowly scoped display extension adopted as a trial for one behavior: fitting oversized tables to the window. Its required renderer hook is verifiable with `:checkhealth markview-smart-tables`. |

## Foundational Nix inputs (community infrastructure)

For completeness, the build also depends on standard, widely-used Nix community
inputs, all recorded in `flake.lock`: `nixpkgs` (`nixpkgs-26.05-darwin`),
[`nix-darwin`](https://github.com/nix-darwin/nix-darwin) (`nix-darwin-26.05`),
[`home-manager`](https://github.com/nix-community/home-manager)
(`release-26.05`), and [`nix-homebrew`](https://github.com/zhaofengli/nix-homebrew)
(plus Homebrew's `brew-src`). `brew-src` deliberately advances to the latest
upstream revision at the start of every rebuild so Homebrew can parse the latest
formula and cask DSL; the selected revision remains reproducible in
`flake.lock`. These are the ecosystem's foundational infrastructure — high-trust,
broadly reviewed, and outside the `kunchenguid` concentration that is this
document's concern — but they are named here so those high-level build trust
decisions are not implicit.

---

*Maintaining this file: when a direct upstream in this inventory's scope is
added, removed, or moved between capability tiers, update the matching table
here in the same change. Version pins in the tables are illustrative of the
pinning discipline — the authoritative pins live in [`flake.lock`](flake.lock),
[`agent-tools/package.json`](agent-tools/package.json), and
[`home/.config/opencode/package.json`](home/.config/opencode/package.json).
Neovim upstreams have no pin; see the [stance bullet](#nvim-stance).*
