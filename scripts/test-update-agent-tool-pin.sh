#!/usr/bin/env bash
# Transactional fixture tests for scripts/update-agent-tool-pin.sh.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$DOTFILES_DIR/scripts/update-agent-tool-pin.sh"
tmp_dir="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_error() {
  printf 'error: update helper fixture is invalid: %s\n' "$1" >&2
  exit 1
}

helper_error() {
  printf 'error: scripts/update-agent-tool-pin.sh regressed: %s\n' "$1" >&2
  exit 1
}

make_fixture() {
  fixture="$tmp_dir/repo"
  rm -rf "$fixture"
  mkdir -p "$fixture/agent-tools" "$fixture/scripts" "$fixture/security"
  cp "$DOTFILES_DIR/flake.nix" "$DOTFILES_DIR/flake.lock" "$DOTFILES_DIR/TRUST.md" "$fixture/"
  cp "$DOTFILES_DIR/agent-tools/package.json" \
    "$DOTFILES_DIR/agent-tools/package-lock.json" "$fixture/agent-tools/"
  cp "$DOTFILES_DIR/scripts/agent-tool-pins.tsv" \
    "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" \
    "$DOTFILES_DIR/scripts/check-firstmate-floor-exceptions.sh" \
    "$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv" "$fixture/scripts/"
  cp "$DOTFILES_DIR/security/firstmate-floor-exceptions.json" "$fixture/security/"
  # Repository checks read `git ls-files` to establish a capability tier and
  # refuse to run outside a work tree, so the stub asserts what they need: the
  # staged copy is its own work tree whose tracked set is exactly the archived
  # HEAD of the source repository.
  cat >"$fixture/scripts/validate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
stage_fail() {
  printf 'error: scripts/update-agent-tool-pin.sh regressed: %s\n' "$1" >&2
  exit 1
}
[[ "$(git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] ||
  stage_fail 'the staged copy is not a git work tree'
stage_root="$(git -C "$DOTFILES_DIR" rev-parse --show-toplevel)"
[[ "$stage_root" -ef "$DOTFILES_DIR" ]] ||
  stage_fail "the staged copy belongs to an enclosing work tree: $stage_root"
[[ -n "${DOTFILES_HISTORY_DIR:-}" ]] ||
  stage_fail 'validation did not receive DOTFILES_HISTORY_DIR'
staged_tracked="$(git -C "$DOTFILES_DIR" ls-files | sort)"
[[ -n "$staged_tracked" ]] || stage_fail 'the staged copy tracks no files'
archived_tracked="$(git -C "$DOTFILES_HISTORY_DIR" ls-files | sort)"
[[ "$staged_tracked" == "$archived_tracked" ]] || {
  diff <(printf '%s\n' "$archived_tracked") <(printf '%s\n' "$staged_tracked") >&2 || true
  stage_fail 'the staged tracked set differs from the archived HEAD tracked set'
}
DOTFILES_DIR="$DOTFILES_DIR" "$DOTFILES_DIR/scripts/check-agent-tool-pins.sh" >/dev/null
printf '%s\n' 'fixture validation passed'
EOF
  chmod +x "$fixture/scripts/check-agent-tool-pins.sh" \
    "$fixture/scripts/check-firstmate-floor-exceptions.sh" "$fixture/scripts/validate.sh"
  git -C "$fixture" init -q
  git -C "$fixture" config user.name 'Fixture Test'
  git -C "$fixture" config user.email 'fixture@example.invalid'
  git -C "$fixture" add .
  git -C "$fixture" commit -qm fixture
}

commit_fixture() {
  git -C "$fixture" add .
  git -C "$fixture" commit -qm 'fixture mutation'
}

make_mocks() {
  mock_bin="$tmp_dir/mock-bin"
  rm -rf "$mock_bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NIX_LOG"
if [[ "${NIX_FAIL:-0}" == "1" ]]; then
  printf '%s\n' 'mock nix failure' >&2
  exit 23
fi
[[ "$#" == "5" && "$1" == "flake" && "$2" == "update" && "$4" == "--flake" ]] || {
  printf 'unexpected nix invocation: %s\n' "$*" >&2
  exit 24
}
tool="$3"
repo="$5"
ref="$(sed -nE "s|^[[:space:]]*url = \"github:kunchenguid/${tool}/([^\"]+)\";|\\1|p" "$repo/flake.nix")"
[[ -n "$ref" && "$ref" != *$'\n'* ]]
jq --arg tool "$tool" --arg ref "$ref" \
  '.nodes[$tool].original.ref = $ref' "$repo/flake.lock" >"$repo/flake.lock.new"
mv "$repo/flake.lock.new" "$repo/flake.lock"
EOF
  cat >"$mock_bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MISE_LOG"
if [[ "${MISE_FAIL:-0}" == "1" ]]; then
  printf '%s\n' 'mock mise/npm failure' >&2
  exit 25
fi
[[ "$1" == "exec" && "$2" == "--" && "$3" == "npm" && "$4" == "install" ]] || {
  printf 'unexpected mise invocation: %s\n' "$*" >&2
  exit 26
}
spec="${!#}"
tool="${spec%@*}"
version="${spec##*@}"
jq --arg tool "$tool" --arg version "$version" \
  '.dependencies[$tool] = $version' package.json >package.json.new
mv package.json.new package.json
jq --arg tool "$tool" --arg path "node_modules/$tool" --arg version "$version" \
  '.packages[""].dependencies[$tool] = $version
   | .packages[$path].version = $version' package-lock.json >package-lock.json.new
mv package-lock.json.new package-lock.json
if [[ "${INJECT_UNRELATED_LOCK_CHURN:-0}" == "1" ]]; then
  jq '.packages["node_modules/unrelated-churn"] = {"version":"9.9.9"}' \
    package-lock.json >package-lock.json.new
  mv package-lock.json.new package-lock.json
fi
EOF
  cat >"$mock_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${!#}"
printf '%s\n' "$target" >>"$MV_LOG"
if [[ -n "${FAIL_INSTALL_TARGET:-}" && "$target" == "${FAIL_INSTALL_TARGET}" && ! -e "${MV_SENTINEL:-}" ]]; then
  : >"${MV_SENTINEL}"
  printf 'mock mv failure: %s\n' "$target" >&2
  exit 27
fi
if [[ -x /bin/mv ]]; then
  exec /bin/mv "$@"
fi
exec /usr/bin/mv "$@"
EOF
  chmod +x "$mock_bin/nix" "$mock_bin/mise" "$mock_bin/mv"
  NIX_LOG="$tmp_dir/nix.log"
  MISE_LOG="$tmp_dir/mise.log"
  MV_LOG="$tmp_dir/mv.log"
  export MV_LOG
  : >"$NIX_LOG"
  : >"$MISE_LOG"
  : >"$MV_LOG"
}

bumped_version() {
  pinned="$1"
  [[ "$pinned" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] ||
    fixture_error "live pin is not plain semver: $pinned"
  printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$((BASH_REMATCH[3] + 1))"
}

run_helper() {
  PATH="$mock_bin:$PATH" NIX_BIN=nix MISE_BIN=mise \
    NIX_LOG="$NIX_LOG" MISE_LOG="$MISE_LOG" DOTFILES_DIR="$fixture" \
    "$HELPER" "$@"
}

expect_failure() {
  expected="$1"
  shift
  if output="$(run_helper "$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    helper_error "helper accepted a failing scenario; expected: $expected"
  fi
  if ! grep -Fq -- "$expected" <<<"$output"; then
    printf '%s\n' "$output" >&2
    helper_error "helper did not explain refusal; expected: $expected"
  fi
}

assert_source_unchanged() {
  git -C "$fixture" diff --quiet -- || helper_error 'failed operation changed tracked source files'
  git -C "$fixture" diff --cached --quiet -- || helper_error 'failed operation changed the index'
}

make_mocks
supported_count=0
while IFS=$'\t' read -r flake_input tool tag_prefix extra; do
  [[ -z "$flake_input" || "$flake_input" == \#* ]] && continue
  [[ -n "$tool" && -n "$tag_prefix" && -z "${extra:-}" ]] ||
    fixture_error "invalid inventory record for $flake_input"
  supported_count=$((supported_count + 1))
  make_fixture
  : >"$NIX_LOG"
  : >"$MISE_LOG"
  old="$(jq -er --arg tool "$tool" '.dependencies[$tool]' "$fixture/agent-tools/package.json")"
  new="$(bumped_version "$old")"
  run_helper "$tool" "$new" >/dev/null

  [[ "$(jq -r --arg tool "$tool" '.dependencies[$tool]' "$fixture/agent-tools/package.json")" == "$new" ]] ||
    helper_error "$tool manifest was not updated"
  [[ "$(jq -r --arg tool "$flake_input" '.nodes[$tool].original.ref' "$fixture/flake.lock")" == "${tag_prefix}${new}" ]] ||
    helper_error "$tool lock ref was not updated"
  grep -Fq -- "${tag_prefix}${new}" "$fixture/TRUST.md" ||
    helper_error "$tool TRUST.md tag was not updated"
  grep -Fq -- "${tool}@${new}" "$fixture/TRUST.md" ||
    helper_error "$tool TRUST.md npm pin was not updated"

  [[ "$(wc -l <"$NIX_LOG" | tr -d ' ')" == "1" ]] ||
    helper_error "$tool must invoke Nix exactly once"
  read -r nix_flake nix_update nix_tool nix_flag nix_stage <"$NIX_LOG"
  [[ "$nix_flake" == "flake" && "$nix_update" == "update" && \
     "$nix_tool" == "$flake_input" && "$nix_flag" == "--flake" && -n "$nix_stage" ]] ||
    helper_error "$tool did not use a targeted nix flake update"
  [[ "$(wc -l <"$MISE_LOG" | tr -d ' ')" == "1" ]] ||
    helper_error "$tool must invoke npm exactly once"
  grep -Fq -- "${tool}@${new}" "$MISE_LOG" ||
    helper_error "$tool npm invocation omitted the exact package version"

  changed="$(git -C "$fixture" status --short | awk '{ print $2 }' | sort)"
  expected_changed="$({
    printf '%s\n' TRUST.md agent-tools/package-lock.json agent-tools/package.json flake.lock flake.nix
    if jq -e --arg dependency "$tool" \
      'any(.exceptions[]; .dependency == $dependency)' \
      "$DOTFILES_DIR/security/firstmate-floor-exceptions.json" >/dev/null; then
      printf '%s\n' security/firstmate-floor-exceptions.json
    fi
  } | sort)"
  [[ "$changed" == "$expected_changed" ]] || {
    printf 'changed files:\n%s\n' "$changed" >&2
    helper_error "$tool success did not leave exactly its coordinated pin and exception-evidence diff"
  }
done <"$DOTFILES_DIR/scripts/agent-tool-pins.tsv"
[[ "$supported_count" -gt 0 ]] || fixture_error 'shared inventory is empty'

make_fixture
make_mocks
first_tool="$(awk -F '\t' '$1 !~ /^#/ { print $2; exit }' "$DOTFILES_DIR/scripts/agent-tool-pins.tsv")"
first_prefix="$(awk -F '\t' '$1 !~ /^#/ { print $3; exit }' "$DOTFILES_DIR/scripts/agent-tool-pins.tsv")"
[[ -n "$first_tool" && -n "$first_prefix" ]] || fixture_error 'shared inventory has no usable first row'
first_old="$(jq -er --arg tool "$first_tool" '.dependencies[$tool]' "$fixture/agent-tools/package.json")"
first_new="$(bumped_version "$first_old")"
for malformed in 1.2 v1.2.3 1.2.3-beta 01.2.3 1.2.3+build; do
  expect_failure 'version must be a plain exact semver' "$first_tool" "$malformed"
  assert_source_unchanged
done
expect_failure 'unsupported or ambiguous AXI tool' unsupported-axi 1.2.3
assert_source_unchanged
expect_failure 'is already pinned' "$first_tool" "$first_old"
assert_source_unchanged

make_fixture
make_mocks
printf '%s\n' unrelated >"$fixture/unrelated-work.txt"
expect_failure 'worktree must be clean' "$first_tool" "$first_new"
[[ "$(cat "$fixture/unrelated-work.txt")" == unrelated ]] ||
  helper_error 'dirty-start refusal did not preserve unrelated work'

make_fixture
make_mocks
trust_match="$(rg -n -F "https://github.com/kunchenguid/${first_tool})" "$fixture/TRUST.md" | cut -d: -f1)"
awk -v line="$trust_match" 'NR != line' "$fixture/TRUST.md" >"$fixture/TRUST.md.new"
mv "$fixture/TRUST.md.new" "$fixture/TRUST.md"
commit_fixture
expect_failure "TRUST.md must contain exactly one inventory row for $first_tool" "$first_tool" "$first_new"
assert_source_unchanged

make_fixture
make_mocks
duplicate_trust_row="$(rg -F "https://github.com/kunchenguid/${first_tool})" "$fixture/TRUST.md")"
printf '%s\n' "$duplicate_trust_row" >>"$fixture/TRUST.md"
commit_fixture
expect_failure "TRUST.md must contain exactly one inventory row for $first_tool" "$first_tool" "$first_new"
assert_source_unchanged

make_fixture
make_mocks
MISE_FAIL=1
export MISE_FAIL
expect_failure 'mock mise/npm failure' "$first_tool" "$first_new"
unset MISE_FAIL
assert_source_unchanged
[[ -z "$(git -C "$fixture" status --porcelain --untracked-files=all)" ]] ||
  helper_error 'intermediate command failure left partial or temporary files in source'

make_fixture
make_mocks
INJECT_UNRELATED_LOCK_CHURN=1
export INJECT_UNRELATED_LOCK_CHURN
expect_failure 'npm lockfile contains churn unrelated' "$first_tool" "$first_new"
unset INJECT_UNRELATED_LOCK_CHURN
assert_source_unchanged
[[ -z "$(git -C "$fixture" status --porcelain --untracked-files=all)" ]] ||
  helper_error 'lock-churn refusal left partial or temporary files in source'

make_fixture
make_mocks
MV_SENTINEL="$tmp_dir/install-mv-fired"
FAIL_INSTALL_TARGET="$fixture/TRUST.md"
rm -f "$MV_SENTINEL"
export MV_SENTINEL FAIL_INSTALL_TARGET
expect_failure 'restored every coordinated pin file' "$first_tool" "$first_new"
unset MV_SENTINEL FAIL_INSTALL_TARGET
[[ -e "$tmp_dir/install-mv-fired" ]] ||
  fixture_error 'the install phase never failed, so rollback of installed files was not exercised'
for installed in flake.nix flake.lock agent-tools/package.json agent-tools/package-lock.json; do
  grep -Fxq -- "$fixture/$installed" "$MV_LOG" ||
    fixture_error "the install phase never replaced $installed, so rollback was not exercised"
done
assert_source_unchanged
[[ -z "$(git -C "$fixture" status --porcelain --untracked-files=all)" ]] ||
  helper_error 'install-phase rollback left partial or temporary files in source'

# A backslash in the TRUST.md row must survive the literal row substitution.
make_fixture
make_mocks
trust_line="$(rg -n -F "https://github.com/kunchenguid/${first_tool})" "$fixture/TRUST.md" | cut -d: -f1)"
[[ "$trust_line" =~ ^[0-9]+$ ]] || fixture_error 'could not locate a single TRUST.md row to annotate'
backslash_note=' \|annotated'
backslash_note="$backslash_note" awk -v line="$trust_line" \
  'NR == line { $0 = $0 ENVIRON["backslash_note"] } { print }' \
  "$fixture/TRUST.md" >"$fixture/TRUST.md.new"
mv "$fixture/TRUST.md.new" "$fixture/TRUST.md"
grep -Fq -- '\|annotated' "$fixture/TRUST.md" ||
  fixture_error 'the backslash annotation was never written to TRUST.md'
commit_fixture
run_helper "$first_tool" "$first_new" >/dev/null
grep -Fq -- '\|annotated' "$fixture/TRUST.md" ||
  helper_error 'row substitution dropped a backslash from the TRUST.md row'
grep -Fq -- "${first_prefix}${first_new}" "$fixture/TRUST.md" ||
  helper_error 'row substitution skipped the TRUST.md release tag'
grep -Fq -- "${first_tool}@${first_new}" "$fixture/TRUST.md" ||
  helper_error 'row substitution skipped the TRUST.md npm pin'

# The recorded floor exception must be checked against the real repository
# history, not the temporary stage copy, which is an index-only work tree with
# no commits and therefore no history to walk.
make_fixture
jq '.exceptions = []' "$fixture/security/firstmate-floor-exceptions.json" \
  >"$fixture/security/firstmate-floor-exceptions.json.next"
mv "$fixture/security/firstmate-floor-exceptions.json.next" \
  "$fixture/security/firstmate-floor-exceptions.json"
git -C "$fixture" diff --quiet -- || commit_fixture
make_mocks
floor_row="$(awk -F '\t' '$1 !~ /^#/ && $2 == "npm" && $6 == "yes" { print; exit }' \
  "$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv")"
[[ -n "$floor_row" ]] ||
  fixture_error 'no cooldown-gated npm dependency floor is registered, so the exception path is untestable'
IFS=$'\t' read -r floor_tool _ floor_pin_key _ _ _ _ _ <<<"$floor_row"
awk -F '\t' -v tool="$floor_pin_key" \
  '$1 !~ /^#/ && $2 == tool { found = 1 } END { exit found ? 0 : 1 }' \
  "$DOTFILES_DIR/scripts/agent-tool-pins.tsv" ||
  fixture_error "$floor_pin_key carries a Firstmate floor but is not a supported AXI pin"
floor_old="$(jq -er --arg tool "$floor_pin_key" '.dependencies[$tool]' \
  "$fixture/agent-tools/package.json")"
floor_new="$(bumped_version "$floor_old")"
floor_commit="$(printf 'd%039d' 9)"
FIXTURE_FLOOR="$floor_new"
FIXTURE_NPM_JSON="$(jq -n --arg old "$floor_old" --arg new "$floor_new" \
  --arg old_at "$(node -e 'console.log(new Date(Date.now() - 30 * 86400000).toISOString())')" \
  --arg new_at "$(node -e 'console.log(new Date(Date.now() - 86400000).toISOString())')" \
  '{versions: [$old, $new], time: {($old): $old_at, ($new): $new_at}}')"
cat >"$mock_bin/gh-axi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "api" && "$2" == "GET" && "$3" == */contents/*\?ref=* ]] || {
  printf 'unexpected gh-axi invocation: %s\n' "$*" >&2
  exit 28
}
printf '  truncated: false\n'
printf '  body: "%s"\n' "$FIXTURE_FLOOR"
EOF
cat >"$mock_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "view" && "$3" == "--json" ]] || {
  printf 'unexpected npm invocation: %s\n' "$*" >&2
  exit 29
}
printf '%s\n' "$FIXTURE_NPM_JSON"
EOF
chmod +x "$mock_bin/gh-axi" "$mock_bin/npm"
export FIXTURE_FLOOR FIXTURE_NPM_JSON
run_helper --firstmate-commit "$floor_commit" "$floor_pin_key" "$floor_new" >/dev/null
unset FIXTURE_FLOOR FIXTURE_NPM_JSON
recorded="$(jq -r --arg dependency "$floor_tool" \
  '[.exceptions[] | select(.dependency == $dependency)
    | [.previous_version, .adopted_version, .required_version, .firstmate_commit]
    | join(" ")] | join(",")' "$fixture/security/firstmate-floor-exceptions.json")"
[[ "$recorded" == "$floor_old $floor_new $floor_new $floor_commit" ]] ||
  helper_error "exception record is wrong: $recorded"

printf '%s\n' 'agent tool pin update helper checks passed'
