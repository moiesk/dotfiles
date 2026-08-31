# dotfiles

My repeatable Apple Silicon Mac setup for agentic development. It is inspired
by [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), but the
configuration and macOS preferences here are derived from my own machine.

One repository manages:

- Codex, Claude Code, Pi, and OpenCode with shared tools and portable settings
- Ghostty, Herdr, zsh, Starship, fzf, mise, and Neovim/LazyVim
- Portable CLI tools with Nix and native macOS apps with Homebrew
- Matt Pocock's agent skills plus Treehouse, Firstmate, no-mistakes, and Lavish
- Dock auto-hide, automatic light/dark appearance, and Finder tabs

## Fresh Mac

Prerequisites:

- Apple Silicon Mac
- macOS administrator access
- Git and internet access

Clone and bootstrap:

```sh
git clone https://github.com/moiesk/dotfiles.git
cd dotfiles
./bootstrap.sh
```

`bootstrap.sh`:

1. Installs Determinate Nix if needed.
2. Links the checkout to `~/.dotfiles`.
3. Checks the configured username and offers to update it.
4. Evaluates the locked flake without applying it.
5. Shows any Homebrew items that strict cleanup would remove.
6. Applies the first nix-darwin/Home Manager build.
7. Installs user-scoped agent tools and runs the doctor.

Open a new terminal after it finishes. Applications still require their normal
interactive sign-ins; credentials and sessions are deliberately not stored
here.

## Homebrew cleanup warning

`homebrew.onActivation.cleanup = "zap"` is intentional. On every rebuild,
Homebrew removes formulae, casks, and taps that are not declared in
`homebrew.nix`. For casks, zap can also remove associated application files.

The first bootstrap is guarded: it prints the undeclared delta and requires the
exact confirmation phrase `WIPE UNDECLARED`. Stop there and edit
`homebrew.nix` if the preview contains anything you want to keep.

`./rebuild.sh` runs the same preview before every switch and stops for the
`WIPE UNDECLARED` confirmation when it finds undeclared items. Add new packages
to `homebrew.nix` before rebuilding. Pass `--yes` (or set `REBUILD_YES=1`) to
skip the preview once the declared state is already correct; without an opt-out
and without an interactive terminal the rebuild refuses to zap rather than doing
it silently.

Rebuilds first advance Homebrew's own source revision in `flake.lock`, then
update package metadata and greedily upgrade every declared cask. Updating the
Homebrew interpreter first prevents new formula or cask DSL methods from
breaking activation before an upgrade can run. The newly selected revision is
still recorded in the lock file, so the applied system remains reproducible and
the lock-file change should be committed with the next project change. This
intentionally favors the latest available release, including for self-updating
or unversioned apps such as agent harnesses. The final doctor check fails if any
Homebrew formula or cask is still outdated. The first-party
agent harnesses roll to latest by the same deliberate policy — no pin, no
cooldown: the `claude-code`/`codex` casks upgrade greedily, and Pi
(`@earendil-works/pi-coding-agent`) is installed from its latest npm release on
every rebuild by `scripts/post-switch.sh`, with the doctor confirming it is
present. The third-party `kunchenguid` and `mattpocock` upstreams stay pinned
and gated instead (see `TRUST.md`); the asymmetry is intentional.

## Daily use

Edit the repository in place, then apply:

```sh
./rebuild.sh
```

Validate without changing the machine:

```sh
./scripts/validate.sh
nix flake check --no-build
```

Check the live result:

```sh
./scripts/doctor.sh
```

## Package ownership

Portable command-line tools are declared in `home.packages` and pinned by the
flake lock. Homebrew is reserved for macOS app bundles, fonts, native window
management, Herdr, ScummVM, and the Borders tap. The Homebrew list contains only
direct installs; dependencies are allowed to converge automatically.

Remove tap-backed packages in two rebuilds: first remove the formula or cask
while leaving its tap declared, then remove the now-unused tap in the following
rebuild. Homebrew cannot uninstall a package after its defining tap is gone.

## mise runtimes

