#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECK_SCRIPT="$DOTFILES_DIR/scripts/check-homebrew-current.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${BREW_TEST_STDOUT:-}"
printf '%s' "${BREW_TEST_STDERR:-}" >&2
exit "${BREW_TEST_STATUS:-0}"
EOF
chmod +x "$TEST_DIR/brew"

run_check() {
  PATH="$TEST_DIR:$PATH" "$CHECK_SCRIPT" 2>&1
}

BREW_TEST_STDERR='continuation.bundle: warning: callcc is obsolete'
export BREW_TEST_STDERR
if output="$(run_check)"; then
  [[ -z "$output" ]] || {
    printf 'error: successful warning-only check produced output: %s\n' "$output" >&2
    exit 1
  }
else
  printf '%s\n' 'error: a warning on stderr was treated as an outdated package' >&2
  exit 1
fi

BREW_TEST_STDOUT=$'sqlite\nvips\n'
BREW_TEST_STDERR=''
export BREW_TEST_STDOUT BREW_TEST_STDERR
if output="$(run_check)"; then
  printf '%s\n' 'error: outdated packages were not detected' >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 1 && "$output" == 'Homebrew packages remain outdated: sqlite vips' ]] || {
  printf 'error: unexpected outdated-package result (%s): %s\n' "$status" "$output" >&2
  exit 1
}

BREW_TEST_STDOUT=''
BREW_TEST_STDERR='repository unavailable'
BREW_TEST_STATUS=7
export BREW_TEST_STDOUT BREW_TEST_STDERR BREW_TEST_STATUS
if output="$(run_check)"; then
  printf '%s\n' 'error: brew failure was not detected' >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 2 && "$output" == 'Homebrew could not check for outdated packages: repository unavailable' ]] || {
  printf 'error: unexpected brew-failure result (%s): %s\n' "$status" "$output" >&2
  exit 1
}

printf '%s\n' 'Homebrew current-check tests passed'
