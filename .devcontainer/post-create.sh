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

# A configured target-org is NOT evidence that the org is usable here. The
# workspace is bind-mounted, so a host-side .sf/config.json shows up as sf's
# *Local* config and outranks the Global config in the container's named
# volume — meaning `sf config get target-org` happily returns an alias that
# was only ever authorized on the host. Resolve, then verify, then fall back.
target="$(sf config get target-org --json 2>/dev/null \
  | jq -r '.result[0].value // empty' || true)"

if [ -n "$target" ] && ! sf org display --target-org "$target" >/dev/null 2>&1; then
  echo "target-org '${target}' is configured but not authorized in this container."
  target=""
fi

if [ -z "$target" ]; then
  target="${SF_DEFAULT_ORG_ALIAS:-}"
  if [ -z "$target" ]; then
    echo "No usable target-org and SF_DEFAULT_ORG_ALIAS is empty. Set one with:"
    echo "    sf config set target-org <alias>"
    exit 1
  fi
  echo "Falling back to '${target}'."
fi

if sf org display --target-org "$target" >/dev/null 2>&1; then
  # Only pin the alias once it is known good, and pin it globally so this
  # never writes back into the host's bind-mounted project .sf/config.json.
  sf config set target-org "$target" --global >/dev/null
  echo "✅ Salesforce org '${target}' is authorized and set as target-org."
  sf org display --target-org "$target" | head -n 12
else
  cat <<EOF
❌ Org '${target}' is NOT authorized in this container.

Auth now lives in a named Docker volume, isolated from your host's ~/.sf —
log in from INSIDE this container (a host login won't be visible here):

    sf org login web --alias ${target}

Or non-interactively, from an auth URL obtained on a machine already logged
in. Note 'sf org display --verbose' now REDACTS the URL; use:

    sf org auth show-sfdx-auth-url -o ${target}

then, in this container, paste it into a file and consume it:

    sf org login sfdx-url --sfdx-url-file /tmp/u.txt --alias ${target} && rm -f /tmp/u.txt

Omit --set-default in both: this script pins the alias globally once it
verifies, which avoids writing into the bind-mounted /workspace/.sf.

It persists across rebuilds after that — no need to repeat it. Then re-run:

    .devcontainer/post-create.sh
EOF
  exit 1
fi
