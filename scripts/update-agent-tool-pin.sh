#!/usr/bin/env bash
# Stage and validate a coordinated AXI flake/npm/trust pin update, then install it.
set -euo pipefail

# Every git command below must address the repository named by its -C path, and
# the staging repository must be self-contained. An inherited git environment
# (a hook, `git bisect run`) would silently redirect all of them at the caller's
# repository, so it is dropped before the first git invocation.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
NIX_BIN="${NIX_BIN:-nix}"
MISE_BIN="${MISE_BIN:-mise}"
stage_dir=""
backup_dir=""
replacement_files=""
installing=0

usage() {
  cat <<'EOF'
Usage: scripts/update-agent-tool-pin.sh [--firstmate-commit <sha>] <tool> <version>

Coordinate one supported npm-backed AXI tool across flake.nix, flake.lock,
agent-tools/package.json, agent-tools/package-lock.json, and TRUST.md.

VERSION must be a plain exact major.minor.patch semver. Without
--firstmate-commit, this helper does not assess ordinary release eligibility or
bypass TRUST.md policy; the maintainer must first establish that the selected
release is eligible, including the 7-day cooldown where required. When an exact
candidate Firstmate commit raises a hard dependency floor above the current pin,
pass --firstmate-commit to record and mechanically validate the narrow exception.

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
    for relative in flake.nix flake.lock agent-tools/package.json agent-tools/package-lock.json TRUST.md security/firstmate-floor-exceptions.json; do
      if [[ -f "$backup_dir/$relative" ]]; then
        rollback="$DOTFILES_DIR/$(dirname "$relative")/.update-agent-tool-pin.rollback.$$"
        cp -p "$backup_dir/$relative" "$rollback" || true
        mv -f "$rollback" "$DOTFILES_DIR/$relative" || rm -f "$rollback"
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

  replace_old="$old" replace_new="$new" awk '
    BEGIN {
      old = ENVIRON["replace_old"]
      new = ENVIRON["replace_new"]
      replaced = 0
    }
    {
      position = replaced ? 0 : index($0, old)
      if (position) {
        $0 = substr($0, 1, position - 1) new substr($0, position + length(old))
        replaced = 1
      }
      print
    }
    END { if (!replaced) exit 1 }
  ' "$file" >"$file.update-agent-tool-pin" ||
    { rm -f "$file.update-agent-tool-pin"; fail "failed to substitute '$old' in $file"; }
  mv "$file.update-agent-tool-pin" "$file"
}

