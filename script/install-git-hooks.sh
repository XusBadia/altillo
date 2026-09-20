#!/usr/bin/env bash
# Installs a pre-commit hook that refuses to commit secrets (needs `brew install gitleaks`).
set -euo pipefail
root=$(git rev-parse --show-toplevel)
hook="$root/.git/hooks/pre-commit"

cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "pre-commit: gitleaks no está instalado (brew install gitleaks); me lo salto." >&2
  exit 0
fi
if ! gitleaks protect --staged --no-banner --redact; then
  echo "pre-commit: parece que hay un secreto en lo que vas a commitear. Sácalo del commit." >&2
  exit 1
fi
HOOK

chmod +x "$hook"
echo "Hook instalado en $hook"
