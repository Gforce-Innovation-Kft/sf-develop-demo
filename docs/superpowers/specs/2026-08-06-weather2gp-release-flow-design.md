# weather2GP Release Flow — Design

**Date:** 2026-08-06
**Repos:** `Gforce-Innovation-Kft/sf-develop-demo` (consumer), `Gforce-Innovation-Kft/shared-github-actions` (provider)
**Status:** implemented and verified end-to-end (run 31055115905 → `04tgL000000M3YjQAK`, `pkg/weather-app/0.1.0.3`)

## Problem

`weather-app` is an unlocked 2GP package with a declared dependency chain, built by hand from a
laptop. There was no automated path from "commit lands on `main`" to "a package version exists,
tagged, with an install command someone can copy".

`shared-github-actions` had `sf-package-create` but nothing orchestrating it, and no scratch-org
action — `sf-pr-validate.yml` inlined its own org creation.

## Goals

1. On push to `main` (and on demand), produce a new `weather-app` package version.
2. Prove the source deploys and is green **before** spending scarce package-create quota.
3. Tag it, publish a manifest artifact, and cut a GitHub Release.
4. Put every repeatable part in `shared-github-actions`; the consumer passes parameters only.

## Non-goals

- Rebuilding the fflib packages. They are pinned; a separate flow bumps them.
- Install-testing the built version. It needs a second, clean scratch org — see Deferred.
- Promoting versions to `released`, or installing into any persistent org.

## Constraints that shaped the design

| Constraint | Consequence |
|---|---|
| `ActiveScratchOrgs` max **3**, `DailyScratchOrgs` max **6** | Exactly ONE scratch org per run. Both limits are checked up front because the CLI reports either as the same opaque `LIMIT_EXCEEDED`. |
| **6 validated package creates/day** | Validation runs before the build, so a broken tree costs 0 creates. `skip-validation` (500/day) is the escape hatch. |
| **2GP dependencies are not transitive** | `weather-app` declares both fflib packages in install order. |
| **`--branch` scopes dependency resolution** | Must NOT be passed by default — see Findings. |
| Composite actions cannot declare `post:` steps | Org deletion is an explicit `if: always()` step; the action documents this as a caller contract. |
| An argument-less `sf project deploy start` deploys **every** package directory | `source-dirs` scopes the deploy; otherwise `github-action-service`'s `replacements` block fails the run. |
| `weather-app` contains **zero Apex test classes** | `code-coverage: false` — coverage would compute to 0% and only cost build time. |
| `workflow_dispatch` requires the file on the default branch | Pre-merge testing needs a temporary push trigger on the feature branch. |

## Architecture

```
push to main / workflow_dispatch
        │
        ▼
┌───────────────┐   ┌───────────────┐   ┌──────────────┐
│   validate    │──▶│    package    │──▶│   release    │
│               │   │               │   │              │
│ scratch org   │   │ sf-package-   │   │ manifest     │
│ push source   │   │   create      │   │ artifact     │
│ permsets      │   │ → 04t         │   │ GH Release   │
│ Apex tests    │   │ → pkg/ tag    │   │              │
│ delete org    │   │               │   │              │
│ sf-ci         │   │ sf-ci         │   │ ubuntu-latest│
│ 1 scratch org │   │ 0 orgs        │   │ no container │
└───────────────┘   └───────────────┘   └──────────────┘
```

Job order is driven by cost. Only `validate` consumes a scratch org; `package` needs just the Dev
Hub and `release` needs no Salesforce at all, so it runs on a bare runner.

`run-validate: false` skips the org entirely when capacity is exhausted. The `package` job is
gated on `always() && (validate succeeded || validate skipped)` so skipping validation does not
cascade into skipping the build.

## Component boundaries

### `sf-scratch-org` (new composite action)

```
inputs:  definition-file, alias, duration-days (1), dev-hub-alias,
         set-default (true), wait (30)
outputs: alias, org-id, username, instance-url
```

Holds the ActiveScratchOrgs + DailyScratchOrgs preflight, the definition-file existence check, and
the JSON parse. Does not delete — the caller contract is documented in the action header.

`sf-pr-validate.yml` was refactored onto it, removing the duplicated create block and its
hardcoded `config/scratch-orgs/ci.json` (which does not exist in this repo) in favour of a
`scratch-org-definition` input.

