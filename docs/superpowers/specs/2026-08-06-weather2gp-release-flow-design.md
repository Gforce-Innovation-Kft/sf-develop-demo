# weather2GP Release Flow — Design

**Date:** 2026-08-06
**Repos:** `Gforce-Innovation-Kft/sf-develop-demo` (consumer), `Gforce-Innovation-Kft/shared-github-actions` (provider)
**Status:** approved, ready for implementation

## Problem

`weather-app` is an unlocked 2GP package with a declared dependency chain, built by hand from a
laptop. There is no automated path from "commit lands on `main`" to "a verified package version
exists, tagged, with an install command someone can copy".

`shared-github-actions` already provides `sf-package-create` (a 563-line composite action doing
preflight, digest, create, provenance tag, evidence bundle) but nothing orchestrates it, creates
scratch orgs, or proves the resulting version actually installs.

## Goals

1. On every push to `main` (and on demand), produce a new `weather-app` package version.
2. Prove the source deploys and is green **before** spending scarce package-create quota.
3. Prove the built version **installs and runs** in a clean org, dependencies and all.
4. Tag it, publish a manifest artifact, and cut a GitHub Release that means "verified".
5. Do it as one workflow first, then split into reusable parts across the two repos.

## Non-goals

- Rebuilding the fflib packages on every run. They are pinned; a separate manual flow bumps them.
- Promoting versions to `released`, or installing into any persistent org.
- Namespaced or managed packages. These are unlocked, no namespace.

## Constraints that shaped the design

| Constraint | Consequence |
|---|---|
| Dev Hub allows **6 validated package version creates/day** | Validation runs *before* the build, so a broken tree costs 0 creates. One release = 1 create. |
| **2GP dependencies are not transitive** | `weather-app` declares both fflib packages in install order. Install must follow the same order. |
| A scratch org's auth cannot cross a job boundary without leaking its auth URL through a job output | Every job that needs an org authenticates itself. Four `sf-org-login` calls, deliberately. |
| Composite actions cannot declare a `post:` step (JS/Docker actions only) | Scratch org deletion stays an explicit `if: always()` step in the workflow; the action documents this as a caller contract. |
| A freshly created package version is not immediately installable | `sf package install --publish-wait` is mandatory, not optional. |
| `weather-app` contains **zero Apex test classes** | Verification is anonymous-Apex smoke, not a package test run. `code-coverage: false` on create. |
| A `04t` cannot be un-created; `sf-package-create` pushes its tag on success | A failed install test cannot roll anything back. The GitHub Release, not the tag, is the "verified" signal. |

## Architecture

```
push to main / workflow_dispatch
        │
        ▼
┌───────────────┐   ┌───────────────┐   ┌────────────────┐   ┌──────────────┐
│   validate    │──▶│    package    │──▶│  install-test  │──▶│   release    │
│               │   │               │   │                │   │              │
│ scratch org   │   │ sf-package-   │   │ fresh scratch  │   │ manifest     │
│ push source   │   │   create      │   │ resolve deps   │   │ artifact     │
│ permsets      │   │ → 04t         │   │ install chain  │   │ GH Release   │
│ RunLocalTests │   │ → digest      │   │ permset        │   │              │
│ delete org    │   │ → pkg/ tag    │   │ smoke Apex     │   │              │
│               │   │               │   │ delete org     │   │              │
│ sf-ci         │   │ sf-ci         │   │ sf-ci          │   │ ubuntu-latest│
│ 0 creates     │   │ 1 create      │   │ 0 creates      │   │ no container │
└───────────────┘   └───────────────┘   └────────────────┘   └──────────────┘
```

Job ordering is driven by cost: scratch orgs are effectively free, package creates are capped at
6/day. `validate` runs first so a tree that does not compile never reaches the quota-consuming
step. `release` needs no Salesforce CLI at all, so it runs on a bare runner.

### Job: `validate`

Container `gforceinnovation/sf-ci:latest`, `permissions: contents: read`.

1. `actions/checkout@v7` with `submodules: recursive` — fflib lives in submodules; without this
   the Apex build cannot compile.
2. `sf-org-login@v1` → Dev Hub, alias `devhub`, `set-default-dev-hub: true`.
3. Create scratch org from `config/project-scratch-def.json`, alias `build-check`, 1 day.
4. `sf project deploy start` — deploys **all** `packageDirectories`, fflib included.
5. Assign every `*.permissionset-meta.xml` found under the package dirs.
6. `sf apex run test --test-level RunLocalTests --code-coverage`.
7. Upload results. Delete org in `if: always()`.

