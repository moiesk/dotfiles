#!/usr/bin/env bash
# Stage and validate a coordinated AXI flake/npm/trust pin update, then install it.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
NIX_BIN="${NIX_BIN:-nix}"
MISE_BIN="${MISE_BIN:-mise}"
stage_dir=""
backup_dir=""
replacement_files=""
installing=0

usage() {
  cat <<'EOF'
Usage: scripts/update-agent-tool-pin.sh <tool> <version>

Coordinate one supported npm-backed AXI tool across flake.nix, flake.lock,
agent-tools/package.json, agent-tools/package-lock.json, and TRUST.md.

VERSION must be a plain exact major.minor.patch semver. This helper does not
assess release eligibility or bypass TRUST.md policy. Before running it, the
maintainer must establish that the selected release is eligible, including the
7-day cooldown for tools whose trust tier requires it.

The repository must start clean. The update is built and fully validated in a
temporary copy before the coordinated files are installed for review. This
command never commits, pushes, manages GitHub branches or PRs, activates the
configuration, or runs rebuild.sh.
EOF
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  exit_status=$?
  trap - EXIT INT TERM HUP

  if [[ "$installing" == "1" && -n "$backup_dir" && -d "$backup_dir" ]]; then
    for relative in flake.nix flake.lock agent-tools/package.json agent-tools/package-lock.json TRUST.md; do
      if [[ -f "$backup_dir/$relative" ]]; then
        rollback="$DOTFILES_DIR/$(dirname "$relative")/.update-agent-tool-pin.rollback.$$"
        cp -p "$backup_dir/$relative" "$rollback" || true
        mv -f "$rollback" "$DOTFILES_DIR/$relative" || true
      fi
    done
    printf '%s\n' 'error: installation failed; restored every coordinated pin file' >&2
  fi

  if [[ -n "$replacement_files" ]]; then
    while IFS= read -r replacement; do
      [[ -z "$replacement" ]] || rm -f "$replacement"
    done <<<"$replacement_files"
  fi
  [[ -z "$stage_dir" ]] || rm -rf "$stage_dir"
  [[ -z "$backup_dir" ]] || rm -rf "$backup_dir"
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

replace_literal_once() {
  file="$1"
  old="$2"
  new="$3"
  count="$(grep -F -o -- "$old" "$file" | grep -c '' || true)"
  [[ "$count" == "1" ]] ||
    fail "$file must contain exactly one occurrence of '$old' (found $count)"

  awk -v old="$old" -v new="$new" '
    {
      position = index($0, old)
      if (position) {
        $0 = substr($0, 1, position - 1) new substr($0, position + length(old))
      }
      print
    }
  ' "$file" >"$file.update-agent-tool-pin"
  mv "$file.update-agent-tool-pin" "$file"
}

lock_closure_filter='
  def dependency_paths($packages; $path):
    (($packages[$path].dependencies // {}) | keys[]) as $dependency
    | ($packages | keys[]
       | select(. == ("node_modules/" + $dependency)
                or endswith("/node_modules/" + $dependency)));
  def expand($packages; $seen):
    reduce $seen[] as $path
      ($seen; . + [dependency_paths($packages; $path)]) | unique;
  def closure($packages; $seen):
    (expand($packages; $seen)) as $next
    | if ($next | length) == ($seen | length)
      then $next
      else closure($packages; $next)
      end;
'

if [[ "$#" == "1" && ("$1" == "-h" || "$1" == "--help") ]]; then
  usage
  exit 0
fi
[[ "$#" == "2" ]] || { usage >&2; exit 2; }
tool="$1"
version="$2"

if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "version must be a plain exact semver (major.minor.patch): $version"
fi

DOTFILES_DIR="$(cd "$DOTFILES_DIR" 2>/dev/null && pwd -P)" ||
  fail "repository directory does not exist: $DOTFILES_DIR"
inventory="$DOTFILES_DIR/scripts/agent-tool-pins.tsv"
[[ -f "$inventory" && ! -L "$inventory" ]] ||
  fail "missing safe agent tool inventory: $inventory"

matching_rows="$(awk -F '\t' -v tool="$tool" '$1 !~ /^#/ && ($1 == tool || $2 == tool) { print }' "$inventory")"
matching_count="$(printf '%s\n' "$matching_rows" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$matching_count" == "1" ]] ||
  fail "unsupported or ambiguous AXI tool '$tool'; choose exactly one tool from scripts/agent-tool-pins.tsv"
IFS=$'\t' read -r flake_input npm_package tag_prefix extra <<<"$matching_rows"
[[ -n "$flake_input" && -n "$npm_package" && -n "$tag_prefix" && -z "${extra:-}" ]] ||
  fail "invalid inventory record for $tool"

for command_name in git jq rg awk grep tar "$NIX_BIN" "$MISE_BIN"; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command is unavailable: $command_name"
done

git_root="$(git -C "$DOTFILES_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "$DOTFILES_DIR is not a Git worktree"
git_root="$(cd "$git_root" && pwd -P)"
[[ "$git_root" == "$DOTFILES_DIR" ]] ||
  fail "DOTFILES_DIR must be the Git worktree root (found $git_root)"
head_at_start="$(git -C "$DOTFILES_DIR" rev-parse --verify HEAD 2>/dev/null)" ||
  fail "the worktree has no valid HEAD"
starting_status="$(git -C "$DOTFILES_DIR" status --porcelain --untracked-files=all)"
[[ -z "$starting_status" ]] ||
  fail "the worktree must be clean; preserve and finish unrelated work before updating a pin"

mutation_files='flake.nix
flake.lock
agent-tools/package.json
agent-tools/package-lock.json
TRUST.md'
while IFS= read -r relative; do
  [[ -f "$DOTFILES_DIR/$relative" && ! -L "$DOTFILES_DIR/$relative" ]] ||
    fail "required pin surface is missing, not regular, or a symlink: $relative"
  git -C "$DOTFILES_DIR" ls-files --error-unmatch "$relative" >/dev/null 2>&1 ||
    fail "required pin surface is not tracked: $relative"
done <<<"$mutation_files"
[[ -x "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" ]] ||
  fail "scripts/check-agent-tool-pins.sh is missing or not executable"

# Refuse malformed, missing, duplicate, or already-drifted records before staging.
DOTFILES_DIR="$DOTFILES_DIR" "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" >/dev/null
old_version="$(jq -er --arg tool "$npm_package" '.dependencies[$tool]' \
  "$DOTFILES_DIR/agent-tools/package.json")" ||
  fail "agent-tools/package.json must contain exactly one dependency record for $npm_package"
[[ "$old_version" != "$version" ]] || fail "$npm_package is already pinned to $version"
old_ref="${tag_prefix}${old_version}"
new_ref="${tag_prefix}${version}"

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-agent-tool-pin.XXXXXX")"
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-agent-tool-pin-backup.XXXXXX")"
git -C "$DOTFILES_DIR" archive "$head_at_start" | tar -xf - -C "$stage_dir"

replace_literal_once "$stage_dir/flake.nix" "/$old_ref\";" "/$new_ref\";"
cp "$stage_dir/flake.lock" "$stage_dir/flake.lock.before-update"
"$NIX_BIN" flake update "$flake_input" --flake "$stage_dir"
if ! jq -e -n --arg tool "$flake_input" \
  --slurpfile old "$stage_dir/flake.lock.before-update" \
  --slurpfile new "$stage_dir/flake.lock" \
  '($old[0] | del(.nodes[$tool])) == ($new[0] | del(.nodes[$tool]))' >/dev/null; then
  fail "targeted Nix update changed lock records outside input $flake_input"
fi
rm "$stage_dir/flake.lock.before-update"

cp "$stage_dir/agent-tools/package.json" "$stage_dir/agent-tools/package.json.before-update"
cp "$stage_dir/agent-tools/package-lock.json" "$stage_dir/agent-tools/package-lock.json.before-update"
(
  cd "$stage_dir/agent-tools"
  "$MISE_BIN" exec -- npm install --package-lock-only --save-exact \
    --ignore-scripts --no-audit --no-fund "${npm_package}@${version}"
)
if ! jq -e -n --arg tool "$npm_package" \
  --slurpfile old "$stage_dir/agent-tools/package.json.before-update" \
  --slurpfile new "$stage_dir/agent-tools/package.json" '
    ($old[0] | .dependencies |= del(.[$tool]))
    == ($new[0] | .dependencies |= del(.[$tool]))
    and $new[0].dependencies[$tool] != null
  ' >/dev/null; then
  fail "npm changed package.json outside the selected dependency $npm_package"
fi
if ! jq -e -n --arg tool "$npm_package" \
  --slurpfile old "$stage_dir/agent-tools/package-lock.json.before-update" \
  --slurpfile new "$stage_dir/agent-tools/package-lock.json" '
    ($old[0] | del(.packages)) == ($new[0] | del(.packages))
    and (($old[0].packages[""] | .dependencies |= del(.[$tool]))
         == ($new[0].packages[""] | .dependencies |= del(.[$tool])))
  ' >/dev/null; then
  fail "npm lockfile changed root metadata or a direct dependency other than $npm_package"
fi
unrelated_lock_churn="$(jq -r -n --arg tool "$npm_package" \
  --slurpfile old "$stage_dir/agent-tools/package-lock.json.before-update" \
  --slurpfile new "$stage_dir/agent-tools/package-lock.json" \
  "$lock_closure_filter"'
    ($old[0]) as $old_lock | ($new[0]) as $new_lock
    | ([($old_lock.packages | keys[]), ($new_lock.packages | keys[])] | unique
       | map(select(. != "" and $old_lock.packages[.] != $new_lock.packages[.]))) as $changed
    | ((closure($old_lock.packages; ["node_modules/" + $tool])
        + closure($new_lock.packages; ["node_modules/" + $tool])) | unique) as $allowed
    | ($changed - $allowed)[]
  ' )"
if [[ -n "$unrelated_lock_churn" ]]; then
  printf '%s\n' "$unrelated_lock_churn" >&2
  fail "npm lockfile contains churn unrelated to $npm_package"
fi
rm "$stage_dir/agent-tools/package.json.before-update" \
  "$stage_dir/agent-tools/package-lock.json.before-update"

trust_row="$(rg -F -- "https://github.com/kunchenguid/${npm_package})" "$stage_dir/TRUST.md" || true)"
trust_count="$(printf '%s\n' "$trust_row" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$trust_count" == "1" ]] ||
  fail "TRUST.md must contain exactly one inventory row for $npm_package"
