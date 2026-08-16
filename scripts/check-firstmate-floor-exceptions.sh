#!/usr/bin/env bash
# Validate narrow cooldown exceptions against an immutable Firstmate commit.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
REGISTRY="${FIRSTMATE_FLOOR_REGISTRY:-$DOTFILES_DIR/scripts/firstmate-tool-floors.tsv}"
EXCEPTIONS="${FIRSTMATE_FLOOR_EXCEPTIONS_FILE:-$DOTFILES_DIR/security/firstmate-floor-exceptions.json}"
GH_AXI_BIN="${GH_AXI_BIN:-gh-axi}"
NPM_BIN="${NPM_BIN:-npm}"
COOLDOWN_DAYS="${TOOL_UPDATE_COOLDOWN_DAYS:-7}"
NOW_EPOCH="${TOOL_UPDATE_NOW_EPOCH:-$(date -u +%s)}"
FIRSTMATE_REPOSITORY='kunchenguid/firstmate'
DOTFILES_HISTORY_DIR="${FIRSTMATE_DOTFILES_HISTORY_DIR:-$DOTFILES_DIR}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check-firstmate-floor-exceptions.sh
  scripts/check-firstmate-floor-exceptions.sh --candidate <40-hex-commit>
  scripts/check-firstmate-floor-exceptions.sh --show-floor <dependency> <40-hex-commit>
  scripts/check-firstmate-floor-exceptions.sh --retire-expired

With no arguments, validate every committed cooldown exception against its exact
Firstmate commit, the committed dependency pin, and published release metadata,
and warn while a record is approaching its retirement deadline.
With --candidate, inspect that immutable Firstmate commit and report whether the
currently committed dotfiles pins meet every registered dependency floor.
With --show-floor, print one dependency floor for the pin-update helper.
With --retire-expired, delete every exception whose adopted release has since
completed the ordinary cooldown and no longer needs an exception, so the record
is retired by review rather than by a scheduled failure.
EOF
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

api_body() {
  local response="$1" body count
  grep -Fxq '  truncated: false' <<<"$response" || return 1
  count="$(grep -c '^  body: ' <<<"$response" || true)"
  [[ "$count" == 1 ]] || return 1
  body="$(sed -n 's/^  body: //p' <<<"$response")"
  node -e '
    const value = process.argv[1];
    try {
      const parsed = JSON.parse(value);
      process.stdout.write(typeof parsed === "string" ? parsed : String(parsed));
    } catch {
      process.stdout.write(value);
    }
  ' "$body"
}

semver_at_least() {
  node -e '
    const parse = value => /^\d+\.\d+\.\d+$/.test(value) ? value.split(".").map(Number) : null;
    const left = parse(process.argv[1]);
    const right = parse(process.argv[2]);
    if (!left || !right) process.exit(2);
    const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
    process.exit(compare(left, right) >= 0 ? 0 : 1);
  ' "$1" "$2"
}

floor_from_commit() {
  local commit="$1" path="$2" variable="$3" response value jq_filter
  [[ "$path" =~ ^[A-Za-z0-9._/-]+$ && "$variable" =~ ^[A-Z0-9_]+$ ]] || return 1
  jq_filter=".content | @base64d | [match(\"(?m)^${variable}=([0-9]+\\\\.[0-9]+\\\\.[0-9]+)$\"; \"g\")] | if length == 1 then .[0].captures[0].string else error(\"expected exactly one floor\") end"
  response="$($GH_AXI_BIN api GET "/repos/$FIRSTMATE_REPOSITORY/contents/$path?ref=$commit" \
    --jq "$jq_filter" 2>/dev/null)" || return 1
  value="$(api_body "$response")" || return 1
  [[ "$value" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || return 1
  printf '%s\n' "$value"
}

pinned_version() {
  local pin_kind="$1" pin_key="$2" tag_prefix="$3" ref
  case "$pin_kind" in
    npm)
      jq -er --arg dependency "$pin_key" '.dependencies[$dependency]' \
        "$DOTFILES_DIR/agent-tools/package.json"
      ;;
    flake)
      ref="$(jq -er --arg input "$pin_key" '.nodes[$input].original.ref' \
        "$DOTFILES_DIR/flake.lock")" || return 1
      [[ "$ref" == "$tag_prefix"* ]] || return 1
      printf '%s\n' "${ref#"$tag_prefix"}"
      ;;
    *) return 1 ;;
  esac
}