Home Manager enables mise, pins Node 24.20.0 and Ruby 4.0.6, and activates mise
in new Zsh sessions. Runtime installation is serialized and retried once because
parallel first-run GPG key imports can race. Ruby uses mise's precompiled Apple
Silicon binaries, falling back to a source build when no binary is available.
Homebrew provides the native `vips` library used by Rails applications with the
`ruby-vips` gem.
After rebuilding, open a new shell and run:

```sh
mise current
mise exec -- node --version
mise exec -- ruby --version
./scripts/doctor.sh
```

Advance the other pinned Nix inputs by naming each one. A blanket `nix flake
update` also drags `nixpkgs`, `nix-darwin`, and `home-manager` along, which
turns a single reviewable pin bump into an untargeted framework upgrade
(Homebrew itself advances automatically on every `./rebuild.sh`):

```sh
nix flake update treehouse no-mistakes   # name only the inputs you intend to move
./scripts/validate.sh
./rebuild.sh
```

For the `*-axi` tools, the flake input is only one of three pins that must move
together; see `AGENTS.md` for the full bump procedure.

## Repository map

| Path | Purpose |
| --- | --- |
| `flake.nix` / `flake.lock` | Pinned nix-darwin, Home Manager, nix-homebrew, and nixpkgs inputs |
| `configuration.nix` | Platform, user, and the three requested macOS behaviors |
| `homebrew.nix` | Complete reviewed Homebrew inventory and strict convergence policy |
| `home.nix` | Shell, Git, environment variables, and out-of-store symlinks |
| `AGENTS.md` / `CLAUDE.md` | Project-local instructions (`CLAUDE.md` links to `AGENTS.md`) |
| `home/.*` | Portable app configurations copied from the working Mac |
| `bootstrap.sh` | One-time fresh-machine setup |
| `rebuild.sh` | Normal apply workflow |
| `scripts/homebrew-preflight.sh` | Destructive cleanup preview for bootstrap and rebuild |
| `scripts/update-homebrew.sh` | Targeted Homebrew source update used by bootstrap and rebuild |
| `scripts/post-switch.sh` | Pinned agents/tools plus mise runtime installation |
| `scripts/nix-gc.sh` | Interval-gated Nix garbage collection after a successful switch |
| `scripts/doctor.sh` | Read-only outcome checks |
| `scripts/check-secrets.sh` | Repository credential guard |

## Agent instructions

The root `AGENTS.md` and its `CLAUDE.md` symlink contain instructions for this
project only. Home Manager deliberately does not install them into any agent's
top-level configuration directory.

If global instructions are added later, keep each source in its explicit path
under `home/` (for example, `home/.codex/AGENTS.md`) and link that file from
`home.nix`. Do not reuse the project instruction file as global configuration.

