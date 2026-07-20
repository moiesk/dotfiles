# dotfiles

My repeatable Apple Silicon Mac setup for agentic development. It is inspired
by [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), but the
configuration and macOS preferences here are derived from my own machine.

One repository manages:

- Codex, Claude Code, Pi, and OpenCode, all using the same global `AGENTS.md`
- Ghostty, Herdr, zsh, Starship, fzf, asdf, and Neovim/LazyVim
- Homebrew formulae, casks, taps, and the OpenAI editor extension
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
7. Installs pinned user-scoped agent tools and runs the doctor.

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

Later `./rebuild.sh` runs are not interactive. Add new packages to
`homebrew.nix` before rebuilding.

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
| `scripts/homebrew-preflight.sh` | First-run destructive cleanup preview |
| `scripts/post-switch.sh` | Pinned Pi, helper CLI, uv tool, OpenCode, and asdf setup |
| `scripts/doctor.sh` | Read-only outcome checks |
| `scripts/check-secrets.sh` | Repository credential guard |

## Shared agent instructions

`AGENTS.md` is the single source of truth. Home Manager links it to:

- `~/.codex/AGENTS.md`
- `~/.claude/CLAUDE.md`
- `~/.pi/agent/AGENTS.md`
- `~/.config/opencode/AGENTS.md`

Tool-specific portable preferences remain separate:

- Codex: personality, model/effort, enabled plugins, and desktop preferences
- Claude: model, status line, theme, effort, plugins, and spinner verbs
- Pi: LM Studio provider and model defaults
- OpenCode: plugin package manifest

Generated state is not tracked: auth files, histories, transcripts, caches,
logs, sockets, jobs, project trust lists, installation IDs, and local app
bundle paths.

## Editing linked configs

Home Manager uses out-of-store symlinks for app configuration. Editing Neovim,
Ghostty, Herdr, or agent settings through their normal paths edits this
checkout directly. Run `./rebuild.sh` when changing Nix files, package lists,
shell configuration, or link declarations.

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