version_at_revision() {
  local revision="$1" pin_kind="$2" pin_key="$3" tag_prefix="$4" ref
  case "$pin_kind" in
    npm)
      git -C "$DOTFILES_HISTORY_DIR" show "$revision:agent-tools/package.json" 2>/dev/null |
        jq -er --arg dependency "$pin_key" '.dependencies[$dependency]'
      ;;
    flake)
      ref="$(git -C "$DOTFILES_HISTORY_DIR" show "$revision:flake.lock" 2>/dev/null |
        jq -er --arg input "$pin_key" '.nodes[$input].original.ref')" || return 1
      [[ "$ref" == "$tag_prefix"* ]] || return 1
      printf '%s\n' "${ref#"$tag_prefix"}"
      ;;
    *) return 1 ;;
  esac
}

historical_previous_pin() {
  local pin_kind="$1" pin_key="$2" tag_prefix="$3" adopted="$4"
  local revision value
  revision="$(git -C "$DOTFILES_HISTORY_DIR" rev-parse --verify HEAD 2>/dev/null)" || return 1
  while [[ -n "$revision" ]]; do
    value="$(version_at_revision "$revision" "$pin_kind" "$pin_key" "$tag_prefix")" || return 1
    if [[ "$value" != "$adopted" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    revision="$(git -C "$DOTFILES_HISTORY_DIR" rev-parse --verify "$revision^" 2>/dev/null || true)"
  done
  return 1
}

npm_release_evidence() {
  local dependency="$1" adopted="$2" required="$3" metadata lowest published
  metadata="$($NPM_BIN view "$dependency" --json 2>/dev/null)" || return 1
  lowest="$(node -e '
    const metadata = JSON.parse(process.argv[1]);
    const required = process.argv[2].split(".").map(Number);
    const parse = value => /^\d+\.\d+\.\d+$/.test(value) ? value.split(".").map(Number) : null;
    const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
    const matches = (metadata.versions || [])
      .map(value => ({value, parsed: parse(value)}))
      .filter(item => item.parsed
        && Number.isFinite(Date.parse(metadata.time?.[item.value]))
        && compare(item.parsed, required) >= 0)
      .sort((a, b) => compare(a.parsed, b.parsed));
    if (matches[0]) process.stdout.write(matches[0].value);
  ' "$metadata" "$required")" || return 1
  [[ -n "$lowest" ]] || return 1
  if [[ "$adopted" != "$lowest" ]]; then
    fail "$dependency exception adopted version $adopted is broader than the lowest released version $lowest satisfying floor $required"
  fi
  published="$(jq -r --arg version "$adopted" '.time[$version] // empty' <<<"$metadata")"
  [[ -n "$published" ]] || return 1
  printf '%s\n' "$published"
}

release_published_at() {
  local pin_kind="$1" release_key="$2" tag_prefix="$3" version="$4" metadata published
  case "$pin_kind" in
    npm)
      metadata="$($NPM_BIN view "$release_key" --json 2>/dev/null)" || return 1
      published="$(jq -r --arg version "$version" '.time[$version] // empty' <<<"$metadata")"
      ;;
    flake)
      [[ "$tag_prefix" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
      metadata="$($GH_AXI_BIN api GET \
        "/repos/$release_key/releases/tags/${tag_prefix}${version}" 2>/dev/null)" || return 1
      published="$(awk -F': ' '/^published_at:/ { print $2; exit }' <<<"$metadata")"
      published="${published%\"}"
      published="${published#\"}"
      ;;
    *) return 1 ;;
  esac
  [[ -n "$published" ]] || return 1
  printf '%s\n' "$published"
}

published_epoch_of() {
  node -e '
    const value = Date.parse(process.argv[1]);
    if (!Number.isFinite(value)) process.exit(1);
    console.log(Math.floor(value / 1000));
  ' "$1"
}

registry_row() {
  local dependency="$1" rows row_count
  rows="$(awk -F '\t' -v dependency="$dependency" '$1 == dependency { print }' "$REGISTRY")"
  row_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"$rows")"
  [[ "$row_count" == 1 ]] || return 1
  printf '%s\n' "$rows"
}

