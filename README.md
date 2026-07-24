# dotfiles

My repeatable Apple Silicon Mac setup for agentic development. It is inspired
by [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), but the
configuration and macOS preferences here are derived from my own machine.

One repository manages:

- Codex, Claude Code, Pi, and OpenCode, all using the same global `AGENTS.md`
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

Rebuilds update Homebrew metadata and greedily upgrade every declared cask.
This intentionally favors the latest available release, including for
self-updating or unversioned apps such as agent harnesses. The final doctor
check fails if any Homebrew formula or cask is still outdated. Pi follows the
same policy: its Bun package is resolved from the latest registry release on
every rebuild, and the doctor verifies the installed version.

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

Home Manager enables mise, pins Node 24.6.0 and Ruby 4.0.6, and activates mise
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

Update pinned Nix inputs:

```sh
nix flake update
./scripts/validate.sh
./rebuild.sh
```

## Repository map

| Path | Purpose |
| --- | --- |
| `flake.nix` / `flake.lock` | Pinned nix-darwin, Home Manager, nix-homebrew, and nixpkgs inputs |
| `configuration.nix` | Platform, user, and the three requested macOS behaviors |
| `homebrew.nix` | Complete reviewed Homebrew inventory and strict convergence policy |
| `home.nix` | Shell, Git, environment variables, and out-of-store symlinks |
| `AGENTS.md` | Canonical global instruction file shared by all four coding agents |
| `home/.*` | Portable app configurations copied from the working Mac |
| `bootstrap.sh` | One-time fresh-machine setup |
| `rebuild.sh` | Normal apply workflow |
| `scripts/homebrew-preflight.sh` | Destructive cleanup preview for bootstrap and rebuild |
| `scripts/post-switch.sh` | Pinned agents/tools plus mise runtime installation |
| `scripts/doctor.sh` | Read-only outcome checks |
| `scripts/check-secrets.sh` | Repository credential guard |

## Shared agent instructions

`AGENTS.md` is the single source of truth. Home Manager links it to:

- `~/.codex/AGENTS.md`
- `~/.claude/CLAUDE.md`
- `~/.pi/agent/AGENTS.md`
- `~/.config/opencode/AGENTS.md`

Pi, `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `quota-axi`, and `tasks-axi`
are exact-pinned in `agent-tools/package.json`, with their complete dependency
tree and registry integrity hashes committed in `package-lock.json`.
`scripts/post-switch.sh` installs that reviewed tree with `npm ci`, rejects any
known production vulnerability, and verifies npm registry signatures. A
vulnerability without a compatible fix must have a documented, expiring entry
in `security/npm-audit-exceptions.json`; the audit gate fails again when that
exception expires.
Nix-managed wrappers invoke the exact mise-pinned Node runtime directly, so
they do not depend on an agent session's inherited shell initialization or Node
shim state.
Dependabot proposes delayed minor and patch updates weekly, while security
updates bypass the delay and target the minimum patched version. Major routine
updates remain manual.

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
Matt Pocock skills are deliberately excluded. New skills in an included category
are discovered automatically after `nix flake update matt-pocock-skills`.
The package skills use their npm package names: `chrome-devtools-axi`, `gh-axi`,
`lavish-axi`, `quota-axi`, and `tasks-axi`. Pi's example-only dynamic-resources
skill is deliberately excluded.

Firstmate is different: it is an agent distro whose clone contains mutable
configuration and state. Bootstrap creates `~/firstmate` once, then leaves that
clone under Firstmate's own update workflow instead of replacing it on every
rebuild. Per-project setup remains explicit: run `/setup-matt-pocock-skills` to
configure Matt's workflow and `no-mistakes init` to add a validation gate.

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

## Rollback and recovery

List nix-darwin generations:

```sh
darwin-rebuild --list-generations
```

Roll back to the previous system generation:

```sh
sudo darwin-rebuild --rollback
```

Home Manager uses the suffix `.dotfiles-backup` when an existing file blocks
the first activation. Review those backups after a successful migration and
remove them manually when no longer needed.

The original fork and its Git history were intentionally detached and replaced
when this standalone repository was created.
