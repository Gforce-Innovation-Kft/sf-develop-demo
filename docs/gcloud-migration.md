# Google Cloud migration

On 2026-11-10 GForce Google Cloud moved into a Terraform-managed landing zone
(`gforce-google-cloud`). The old projects `claude-integration-501116`, `gforce-salesforce-cicd`,
`gforce-sf-platform` and `gen-lang-client-0257489838` are shutting down, and `gforce-google-infra`
is being deleted. The shutdown leaves a 30-day undelete window.

This repo has no Google Cloud config of its own. It got its GitHub Environment secrets from
`gh-secret-sync` in `gforce-google-infra`. **Those secrets stay as they are, but nothing syncs or
rotates them any more.**

## What this repo touches

| Item                                        | Where in this repo                                              | Old source                                           | Future source                                                | Breaks at shutdown                           |
| ------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------- |
| Environment `devhub` JWT credentials        | GitHub Environment `devhub` (`verify-org-login.yml`)            | `salesforce-devhub`, synced by `gh-secret-sync`      | `gforce-shared-credentials` `salesforce-devhub-jwt`          | No. The copy stays; it is no longer rotated. |
| Environment `integration` JWT credentials   | GitHub Environment `integration` (`org-deploy-integration.yml`) | `salesforce-integration`, synced by `gh-secret-sync` | `gforce-shared-credentials` `salesforce-integration-jwt`     | No. The copy stays; it is no longer rotated. |
| Environment `production` JWT credentials    | GitHub Environment `production` (`org-deploy-production.yml`)   | `salesforce-demo-prod`, synced by `gh-secret-sync`   | `gforce-shared-credentials` `salesforce-demo-production-jwt` | No. The copy stays; it is no longer rotated. |
| GitHub App key `PRIVATE_KEY_GITHUB_BASE64`  | repo-level secret (`org-deploy-integration.yml`)                | `salesforce-github-app`, synced by `gh-secret-sync`  | `gforce-shared-credentials` `github-app-salesforce-key`      | No. The copy stays; it is no longer rotated. |
| Trust in the old Workload Identity provider | none used (workflows use `credential-source: github-env`)       | `github-provider` allowed this repo                  | none needed                                                  | No                                           |

The workflows pass the values to `sf-org-login` with `credential-source: github-env`. Nothing in
this repo calls Google Cloud.

## What this means

- Do not expect a credential change in Secret Manager to reach these Environments. Rotating a
  credential is now a manual step: update the secret in `gforce-shared-credentials`, then set the
  Environment secret by hand.
- The values in `gforce-shared-credentials` are the source of truth for what the Environments
  should hold.
- The old `verify-secrets-weekly.yml` check in `gforce-google-infra` goes away, so nothing watches
  for drift between the two.

## Checklist for a later switch

- [ ] Add a sync or a direct read from `gforce-shared-credentials`, or move to
      `credential-source: gcp` in `sf-org-login`. Both are outside this change.
- [ ] If the workflows read Google Cloud directly, set repository variable
      `GCP_WORKLOAD_IDENTITY_PROVIDER` from the `shared` output `workload_identity_provider` of
      `gforce-google-cloud`, and ask for this repo's `principalSet` grant in the `shared` root.
- [ ] Remove the "GCP-sourced replica" wording from `CLAUDE.md` once the new source is live.

Inventory: [plan-2-inventory PR](https://github.com/Gforce-Innovation-Kft/gforce-google-cloud/pull/7).
