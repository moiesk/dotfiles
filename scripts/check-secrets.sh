#!/usr/bin/env bash
# Conservative repository-only checks for common credential mistakes.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$DOTFILES_DIR"

BAD_PATHS="$(find . -path './.git' -prune -o -path './.lavish' -prune -o -type f \
  \( -name 'auth.json' -o -name 'credentials.json' -o -name '*.pem' -o -name '*.key' -o -name '*.sock' -o -name '*.log' \) \
  -print)"
if [[ -n "$BAD_PATHS" ]]; then
  printf 'sensitive-looking paths found:\n%s\n' "$BAD_PATHS" >&2
  exit 1
fi

# Each pattern is a separate -e so inline flags (e.g. (?i)) stay scoped to it.
# Working-tree scan only; history is covered by GitHub-native scanning post-flip
# and a clean baseline pre-flip. This is the dependency-free supplementary layer
# for non-provider secrets GitHub's native scanning misses (see issue #24 / #10).
if rg -n --hidden \
  --glob '!.git/**' --glob '!.lavish/**' \
  -e '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -e 'xox[baprs]-[0-9A-Za-z-]{10,}' \
  -e '"private_key"\s*:\s*"-----BEGIN' \
  -e '[Bb]earer\s+[A-Za-z0-9._-]{20,}' \
  -e '(?i)(secret|token|passwd|password|api[_-]?key)\s*=\s*['"'"'"]?[A-Za-z0-9/+_-]{16,}' \
  .; then
  printf '%s\n' 'credential-like content found; inspect the matches above' >&2
  exit 1
fi

printf '%s\n' 'secret checks passed'
