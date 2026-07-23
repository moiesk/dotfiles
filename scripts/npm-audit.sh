#!/usr/bin/env bash
# Fail on every production advisory except an explicit, unexpired exception.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXCEPTIONS_FILE="$DOTFILES_DIR/security/npm-audit-exceptions.json"

if [[ "$#" -eq 0 ]]; then
  set -- "$DOTFILES_DIR/agent-tools" "$DOTFILES_DIR/home/.config/opencode"
fi

today="$(date -u +%F)"
if command -v mise >/dev/null 2>&1; then
  npm_command=(mise exec -- npm)
else
  npm_command=(npm)
fi

for project_dir in "$@"; do
  project_name="$(jq -er '.name' "$project_dir/package.json")"
  audit_json=""
  if ! audit_json="$(
    "${npm_command[@]}" audit \
      --prefix "$project_dir" \
      --omit=dev \
      --audit-level=low \
      --json
  )"; then
    : # npm reports discovered vulnerabilities with a non-zero status.
  fi

  if ! jq -e '.auditReportVersion == 2' <<<"$audit_json" >/dev/null; then
    printf 'error: npm returned an invalid audit report for %s\n' "$project_dir" >&2
    exit 1
  fi

  advisory_ids="$(
    jq -r '
      [
        .vulnerabilities[]?.via[]?
        | select(type == "object")
        | .url
        | capture("(?<id>GHSA-[^/]+)$").id
      ]
      | unique[]
    ' <<<"$audit_json"
  )"

  if [[ -z "$advisory_ids" ]]; then
    if jq -e '.metadata.vulnerabilities.total == 0' <<<"$audit_json" >/dev/null; then
      printf 'npm audit passed: %s\n' "$project_dir"
      continue
    fi
    printf 'error: npm reported vulnerabilities without advisory IDs for %s\n' \
      "$project_dir" >&2
    exit 1
  fi

  while IFS= read -r advisory_id; do
    if ! jq -e --arg id "$advisory_id" --arg project "$project_name" \
      'has($id) and (.[$id].projects | index($project) != null)' \
      "$EXCEPTIONS_FILE" >/dev/null; then
      printf 'error: unapproved npm advisory in %s (%s): %s\n' \
        "$project_dir" "$project_name" "$advisory_id" >&2
      exit 1
    fi

    expires="$(jq -r --arg id "$advisory_id" '.[$id].expires' "$EXCEPTIONS_FILE")"
    if [[ "$expires" < "$today" ]]; then
      printf 'error: npm advisory exception expired in %s: %s (%s)\n' \
        "$project_dir" "$advisory_id" "$expires" >&2
      exit 1
    fi

    printf 'npm audit exception: %s through %s (%s)\n' \
      "$advisory_id" "$expires" "$project_dir"
  done <<<"$advisory_ids"
done