validate_exception_schema() {
  jq -e '
    type == "object"
    and (keys | sort) == ["exceptions", "schema_version"]
    and .schema_version == 1
    and (.exceptions | type == "array")
    and all(.exceptions[];
      type == "object"
      and (keys | sort) == [
        "adopted_version", "dependency", "firstmate_commit",
        "firstmate_repository", "previous_version", "required_version"
      ]
      and (.dependency | type == "string" and length > 0)
      and (.adopted_version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
      and (.required_version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
      and (.previous_version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))
      and .firstmate_repository == "kunchenguid/firstmate"
      and (.firstmate_commit | type == "string" and test("^[0-9a-f]{40}$"))
    )
    and (([.exceptions[].dependency] | unique | length) == (.exceptions | length))
  ' "$EXCEPTIONS" >/dev/null ||
    fail 'Firstmate floor exceptions are malformed, duplicate, or over-broad'
}

github_release_evidence() {
  local repository="$1" tag_prefix="$2" adopted="$3" required="$4"
  local metadata tag published response tags lowest
  [[ "$tag_prefix" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  response="$($GH_AXI_BIN api GET "/repos/$repository/releases?per_page=100" \
    --paginate --jq '.[].tag_name' 2>/dev/null)" || return 1
  tags="$(api_body "$response")" || return 1
  lowest="$(node -e '
    const prefix = process.argv[1];
    const required = process.argv[2].split(".").map(Number);
    const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pattern = new RegExp(`^${escape(prefix)}(\\d+)\\.(\\d+)\\.(\\d+)$`);
    const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
    const matches = process.argv[3].split("\n")
      .map(value => ({value, match: value.match(pattern)}))
      .filter(item => item.match)
      .map(item => ({value: item.value.slice(prefix.length), parts: item.match.slice(1).map(Number)}))
      .filter(item => compare(item.parts, required) >= 0)
      .sort((a, b) => compare(a.parts, b.parts));
    if (matches[0]) process.stdout.write(matches[0].value);
  ' "$tag_prefix" "$required" "$tags")" || return 1
  [[ -n "$lowest" ]] || return 1
  if [[ "$adopted" != "$lowest" ]]; then
    fail "$repository exception adopted version $adopted is broader than the lowest released version $lowest satisfying floor $required"
  fi
  tag="${tag_prefix}${adopted}"
  metadata="$($GH_AXI_BIN api GET "/repos/$repository/releases/tags/$tag" 2>/dev/null)" || return 1
  published="$(awk -F': ' '/^published_at:/ { print $2; exit }' <<<"$metadata")"
  published="${published%\"}"
  published="${published#\"}"
  [[ -n "$published" ]] || return 1
  printf '%s\n' "$published"
}

[[ "$COOLDOWN_DAYS" =~ ^[0-9]+$ ]] || fail 'TOOL_UPDATE_COOLDOWN_DAYS must be a non-negative integer'
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || fail 'TOOL_UPDATE_NOW_EPOCH must be a non-negative integer epoch'
[[ -f "$REGISTRY" ]] || fail "missing Firstmate floor registry: $REGISTRY"

if [[ "$#" == 3 && "$1" == --show-floor ]]; then
  dependency="$2"
  candidate="$3"
  [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] || fail 'candidate Firstmate commit must be an exact lowercase 40-hex SHA'
  rows="$(awk -F '\t' -v dependency="$dependency" '$1 == dependency { print }' "$REGISTRY")"
  row_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"$rows")"
  [[ "$row_count" == 1 ]] || fail "$dependency does not name a supported Firstmate dependency floor"
  IFS=$'\t' read -r _ _ _ floor_path floor_variable exception_allowed _ _ extra <<<"$rows"
  [[ -z "${extra:-}" && "$exception_allowed" == yes ]] ||
    fail "$dependency does not name a cooldown-gated Firstmate dependency floor"
  floor_from_commit "$candidate" "$floor_path" "$floor_variable" ||
    fail "could not read Firstmate floor evidence for $dependency at exact $FIRSTMATE_REPOSITORY commit $candidate"
  exit 0
fi

if [[ "$#" == 2 && "$1" == --candidate ]]; then
  candidate="$2"
  [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] || fail 'candidate Firstmate commit must be an exact lowercase 40-hex SHA'
  unmet=0
  while IFS=$'\t' read -r dependency pin_kind pin_key floor_path floor_variable _ _ tag_prefix extra; do
    [[ -z "$dependency" || "$dependency" == \#* ]] && continue
    [[ -z "${extra:-}" ]] || fail "invalid Firstmate floor registry row for $dependency"
    pinned="$(pinned_version "$pin_kind" "$pin_key" "$tag_prefix")" ||
      fail "could not read the committed $dependency pin"
    floor="$(floor_from_commit "$candidate" "$floor_path" "$floor_variable")" ||
      fail "could not read Firstmate floor evidence for $dependency at exact $FIRSTMATE_REPOSITORY commit $candidate"
    if semver_at_least "$pinned" "$floor"; then
      printf 'ok: %s pin %s satisfies Firstmate floor %s\n' "$dependency" "$pinned" "$floor"
    else
      printf 'unmet: %s pin %s is below Firstmate floor %s\n' "$dependency" "$pinned" "$floor"
      unmet=$((unmet + 1))
    fi
  done <"$REGISTRY"
  ((unmet == 0)) || exit 1
  exit 0
fi

if [[ "$#" == 1 && "$1" == --retire-expired ]]; then
  [[ -f "$EXCEPTIONS" ]] || fail "missing Firstmate floor exception record: $EXCEPTIONS"
  validate_exception_schema
  retired=()
  while IFS=$'\t' read -r dependency adopted; do
    [[ -n "$dependency" ]] || continue
    rows="$(registry_row "$dependency")" ||
      fail "$dependency exception does not name a supported Firstmate dependency floor"
    IFS=$'\t' read -r _ pin_kind pin_key _ _ _ release_repository tag_prefix _ <<<"$rows"
    case "$pin_kind" in
      npm) release_key="$pin_key" ;;
      flake) release_key="$release_repository" ;;
      *) fail "$dependency exception does not name a supported Firstmate dependency floor" ;;
    esac
    published="$(release_published_at "$pin_kind" "$release_key" "$tag_prefix" "$adopted")" ||
      fail "could not read the release publication time for $dependency $adopted"
    published_epoch="$(published_epoch_of "$published")" ||
      fail "release timestamp for $dependency $adopted is malformed"
    age_seconds=$((NOW_EPOCH - published_epoch))
    ((age_seconds < COOLDOWN_DAYS * 86400)) || retired+=("$dependency")
  done < <(jq -r '.exceptions[] | [.dependency, .adopted_version] | @tsv' "$EXCEPTIONS")

  if ((${#retired[@]} == 0)); then
    printf 'no Firstmate floor exception has completed the %s-day cooldown\n' "$COOLDOWN_DAYS"
    exit 0
  fi
  retired_json="$(printf '%s\n' "${retired[@]}" | jq -R . | jq -s .)"
  jq --argjson retired "$retired_json" \
    '.exceptions |= map(select(.dependency as $name | ($retired | index($name)) | not))' \
    "$EXCEPTIONS" >"$EXCEPTIONS.next"
  mv "$EXCEPTIONS.next" "$EXCEPTIONS"
  for dependency in "${retired[@]}"; do
    printf 'retired Firstmate floor exception: %s completed the %s-day cooldown\n' \
      "$dependency" "$COOLDOWN_DAYS"
  done
  printf 'review and commit %s, then ship the retirement.\n' "$EXCEPTIONS"
  exit 0
fi

if [[ "$#" != 0 ]]; then
  usage >&2
  exit 2
fi

[[ -f "$EXCEPTIONS" ]] || fail "missing Firstmate floor exception record: $EXCEPTIONS"

validate_exception_schema

while IFS=$'\t' read -r dependency previous adopted required repository commit; do
  [[ -n "$dependency" ]] || continue
  rows="$(registry_row "$dependency")" ||
    fail "$dependency exception does not name a supported Firstmate dependency floor"
  IFS=$'\t' read -r _ pin_kind pin_key floor_path floor_variable exception_allowed release_repository tag_prefix extra <<<"$rows"
  [[ -z "${extra:-}" && "$exception_allowed" == yes ]] ||
    fail "$dependency exception does not name a cooldown-gated Firstmate dependency floor"

  pinned="$(pinned_version "$pin_kind" "$pin_key" "$tag_prefix")" ||
    fail "could not read the committed $dependency pin"
  [[ "$pinned" == "$adopted" ]] ||
    fail "$dependency exception adopted version $adopted does not match committed pin $pinned"
  if ! semver_at_least "$adopted" "$required"; then
    fail "$dependency adopted version $adopted does not satisfy required version $required"
  fi

  actual_floor="$(floor_from_commit "$commit" "$floor_path" "$floor_variable")" ||
    fail "could not read Firstmate floor evidence for $dependency at exact $FIRSTMATE_REPOSITORY commit $commit"
  [[ "$actual_floor" == "$required" ]] ||
    fail "Firstmate commit $commit declares $dependency floor $actual_floor, not recorded required version $required"

  if semver_at_least "$previous" "$required"; then
    fail "$dependency exception is unrelated because previous pin $previous already satisfied required version $required"
  fi
  historical_previous="$(historical_previous_pin "$pin_kind" "$pin_key" "$tag_prefix" "$adopted")" ||
    fail "could not establish the historical $dependency pin preceding adopted version $adopted"
  [[ "$previous" == "$historical_previous" ]] ||
    fail "$dependency exception previous version $previous does not match historical pin $historical_previous"

  case "$pin_kind" in
    npm)
      published="$(npm_release_evidence "$dependency" "$adopted" "$required")" ||
        fail "could not verify npm release evidence for $dependency $adopted"
      ;;
    flake)
      published="$(github_release_evidence "$release_repository" "$tag_prefix" "$adopted" "$required")" ||
        fail "could not verify GitHub release evidence for $dependency $adopted"
      ;;
  esac
  published_epoch="$(published_epoch_of "$published")" ||
    fail "release timestamp for $dependency $adopted is malformed"
  age_seconds=$((NOW_EPOCH - published_epoch))
  ((age_seconds >= 0)) || fail "$dependency $adopted has a future release timestamp"
  ((age_seconds < COOLDOWN_DAYS * 86400)) ||
    fail "$dependency exception is stale because adopted version $adopted has completed the ${COOLDOWN_DAYS}-day cooldown; retire it with scripts/check-firstmate-floor-exceptions.sh --retire-expired"

  remaining_hours=$(((COOLDOWN_DAYS * 86400 - age_seconds) / 3600))
  printf 'valid Firstmate floor exception: %s %s requires %s at %s (retire in %sh)\n' \
    "$dependency" "$adopted" "$required" "$commit" "$remaining_hours"
  if ((remaining_hours < 48)); then
    printf 'warning: the %s floor exception expires in %sh; retire it with scripts/check-firstmate-floor-exceptions.sh --retire-expired\n' \
      "$dependency" "$remaining_hours" >&2
  fi
done < <(jq -r '.exceptions[] | [
  .dependency, .previous_version, .adopted_version, .required_version,
  .firstmate_repository, .firstmate_commit
] | @tsv' "$EXCEPTIONS")
