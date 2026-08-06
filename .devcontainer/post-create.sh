#!/usr/bin/env bash
#
# Resolve and verify this project's Salesforce org.
#
# ~/.sf and ~/.sfdx are named Docker volumes (not a host bind mount), so auth
# performed inside this container persists across rebuilds but starts empty on
# a brand-new volume. This script cannot log you in — it can only tell you,
# precisely, that you need to, instead of leaving a shell that looks fine and
# silently cannot deploy.
set -euo pipefail

# .sf/ is gitignored, so a fresh clone/volume has no target-org. Fall back to
# the alias committed in devcontainer.json.
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
❌ Org '${target}' is NOT authorized in this container.

Auth now lives in a named Docker volume, isolated from your host's ~/.sf —
log in from INSIDE this container (a host login won't be visible here):

    sf org login web --alias ${target} --set-default

Or non-interactively, using an auth URL obtained on any machine already
logged in (sf org display --target-org ${target} --verbose --json | jq -r .result.sfdxAuthUrl):

    echo "\$SF_AUTH_URL" | sf org login sfdx-url --sfdx-url-stdin --alias ${target} --set-default

It persists across rebuilds after that — no need to repeat it. Then re-run:

    .devcontainer/post-create.sh
EOF
  exit 1
fi
