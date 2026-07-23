#!/usr/bin/env bash
# Fail on every Go advisory except an explicit, scoped, unexpired exception.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXCEPTIONS_FILE="$DOTFILES_DIR/security/go-vulnerability-exceptions.json"
GOVULNCHECK_BIN="${GOVULNCHECK_BIN:-govulncheck}"

if [[ "$#" -ne 2 ]]; then
  printf 'usage: %s <project-name> <source-directory>\n' "$0" >&2
  exit 2
fi

project_name="$1"
source_dir="$2"
report=""
scan_status=0
report="$(cd "$source_dir" && "$GOVULNCHECK_BIN" -json ./...)" || scan_status=$?

if ! jq -s -e 'length > 0 and any(has("config"))' <<<"$report" >/dev/null; then
  printf 'error: govulncheck returned an invalid report for %s\n' "$project_name" >&2
  exit 1
fi

advisory_ids="$(
  jq -s -r '[.[] | select(has("finding")) | .finding.osv] | unique[]' \
    <<<"$report"
)"
if [[ -z "$advisory_ids" ]]; then
  if ((scan_status != 0)); then
    printf 'error: govulncheck failed for %s with status %s\n' \
      "$project_name" "$scan_status" >&2
    exit 1
  fi
  printf 'govulncheck passed: %s\n' "$project_name"
  exit 0
fi

today="$(date -u +%F)"
while IFS= read -r advisory_id; do
  if ! jq -e --arg id "$advisory_id" --arg project "$project_name" \
    'has($id) and (.[$id].projects | index($project) != null)' \
    "$EXCEPTIONS_FILE" >/dev/null; then
    printf 'error: unapproved Go advisory in %s: %s\n' \
      "$project_name" "$advisory_id" >&2
    exit 1
  fi

  expires="$(jq -r --arg id "$advisory_id" '.[$id].expires' "$EXCEPTIONS_FILE")"
  if [[ "$expires" < "$today" ]]; then
    printf 'error: Go advisory exception expired in %s: %s (%s)\n' \
      "$project_name" "$advisory_id" "$expires" >&2
    exit 1
  fi

  printf 'govulncheck exception: %s through %s (%s)\n' \
    "$advisory_id" "$expires" "$project_name"
done <<<"$advisory_ids"