for old_pin in "$old_ref" "${npm_package}@${old_version}"; do
  pin_count="$(grep -F -o -- "$old_pin" <<<"$trust_row" | grep -c '' || true)"
  [[ "$pin_count" == "1" ]] ||
    fail "TRUST.md row for $npm_package must contain exactly one current pin $old_pin"
done
new_trust_row="${trust_row//$old_ref/$new_ref}"
new_trust_row="${new_trust_row//${npm_package}@${old_version}/${npm_package}@${version}}"
replace_literal_once "$stage_dir/TRUST.md" "$trust_row" "$new_trust_row"

DOTFILES_DIR="$stage_dir" "$stage_dir/scripts/check-agent-tool-pins.sh"
"$stage_dir/scripts/validate.sh"

[[ "$(git -C "$DOTFILES_DIR" rev-parse --verify HEAD)" == "$head_at_start" ]] ||
  fail "HEAD changed while the update was staged; no files were installed"
[[ -z "$(git -C "$DOTFILES_DIR" status --porcelain --untracked-files=all)" ]] ||
  fail "the worktree changed while the update was staged; no files were installed"

while IFS= read -r relative; do
  mkdir -p "$backup_dir/$(dirname "$relative")"
  cp -p "$DOTFILES_DIR/$relative" "$backup_dir/$relative"
  replacement="$DOTFILES_DIR/$(dirname "$relative")/.update-agent-tool-pin.$(basename "$relative").$$"
  cp -p "$stage_dir/$relative" "$replacement"
  replacement_files="${replacement_files}${replacement_files:+$'\n'}${replacement}"
done <<<"$mutation_files"

installing=1
while IFS= read -r relative; do
  replacement="$DOTFILES_DIR/$(dirname "$relative")/.update-agent-tool-pin.$(basename "$relative").$$"
  mv -f "$replacement" "$DOTFILES_DIR/$relative"
done <<<"$mutation_files"
installing=0

printf 'coordinated %s pin update staged: %s -> %s\n' "$npm_package" "$old_version" "$version"
printf '%s\n' 'Review the five-file diff, then commit it on a branch and ship a replacement PR.'
printf '%s\n' 'Close the incomplete Dependabot PR as superseded; activation remains a separate captain action.'
