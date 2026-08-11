#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$DOTFILES_DIR"

for script in bootstrap.sh rebuild.sh scripts/*.sh; do
  bash -n "$script"
done

for apply_script in bootstrap.sh rebuild.sh; do
  if ! rg -Fq '"$DOTFILES_DIR/scripts/update-homebrew.sh"' "$apply_script"; then
    printf 'error: %s must refresh the locked Homebrew source before activation\n' \
      "$apply_script" >&2
    exit 1
  fi
done

if ! rg -Fq 'nix flake update brew-src --flake "$DOTFILES_DIR"' scripts/update-homebrew.sh; then
  printf '%s\n' 'error: the Homebrew updater must advance only the brew-src input' >&2
  exit 1
fi

if ! rg -Uq 'brew-src = \{\n[[:space:]]+url = "github:Homebrew/brew";\n[[:space:]]+flake = false;' flake.nix; then
  printf '%s\n' 'error: brew-src must directly track Homebrew so its DSL can roll independently' >&2
  exit 1
fi

if ! rg -Fq 'nix-homebrew.inputs.brew-src.follows = "brew-src";' flake.nix; then
  printf '%s\n' 'error: nix-homebrew must use the independently updated brew-src input' >&2
  exit 1
fi

jq -e '
  to_entries
  | all(
      .key | test("^GHSA-[a-z0-9-]+$")
    ) and all(
      .value.expires | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
    ) and all(
      (.value.projects | type == "array" and length > 0) and
      (.value.reason | length > 0) and
      (.value.compensatingControl | length > 0)
    )
' security/npm-audit-exceptions.json >/dev/null

jq -e '
  to_entries
  | all(
      .key | test("^GO-[0-9]{4}-[0-9]+$")
    ) and all(
      .value.expires | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
    ) and all(
      (.value.projects | type == "array" and length > 0) and
      (.value.reason | length > 0) and
      (.value.compensatingControl | length > 0)
    )
' security/go-vulnerability-exceptions.json >/dev/null

if rg -n '^[[:space:]]*npm[[:space:]]' bootstrap.sh rebuild.sh scripts/*.sh; then
  printf '%s\n' 'error: scripted npm calls must run through mise exec' >&2
  exit 1
fi

for install_script in bootstrap.sh rebuild.sh scripts/*.sh; do
  [[ "$install_script" == "scripts/validate.sh" ]] && continue
  # Pi is a deliberately rolling first-party harness (decisions #34/#36): its
  # single sanctioned `@latest` install in post-switch.sh is exempt. Every other
  # agent tool must still use an exact version and a locked local install.
  if rg -n '@latest|npm install[^#]*--global|bun add[^#]*--global' \
    "$install_script" | rg -v '@earendil-works/pi-coding-agent@latest'; then
    printf '%s\n' 'error: agent tools must use exact versions and locked local installs' >&2
    exit 1
  fi
done

for json_file in \
  agent-tools/package.json \
  agent-tools/package-lock.json \
  home/.claude/settings.portable.json \
  home/.config/opencode/package.json \
  home/.config/opencode/package-lock.json; do
  jq empty "$json_file"
done

for npm_project in agent-tools home/.config/opencode; do
  if ! jq -e \
    '(.packages[""].dependencies // {}) == (. as $lock | input.dependencies)' \
    "$npm_project/package-lock.json" "$npm_project/package.json" >/dev/null; then
    printf 'error: %s/package.json does not match its lockfile\n' "$npm_project" >&2
    exit 1
  fi

  if jq -e \
    '[.dependencies // {} | to_entries[] | select(.value | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not)] | length > 0' \
    "$npm_project/package.json" >/dev/null; then
    printf 'error: %s contains a non-exact npm dependency version\n' "$npm_project/package.json" >&2
    exit 1
  fi
done

if jq -e '.dependencies | has("@earendil-works/pi-coding-agent")' \
  agent-tools/package.json >/dev/null ||
  jq -e '.packages[""].dependencies | has("@earendil-works/pi-coding-agent")' \
    agent-tools/package-lock.json >/dev/null; then
  printf '%s\n' 'error: rolling Pi must remain outside committed npm manifests' >&2
  exit 1
fi

npm_security_workflow=".github/workflows/npm-security.yml"
# Each entry is "<required occurrences>|<literal line>".
for count_and_line in \
  '2|echo "AGENT_TOOLS_PREFIX=$RUNNER_TEMP/agent-tools" >> "$GITHUB_ENV"' \
  '2|cp package.json package-lock.json .npmrc "$AGENT_TOOLS_PREFIX/"' \
  '2|(cd "$AGENT_TOOLS_PREFIX" && npm ci)' \
  '2|npm install --prefix "$AGENT_TOOLS_PREFIX" @earendil-works/pi-coding-agent@latest' \
  '1|"$GITHUB_WORKSPACE/scripts/npm-audit.sh" "$audit_prefix"' \
  '1|npm audit signatures --prefix "$audit_prefix"'; do
  required_count="${count_and_line%%|*}"
  required_line="${count_and_line#*|}"
  actual_count="$(rg -Fc -- "$required_line" "$npm_security_workflow" || true)"
  if [[ "${actual_count:-0}" -lt "$required_count" ]]; then
    printf 'error: npm security CI needs %s occurrence(s) of full-tree step (found %s): %s\n' \
      "$required_count" "${actual_count:-0}" "$required_line" >&2
    exit 1
  fi
done

if rg -Fq -- 'npm ci --prefix' "$npm_security_workflow"; then
  printf '%s\n' 'error: npm security CI must not use `npm ci --prefix`; npm rejects it, so the isolated install must run from inside $AGENT_TOOLS_PREFIX' >&2
  exit 1
fi

if rg -Fq -- 'runner.temp' "$npm_security_workflow"; then
  printf '%s\n' 'error: npm security CI must not use the runner.temp context; job-level env cannot resolve it, so the prefix must come from $RUNNER_TEMP via $GITHUB_ENV' >&2
  exit 1
fi

for input_package_prefix in \
  'chrome-devtools-axi chrome-devtools-axi chrome-devtools-axi-v' \
  'gh-axi gh-axi gh-axi-v' \
  'lavish-axi lavish-axi lavish-axi-v' \
  'quota-axi quota-axi quota-axi-v' \
  'tasks-axi tasks-axi tasks-axi-v'; do
  read -r flake_input npm_package tag_prefix <<<"$input_package_prefix"
  npm_version="$(jq -er --arg package "$npm_package" \
    '.dependencies[$package]' agent-tools/package.json)"
  flake_ref="$(jq -er --arg input "$flake_input" \
    '.nodes[$input].original.ref' flake.lock)"
  if [[ "$flake_ref" != "${tag_prefix}${npm_version}" ]]; then
    printf 'error: %s npm version %s does not match flake ref %s\n' \
      "$npm_package" "$npm_version" "$flake_ref" >&2
    exit 1
  fi

  trust_row="$(rg -F -- "https://github.com/kunchenguid/${npm_package})" TRUST.md || true)"
  if [[ "$(printf '%s' "$trust_row" | rg -c '' || true)" != "1" ]]; then
    printf 'error: TRUST.md must contain exactly one inventory row for %s\n' \
      "$npm_package" >&2
    exit 1
  fi
  for trust_pin in "${tag_prefix}${npm_version}" "${npm_package}@${npm_version}"; do
    if ! printf '%s' "$trust_row" | rg -Fq -- "$trust_pin"; then
      printf 'error: TRUST.md row for %s does not document the current pin %s\n' \
        "$npm_package" "$trust_pin" >&2
      exit 1
    fi
  done
done

no_mistakes_version="$(sed -nE \
  's/^[[:space:]]*noMistakesVersion = "([^"]+)";/\1/p' home.nix)"
no_mistakes_ref="$(jq -er '.nodes["no-mistakes"].original.ref' flake.lock)"
if [[ "$no_mistakes_ref" != "v${no_mistakes_version}" ]]; then
  printf 'error: no-mistakes build version %s does not match flake ref %s\n' \
    "$no_mistakes_version" "$no_mistakes_ref" >&2
  exit 1
fi

if ! jq -e 'has("model") or has("effortLevel") | not' \
  home/.claude/settings.portable.json >/dev/null; then
  printf '%s\n' 'error: Claude portable settings contain machine-local model or effort' >&2
  exit 1
fi

if rg -n '^(model|model_reasoning_effort)[[:space:]]*=|^\[projects(?:\.|\])' \
  home/.codex/config.defaults.toml; then
  printf '%s\n' 'error: Codex portable defaults contain machine-local settings' >&2
  exit 1
fi

for mutable_config in \
  home/.claude/settings.json \
  home/.codex/config.toml \
  home/.pi/agent/settings.json \
  home/.pi/agent/models.json; do
  if [[ -e "$mutable_config" ]]; then
    printf 'error: mutable agent config is stored in the repository: %s\n' "$mutable_config" >&2
    exit 1
  fi
done

"$DOTFILES_DIR/scripts/test-materialize-agent-configs.sh"
"$DOTFILES_DIR/scripts/test-check-homebrew-current.sh"
"$DOTFILES_DIR/scripts/test-check-privileged-tool-releases.sh"

"$DOTFILES_DIR/scripts/check-secrets.sh"

if command -v nix >/dev/null 2>&1; then
  nix flake check "$DOTFILES_DIR" --no-build
else
  printf '%s\n' 'warning: Nix is not installed; skipped flake evaluation' >&2
fi

printf '%s\n' 'static validation passed'