### `sf-package-create` (existing, simplified 563 → ~310 lines)

See the Findings section. Contract: `package`, `dev-hub-alias`, `wait-minutes`, `code-coverage`,
`skip-validation`, `branch`, `installation-key`, `preflight-min-headroom`, `push-tag`,
`evidence-path` → `version-id`, `package-version-id`, `version-number`, `request-id`, `status`,
`git-tag`.

### `sf-package-release.yml` (new reusable workflow)

Inputs: `package`, `container-image`, `checkout-submodules`, `scratch-org-definition`,
`source-dirs`, `run-validate`, `test-level`, `code-coverage`, `skip-validation`, `wait-minutes`,
`create-github-release`, `retention-days`. Secret: `sfdx-auth-url`. Outputs: `version-id`,
`version-number`, `git-tag`.

### Consumer

`.github/workflows/weather2gp-release.yml` — 60 lines, parameters only.

## Findings that changed the design

**`--branch` is not a label.** `sf-package-create` passed `--branch "$GITHUB_REF_NAME"`
unconditionally. `--branch` scopes *dependency* resolution to that branch, so `weather-app` — whose
fflib dependencies resolve via `0.1.0.LATEST` — failed with:

```
NoReleaseVersionFoundForBranchError: No version number was found in Dev Hub for package id
0HogL000000421dSAA and branch feature/weather2gp-release-flow and version number 0.1.0.LATEST.
```

Any package with `.LATEST` dependencies built from a branch would hit this. `branch` is now opt-in
and empty by default; provenance is unaffected because the commit is recorded via `--tag`.

**A CLI-level failure has no `result`.** `sf package version create --json` returns
`{status, name, message}` with no `result` when it fails before creating a request. The parser read
only `result`, so this surfaced as `ended as "unknown"` with the cause hidden.

**The action was half of an abandoned bake-off.** `plans/2026-08-05-part1` specified a TypeScript
twin, a reusable workflow and a benchmark; only the composite action shipped. The 65-line workspace
digest existed to compare the two implementations byte-for-byte and was removed — in CI from a
clean checkout the commit SHA plus submodule pointers fully determine packaged content.

**Redaction solved the wrong problem.** 60 lines of regex scrubbing existed because artifacts are
downloadable; the real asymmetry is that artifacts bypass GitHub's secret masking while job logs do
not. The CLI log now stays in the log, and only Tooling records (no secrets by schema) are
artifacted.

**`inputs` is null on push.** GitHub casts both `null` and `false` to `0`, so
`inputs.run-validate != false` evaluated **false** on every push — validation would have been
silently skipped on every merge to main. Expressions are now gated on `github.event_name`.

## Failure handling

| Fails at | Creates spent | `pkg/` tag | GH Release |
|---|---|---|---|
| `validate` | **0** | — | — |
| `package` | 1 attempt | — | — |
| `release` | 1 | pushed | retry by hand |

Scratch orgs are created with `--duration-days 1`, so a runner crash that skips the `if: always()`
cleanup still self-heals within 24 hours. `concurrency` uses `cancel-in-progress: false` — a
cancelled run can orphan an org and abandon a create that already spent quota.

## Verification

End-to-end on run 31055115905: validate (org create → deploy → permsets → Apex tests → delete),
package (`04tgL000000M3YjQAK`, `0.1.0.3`, tag `pkg/weather-app/0.1.0.3`), release (manifest
artifact + GitHub Release). Static gates: `actionlint`, `shellcheck`, and the provider repo's
`npm run all` (164 tests, 100% coverage, `dist:verify`).

The `--branch` fix was proven independently against `gabor_dev`: the identical command minus
`--branch` produced `04tgL000000M3X7QAK` (`0.1.0.2`, `Status: Success`).

## Deferred

**Install verification.** Installing the built version into a clean scratch org — with the
dependency chain resolved from `SubscriberPackageVersion.Dependencies` — and running an
anonymous-Apex smoke test against the fflib wiring. It needs a second org, which the current
`ActiveScratchOrgs` budget of 3 (with long-lived orgs holding slots) does not allow. Without it,
"the version installs in a subscriber org" is unproven; a validated build only proves it compiles
in Salesforce's own build org.

Re-enable by adding an `install-test` job plus an `sf-package-install` composite action handling
dependency resolution, `--publish-wait` (a freshly built version is not immediately installable),
and skip-if-already-installed.