Note `RunLocalTests` here exercises fflib's own test suite plus anything in
`github-action-service`; `weather-app` ships no tests of its own. This job proves *deployability*,
and the install-test job proves *weather-app behaviour*.

### Job: `package`

`needs: validate`. Container `sf-ci`, `permissions: contents: write` (tag push).

1. Checkout with `submodules: recursive` **and `fetch-depth: 0`** — the tag step needs history.
2. `sf-org-login@v1` → `devhub`.
3. `sf-package-create@v1` with:
   - `package: weather-app`
   - `code-coverage: false` — the package has no test classes, so coverage computes to 0% and
     only costs build time. Unlocked packages have no coverage gate.
   - `skip-validation: false` — stays on the 6/day validated pool intentionally.
   - `push-tag: true` → annotated `pkg/weather-app/<version>` carrying digest + provenance.
   - `preflight-min-headroom: 2` (action default) — refuses to spend the last slot.

Outputs promoted to job outputs: `version-id` (`04t`), `version-number`, `package-version-id`
(`05i`), `request-id`, `workspace-digest`, `git-tag`. All non-secret.

On failure the action writes a redacted evidence bundle; the job uploads it as an artifact.

### Job: `install-test`

`needs: package`. Container `sf-ci`, `permissions: contents: read`.

1. Checkout (needed for the smoke Apex file).
2. `sf-org-login@v1` → `devhub`.
3. Create a **fresh** scratch org, alias `install-test`, 1 day. It must be clean — the validate
   org already has the source pushed, which would mask a broken package.
4. Resolve dependencies from the Dev Hub:
   ```
   SELECT Dependencies FROM SubscriberPackageVersion WHERE Id = '<04t>'
   ```
   returns `{"ids":[{"subscriberPackageVersionId":"04t..."}, ...]}` — the flattened chain in
   install order. No hardcoded ids, no `sfdx-project.json` parsing.
5. Install each dependency, then the new version:
   ```
   sf package install --package <04t> --target-org install-test \
     --wait 20 --publish-wait 20 --no-prompt --apex-compile all --security-type AdminsOnly
   ```
   `--apex-compile all` (unlocked packages only, CLI default) recompiles all Apex in the org, so a
   version with a broken fflib dependency fails at install rather than silently.
6. Assign `Weather_Dashboard_Demo_Access`.
7. Run `scripts/smoke/weather-app-smoke.apex` via `sf apex run --file`.
8. Delete org in `if: always()`.

Before each install, `sf package installed list --json` is checked for the target
`SubscriberPackageVersionId`; already-present versions are skipped, because `sf package install`
errors on a version that is already there. This makes re-runs safe and handles the normal case
where fflib is unchanged.

### Job: `release`

`needs: [package, install-test]`, `if: always() && needs.package.result == 'success'`.
`runs-on: ubuntu-latest`, no container. `permissions: contents: write`.

1. Download the install-test artifact.
2. Build `release-manifest.json`: package, version number, `04t`, `05i`, workspace digest, commit
   SHA, tag, ordered dependency ids, install-test verdict, run URL.
3. Upload artifact `weather-app-release-<run_number>`.
4. `gh release create "$GIT_TAG"` — **gated on `needs.install-test.result == 'success'`** — with
   the install command and dependency chain in the body.
5. Write the same table to `$GITHUB_STEP_SUMMARY`.

## Data flow

Only non-secret scalars cross job boundaries. Credentials never do — each job re-authenticates
from `secrets.sfdx-auth-url`.

```
validate      → (nothing; a gate)
package       → version-id, version-number, package-version-id,
                request-id, workspace-digest, git-tag
install-test  → install-status, installed-ids (JSON array), smoke-status
release       → consumes both
```

## Failure handling

| Fails at | Creates spent | `pkg/` tag | GH Release | Cleanup |
|---|---|---|---|---|
| `validate` | **0** | — | — | build org deleted |
| `package` | 1 attempt | — | — | evidence bundle artifact |
| `install-test` | 1 | **pushed** | **none** | test org deleted, manifest `verified: false` |
| `release` | 1 | pushed | retry by hand | — |

The tag survives a failed verification deliberately. Deleting published tags to tidy up rewrites
history, which is worse than a tag pointing at a version that did not pass. **Absence of a GitHub
Release is the signal not to install a version.**

Scratch orgs are created with `--duration-days 1`, so even a hard runner crash that skips the
`if: always()` cleanup self-heals within 24 hours.

```yaml
concurrency:
  group: weather2gp-release-${{ github.ref }}
  cancel-in-progress: false
```

