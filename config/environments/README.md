# Environment config

**Non-secret** per-environment values, applied at convert time by the
`replacements` block in `sfdx-project.json`. One file per GitHub Environment;
the filename must match the environment name exactly, because
`reusable-sf-org-deploy.yml` reads `config/environments/<environment>.json`.

These files are committed on purpose. They are configuration, not credentials,
and having them in review is the point — a reviewer can see exactly what differs
between integration and production.

## What belongs here

Anything that varies by environment and is safe to read in a public repository:
endpoints, labels, org-identifying strings, feature flags.

## What does NOT belong here

Secrets. Ever.

The deployment artifact is uploaded and retained, and anything baked in at
convert time is retained with it. Secrets are applied **after** deployment, from
GitHub Environment secrets, so they never enter the artifact.

That split is the reason the GitHub App private key is no longer in
`sfdx-project.json`'s `replacements`: it used to be injected at convert time,
which put a live credential inside every artifact the pipeline produced.

## Adding a value

1. Add the key to **every** environment file — a missing value fails the build
   rather than deploying a placeholder, which is deliberate.
2. Add a matching entry to `replacements` in `sfdx-project.json` using
   `replaceWithEnv`.
3. Put the placeholder string in the metadata file itself.

Leave `allowUnsetEnvVariable` at its default (`false`). A missing value should
stop the pipeline, not ship a literal `PLACEHOLDER` into a Salesforce org.
