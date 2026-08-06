#!/usr/bin/env bash
#
# Resolve and verify this project's Salesforce org.
#
# The host's ~/.sf is bind-mounted, so credentials are inherited rather than
# created. This script cannot log you in — it can only tell you, precisely, that
# you need to, instead of leaving a shell that looks fine and silently cannot
# deploy.
set -euo pipefail

SF_DIR="${HOME}/.sf"

if [ ! -d "$SF_DIR" ]; then
  echo "Error: ${SF_DIR} is not mounted. Check the 'mounts' entry in devcontainer.json."
  exit 1
fi

# .sf/ is gitignored, so a fresh clone has no target-org. Fall back to the
# alias committed in devcontainer.json.
target="$(sf config get target-org --json 2>/dev/null \
  | jq -r '.result[0].value // empty' || true)"

if [ -z "$target" ]; then
  target="${SF_DEFAULT_ORG_ALIAS:-}"
  if [ -z "$target" ]; then
    echo "No target-org set and SF_DEFAULT_ORG_ALIAS is empty. Set one with:"
    echo "    sf config set target-org <alias>"
    exit 1
  fi
  echo "No target-org configured; defaulting to '${target}'."
  sf config set target-org "$target"
fi

if sf org display --target-org "$target" >/dev/null 2>&1; then
  echo "✅ Salesforce org '${target}' is authorized and set as target-org."
  sf org display --target-org "$target" | head -n 12
else
  cat <<EOF
❌ Org '${target}' is NOT authorized in the mounted ~/.sf.

Credentials are shared with your host, so log in ONCE on the host (or here —
either persists to both):

    sf org login web --alias ${target} --set-default

Then reopen the container, or just re-run:

    .devcontainer/post-create.sh
EOF
  exit 1
fi