`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, and `tasks-axi`
are exact-pinned in `agent-tools/package.json`, with their complete dependency
tree and registry integrity hashes committed in `package-lock.json`.
`scripts/post-switch.sh` installs that reviewed tree with `npm ci`, then installs
Pi (`@earendil-works/pi-coding-agent`) at its latest release on top: Pi is a
deliberately rolling first-party harness (no pin, no cooldown — see `TRUST.md`),
so it is intentionally absent from `package.json`/`package-lock.json`. The
npm-audit and registry-signature gates then cover the whole installed tree, Pi
included, rejecting any known production vulnerability. A
vulnerability without a compatible fix must have a documented, expiring entry
in `security/npm-audit-exceptions.json`; the audit gate fails again when that
exception expires. The privileged `gh-axi`, `chrome-devtools-axi`, and
`quota-axi` pins additionally carry the same release-cooldown hold as Treehouse
and no-mistakes below: the daily CI gate holds a newer npm release through the
cooldown, then fails until the pin is deliberately advanced. That gate also
fails on a committed privileged pin that is itself still inside the cooldown
unless a valid Firstmate dependency-floor exception covers it (see `TRUST.md`
and the preflight below).

OpenCode's official `@opencode-ai/plugin` authoring package is a separate npm
project, exact-pinned in `home/.config/opencode/package.json` with its dependency
integrity lock beside it. The tracked configuration has no plugin/custom-tool
source or runtime import, so `TRUST.md` classifies this installed support package
as Tier C rather than inheriting the shell, SDK, auth, and tool reach that
actual OpenCode plugins can receive. Its existing Dependabot entry still delays
routine proposals by seven days and lets security updates bypass the delay, but
Tier C does not add it to the fail-closed privileged release checker. The normal
exact-pin, `ignore-scripts`, npm-audit, registry-signature, and PR review controls
remain in force.

Nix-managed wrappers invoke the exact mise-pinned Node runtime directly, so
they do not depend on an agent session's inherited shell initialization or Node
shim state.
Dependabot checks daily and proposes minor and patch updates as soon as their
cooldown expires, while security updates bypass the delay and target the minimum
patched version. Major routine
updates remain manual. A Dependabot proposal for an `*-axi` tool moves only the
npm pin, so CI marks it red on purpose; it is replaced by a coordinated update
rather than merged (see `AGENTS.md`).

Treehouse and no-mistakes use the equivalent Go/Nix policy. Their release tags,
source revisions, and NAR hashes are pinned through `flake.lock`. Daily CI scans
the exact locked source commits with pinned `govulncheck`, compiles and smoke
tests both commands using a current Go security patch, and reports a newer
stable release only after a seven-day cooldown. The pinned nixpkgs toolchain is
kept on a security-patched Go release as well. Go findings, including
module-only findings outside a reachable call path, fail unless they have a
scoped, expiring entry in `security/go-vulnerability-exceptions.json`.

Matt Pocock's engineering, productivity,
misc, and personal skills plus every installable skill bundled with the pinned
npm agent tools are pinned as flake inputs, exposed from
`~/.agents/skills`, and linked into Claude and Pi. Deprecated and in-progress
Matt Pocock skills are deliberately excluded. The `matt-pocock-skills` input is
pinned to a tagged release in `flake.nix`; new skills in an included category are
discovered automatically after bumping that tag in a reviewed `flake.nix` edit.
The package skills use their npm package names: `chrome-devtools-axi`, `gh-axi`,
`lavish-axi`, `quota-axi`, and `tasks-axi`. Pi's example-only dynamic-resources
skill is deliberately excluded.

Firstmate is different: it is an agent distro whose clone contains mutable
configuration and state. Bootstrap creates `~/firstmate` once, then leaves that
clone under Firstmate's own update workflow instead of replacing it on every
rebuild. Per-project setup remains explicit: run `/setup-matt-pocock-skills` to
configure Matt's workflow and `no-mistakes init` to add a validation gate.

### Firstmate dependency-floor preflight

Use this separate two-step workflow when a reviewed candidate Firstmate commit
raises a hard tool floor above the committed dotfiles pin. Never substitute a
branch name or mutable `origin/main` for the full candidate SHA:

```sh
candidate=f1a4af426d7199c1781bc91ccd143b8e1f732d10
./scripts/check-firstmate-floor-exceptions.sh --candidate "$candidate"
./scripts/update-agent-tool-pin.sh --firstmate-commit "$candidate" <tool> <version>
git diff --check
./scripts/validate.sh
```

The first command reports every declared floor and exits nonzero while any pin
is unmet. The updater records the narrow exception and coordinates the reviewed
Nix, npm, lockfile, and trust surfaces; its own validation owns the detailed
record checks. Review and ship that dotfiles change first. The captain then
checks out the reviewed branch and runs:

```sh
./rebuild.sh
```

Only after that succeeds, update Firstmate separately (normally through its
`/updatefirstmate` workflow). Its guarded mechanical command is:

```sh
"$HOME/firstmate/bin/fm-update.sh"
```

Rebuild installs only committed pins and deliberately neither inspects, fetches,
nor modifies the existing mutable `~/firstmate` clone.

#### Retiring an exception

An exception is only valid while its adopted release is still inside the
seven-day cooldown; once the cooldown elapses the record is stale evidence and
`scripts/check-firstmate-floor-exceptions.sh` rejects it, which also fails the
daily privileged-tool security run. Every validation run prints how many hours
remain (`retire in 42h`) and warns on stderr inside the last two days, so the
deadline is visible before it bites. Retire the expired record mechanically and
ship the removal:

```sh
./scripts/check-firstmate-floor-exceptions.sh --retire-expired
git diff security/firstmate-floor-exceptions.json
./scripts/validate.sh
```

The command deletes only records whose adopted release has completed the
ordinary cooldown — those pins now stand on the normal policy and need no
exception — and leaves the pins themselves untouched.

`scripts/doctor.sh` verifies the commands, skills, and Firstmate clone rather
than checking only that command names exist.

Tool-specific portable preferences remain separate from mutable harness state:

- Codex: `/etc/codex/config.toml` supplies the tracked personality, enabled
  plugins, desktop preferences, and feature flags. The higher-precedence
  `~/.codex/config.toml` is an ordinary machine-local file for model, effort,
  and project trust choices.
- Claude: `home/.claude/settings.portable.json` tracks the status line, theme,
  TUI, plugins, and marketplaces. Home Manager overlays those
  keys onto the ordinary `~/.claude/settings.json`, preserving machine-local
  model, effort, and other harness-written keys.
- Pi: `settings.json` and `models.json` are entirely machine-local because the
  current contents select a local provider, model catalog, and thinking level.
- OpenCode: the plugin package manifest remains portable.

`scripts/materialize-agent-configs.sh` performs the migration after Home
Manager removes legacy links. It accepts missing files, so first bootstrap does
not require Claude, Codex, or Pi to have run. An existing regular file is
preserved, and an existing readable managed symlink is converted to a regular
file before its local values are merged.

Generated state is not tracked: model and effort selections, local provider
catalogs, auth files, histories, transcripts, caches, logs, sockets, jobs,
project trust lists, installation IDs, and local app bundle paths.

## Editing linked configs

Home Manager uses out-of-store symlinks for most app configuration. Editing
Neovim, Ghostty, or Herdr through their normal paths edits this checkout
directly. Agent harness settings are the exception: edit portable Claude and
Codex defaults in this checkout, while model, effort, project trust, and Pi
settings remain local under the harness's normal home-directory paths. Run
`./rebuild.sh` to apply portable-default or Nix changes.

## Nix garbage collection

`./rebuild.sh` reclaims Nix store space through `scripts/nix-gc.sh` after a
switch succeeds, so cleanup rides along with the rebuild you already run instead
of a scheduled job a powered-off laptop would silently miss. The behavior:

- **At most once every 7 days.** The last successful cleanup is timestamped in
  `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/nix-gc-last-run` (outside this
  repository); a rebuild within the interval skips collection.
- **Keeps a 30-day rollback window.** Collection uses
  `nix-collect-garbage --delete-older-than 30d` for both the user and the
  root-owned system profile, so every generation from the last 30 days —
  including the current one — survives and the rollback commands below keep
  working. It never uses a bare `-d`, which would delete every older generation.
- **Deduplicates the store.** `nix store optimise` runs afterward (best-effort).
- **Skippable.** Set `REBUILD_SKIP_GC=1` to skip collection for a single
  rebuild.

The interval, the 30-day retention window, and the skip variable are named
constants at the top of `scripts/nix-gc.sh`. To collect manually at any time:

```sh
nix-collect-garbage --delete-older-than 30d       # user generations
sudo nix-collect-garbage --delete-older-than 30d  # system generations
```

## Rollback and recovery

List nix-darwin generations:

```sh
darwin-rebuild --list-generations
```

Roll back to the previous system generation:

```sh
sudo darwin-rebuild --rollback
```

Switch to a specific known-good generation from the list above:

```sh
sudo darwin-rebuild --switch-generation <N>
```

If the shell or login itself is broken and `darwin-rebuild` will not run,
activate a known-good generation directly from its system profile link:

```sh
sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch
```

`./rebuild.sh` builds the system closure (`darwin-rebuild build`) before it
switches, so a configuration that fails to evaluate or build aborts without
touching the running system. The rollback commands above recover when a switch
that did activate turns out to be broken.

Home Manager uses the suffix `.dotfiles-backup` when an existing file blocks
the first activation. Review those backups after a successful migration and
remove them manually when no longer needed.

The original fork and its Git history were intentionally detached and replaced
when this standalone repository was created.