Never cancel in progress: a cancelled run can orphan a scratch org and abandon a package create
that has already consumed quota.

## Component boundaries

### New composite action: `sf-scratch-org`

```
inputs:  definition-file (default config/project-scratch-def.json), alias,
         duration-days (1), dev-hub-alias (devhub), set-default (true),
         wait (30), preflight-min-headroom (1)
outputs: alias, org-id, username, instance-url, expiration-date
```

Earns its place by holding three things that are easy to get wrong: the **ActiveScratchOrgs
preflight** (this project has already hit `LIMIT_EXCEEDED` during manual packaging), the
node-based JSON parse of `sf org create scratch --json`, and the definition-file default.

`sf-pr-validate.yml` hardcodes `config/scratch-orgs/ci.json`, which does not exist in
`sf-develop-demo` — hence the input, defaulting to the file this repo actually has.

**Caller contract:** the action does not delete. Composite actions cannot register `post:` steps,
so every caller must pair it with an `if: always()` delete step. Documented in the action README.

### New composite action: `sf-package-install`

```
inputs:  version-id (04t, required), target-org (required), dev-hub-alias (devhub),
         resolve-dependencies (true), installation-key, wait (20),
         publish-wait (20), apex-compile (all), security-type (AdminsOnly)
outputs: installed-ids (ordered JSON array), install-count, results-path
```

Three behaviours justify it: Dev Hub dependency resolution, `--publish-wait` handling for
freshly built versions, and skip-if-already-installed.

### Reusable workflow: `sf-package-release.yml`

`workflow_call`. Inputs: `package`, `container-image`, `checkout-submodules`,
`scratch-org-definition`, `permission-set`, `smoke-apex-file`, `code-coverage`,
`skip-validation`, `wait-minutes`, `retention-days`, `create-github-release`.
Secret: `sfdx-auth-url`. Outputs: `version-id`, `version-number`, `git-tag`, `verified`.

## Delivery

**Phase 1 — one workflow.** `sf-develop-demo/.github/workflows/weather2gp-release.yml`: four
jobs, all steps inline except `sf-org-login@v1` and `sf-package-create@v1`, which already exist.
Adds `scripts/smoke/weather-app-smoke.apex`. Extraction seams marked in comments so Phase 2 is a
lift rather than a rewrite. Ships with `workflow_dispatch` only; the `push: main` trigger is added
after a green dispatch run.

**Phase 2 — split.** In `shared-github-actions`: create `sf-scratch-org` and `sf-package-install`
actions, create `sf-package-release.yml` from the four jobs, add entries to `CLAUDE.md` under
Composite Actions and Reusable Workflows, extend `docs/consuming-sf-cicd.md`, run `npm run all`,
retag `v1`. The consumer workflow shrinks to a ~25-line caller.

## Testing

- Phase 1 is exercised via `workflow_dispatch` on this branch before `push: main` is enabled.
- Phase 2 is consumed from a branch ref before `v1` is retagged, matching repo policy.
- Budget: one end-to-end run costs 1 validated create + 2 scratch orgs, so roughly 5 full
  iterations per day against the 6/day limit.
- `shared-github-actions` gates on its existing `npm run all` (format, lint, typecheck, bundle,
  test, `dist:verify`). Composite actions have no unit-test harness in that repo; correctness is
  established by consuming them from a branch.

## Smoke test contract

`scripts/smoke/weather-app-smoke.apex` must fail loudly on a broken install. It exercises the
fflib wiring rather than merely asserting classes exist:

```apex
fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
uow.registerNew(new Weather_Report__c(City__c = 'Malaga', Report_Date_Time__c = System.now()));
uow.commitWork();
System.assert([SELECT COUNT() FROM Weather_Report__c] > 0, 'smoke: no Weather_Report__c written');
```

This catches a broken `Application` factory, a missing or wrong fflib dependency, and field-level
permission gaps in the permission set — none of which an exit-code-only install check would see.

## Open risks

1. **`--publish-wait` timeout.** A version can take longer than 20 minutes to become installable
   under Salesforce load. Mitigation: the value is an input; raise it if it proves tight.
2. **Quota exhaustion during a busy day.** Five merges to `main` in a day will exhaust the
   validated-create limit and the sixth run fails at preflight. Accepted: the preflight fails
   fast and cheap, and `force`-style overrides would defeat the protection.
3. **`sf package create` wiping `dependencies`.** Not exercised by this flow (which only creates
   *versions*), but any future automation that runs `sf package create` must re-add the block.