lock_closure_filter='
  def dependency_paths($packages; $path):
    ((($packages[$path].dependencies // {})
      + ($packages[$path].optionalDependencies // {})
      + ($packages[$path].peerDependencies // {})) | keys[]) as $dependency
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
firstmate_commit=""
if [[ "$#" -ge 1 && "$1" == --firstmate-commit ]]; then
  [[ "$#" == 4 ]] || { usage >&2; exit 2; }
  firstmate_commit="$2"
  shift 2
fi
[[ "$#" == "2" ]] || { usage >&2; exit 2; }
tool="$1"
version="$2"

if [[ -n "$firstmate_commit" && ! "$firstmate_commit" =~ ^[0-9a-f]{40}$ ]]; then
  fail "Firstmate commit must be an exact lowercase 40-hex SHA: $firstmate_commit"
fi

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
TRUST.md
security/firstmate-floor-exceptions.json'
while IFS= read -r relative; do
  [[ -f "$DOTFILES_DIR/$relative" && ! -L "$DOTFILES_DIR/$relative" ]] ||
    fail "required pin surface is missing, not regular, or a symlink: $relative"
  git -C "$DOTFILES_DIR" ls-files --error-unmatch "$relative" >/dev/null 2>&1 ||
    fail "required pin surface is not tracked: $relative"
done <<<"$mutation_files"
[[ -x "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" ]] ||
  fail "scripts/check-agent-tool-pins.sh is missing or not executable"
[[ -x "$DOTFILES_DIR/scripts/check-firstmate-floor-exceptions.sh" ]] ||
  fail "scripts/check-firstmate-floor-exceptions.sh is missing or not executable"

# Refuse malformed, missing, duplicate, or already-drifted records before staging.
DOTFILES_DIR="$DOTFILES_DIR" "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" >/dev/null
old_version="$(jq -er --arg tool "$npm_package" '.dependencies[$tool]' \
  "$DOTFILES_DIR/agent-tools/package.json")" ||
  fail "agent-tools/package.json must contain exactly one dependency record for $npm_package"
[[ "$old_version" != "$version" ]] || fail "$npm_package is already pinned to $version"
old_ref="${tag_prefix}${old_version}"
new_ref="${tag_prefix}${version}"

history_dir="$DOTFILES_DIR"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-agent-tool-pin.XXXXXX")"
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-agent-tool-pin-backup.XXXXXX")"
git -C "$DOTFILES_DIR" archive "$head_at_start" | tar -xf - -C "$stage_dir"
# The staged copy must be a git work tree whose tracked set is exactly the
# archived HEAD: validation includes checks that read `git ls-files` to confirm
# a capability tier, and those refuse to run outside a work tree. `--force` with
# no excludes file keeps the staged tracked set identical to HEAD's. An index is
# all those checks need, so the stage is deliberately left without any commit.
git -C "$stage_dir" init -q
git -C "$stage_dir" -c core.excludesFile=/dev/null add --all --force

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

exceptions_file="$stage_dir/security/firstmate-floor-exceptions.json"
jq --arg dependency "$npm_package" \
  '.exceptions |= map(select(.dependency != $dependency))' \
  "$exceptions_file" >"$exceptions_file.next"
mv "$exceptions_file.next" "$exceptions_file"
if [[ -n "$firstmate_commit" ]]; then
  required_version="$(DOTFILES_DIR="$stage_dir" \
    "$stage_dir/scripts/check-firstmate-floor-exceptions.sh" \
    --show-floor "$npm_package" "$firstmate_commit")" ||
    fail "could not establish the $npm_package floor at Firstmate commit $firstmate_commit"
  if node -e '
    const parse = value => value.split(".").map(Number);
    const a = parse(process.argv[1]); const b = parse(process.argv[2]);
    const compare = (x, y) => x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
    process.exit(compare(a, b) >= 0 ? 0 : 1);
  ' "$old_version" "$required_version"; then
    fail "Firstmate floor $required_version is unrelated because current $npm_package pin $old_version already satisfies it"
  fi
  jq \
    --arg dependency "$npm_package" \
    --arg previous "$old_version" \
    --arg adopted "$version" \
    --arg required "$required_version" \
    --arg commit "$firstmate_commit" '
      .exceptions += [{
        dependency: $dependency,
        previous_version: $previous,
        adopted_version: $adopted,
        required_version: $required,
        firstmate_repository: "kunchenguid/firstmate",
        firstmate_commit: $commit
      }]
    ' "$exceptions_file" >"$exceptions_file.next"
  mv "$exceptions_file.next" "$exceptions_file"
  DOTFILES_DIR="$stage_dir" DOTFILES_HISTORY_DIR="$history_dir" \
    "$stage_dir/scripts/check-firstmate-floor-exceptions.sh"
fi

DOTFILES_DIR="$stage_dir" "$stage_dir/scripts/check-agent-tool-pins.sh"
DOTFILES_HISTORY_DIR="$history_dir" "$stage_dir/scripts/validate.sh"

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
if [[ -n "$firstmate_commit" ]]; then
  printf 'recorded exact Firstmate floor evidence: %s requires %s at %s\n' \
    "$npm_package" "$required_version" "$firstmate_commit"
fi
printf '%s\n' 'Review the coordinated pin and exception-evidence diff, then commit it on a branch and ship a replacement PR.'
printf '%s\n' 'Close the incomplete Dependabot PR as superseded; activation remains a separate captain action.'
