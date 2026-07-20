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

if rg -n --hidden \
  --glob '!.git/**' --glob '!.lavish/**' \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})' .; then
  printf '%s\n' 'credential-like content found; inspect the matches above' >&2
  exit 1
fi

printf '%s\n' 'secret checks passed'
