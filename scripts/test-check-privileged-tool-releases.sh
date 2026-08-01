#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/gh-axi" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *treehouse*) tag=v2.1.0 ;;
  *no-mistakes*) tag=v1.41.2 ;;
  *) exit 1 ;;
esac
printf 'tag_name: %s\npublished_at: "2026-01-01T00:00:00Z"\n' "$tag"
EOF

cat >"$tmp_dir/npm" <<'EOF'
#!/usr/bin/env bash
package="$2"
pinned="$(jq -r --arg package "$package" '.dependencies[$package]' "$DOTFILES_DIR/agent-tools/package.json")"
if [[ "$package" == "quota-axi" ]]; then
  cat <<JSON
{
  "dist-tags": {"latest": "0.1.14"},
  "versions": ["$pinned", "0.1.13", "0.1.14"],
  "time": {
    "$pinned": "2026-07-01T00:00:00Z",
    "0.1.13": "2026-07-23T00:00:00Z",
    "0.1.14": "2026-07-31T12:00:00Z"
  }
}
JSON
else
  cat <<JSON
{
  "dist-tags": {"latest": "$pinned"},
  "versions": ["$pinned"],
  "time": {"$pinned": "2026-07-01T00:00:00Z"}
}
JSON
fi
EOF
chmod +x "$tmp_dir/gh-axi" "$tmp_dir/npm"

export DOTFILES_DIR
output_file="$tmp_dir/output"
if GH_AXI_BIN="$tmp_dir/gh-axi" \
  NPM_BIN="$tmp_dir/npm" \
  TOOL_UPDATE_NOW_EPOCH="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-01T00:00:00Z' '+%s' 2>/dev/null || date -u -d '2026-08-01T00:00:00Z' '+%s')" \
  "$DOTFILES_DIR/scripts/check-privileged-tool-releases.sh" >"$output_file" 2>&1; then
  printf '%s\n' 'error: an eligible intermediate npm release was hidden by a fresh latest release' >&2
  exit 1
fi

if ! grep -Fq \
  'error: quota-axi stable release 0.1.13 is past cooldown; pinned release is 0.1.12' \
  "$output_file"; then
  cat "$output_file" >&2
  printf '%s\n' 'error: the release check did not report the highest eligible npm release' >&2
  exit 1
fi

if [[ "$(grep -c '^[[:space:]]*interval: daily$' "$DOTFILES_DIR/.github/dependabot.yml")" -ne 2 ]]; then
  printf '%s\n' 'error: npm Dependabot checks must run daily so updates are proposed when cooldown expires' >&2
  exit 1
fi

printf '%s\n' 'privileged tool release check tests passed'
