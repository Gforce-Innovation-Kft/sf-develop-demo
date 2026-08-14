# Salesforce Org-Based DevOps — Design

**Status:** Approved design / implementation blueprint
**Date:** 2026-08-13
**Scope:** Org-based development model only. 2GP source-based model is explicitly out of scope
and deferred to a later spec.
**Cloud posture:** GitHub-native for Phases 0–7. Google Cloud (Workload Identity Federation,
Secret Manager, Cloud Storage) is designed but deferred to Phase 8.

---

## 1. Objective

Build a reproducible, auditable deployment pipeline that promotes Salesforce metadata from git
to two long-lived orgs through immutable artifacts, containerized tooling, environment-scoped
credentials, and durable artifact retention — with no paid compute and no long-lived cloud
credentials.

The pipeline must demonstrate, in a form a reviewer can read from the repository itself:
source control, immutable artifacts, reproducible builds, containerized tooling, environment
isolation, JWT authentication, full and delta deployments, metadata transformation, automated
testing, static analysis, deployment traceability, promotion gates, rollback, artifact
retention, and auditability.

---

## 2. Decisions

Five decisions were settled during design. They constrain everything below.

| #   | Decision                                                                                        | Consequence                                                                                                                                                                       |
| --- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | **Promote one artifact per environment, transformed per environment.**                          | Each env gets its own zip; promotion identity is the source commit, not a shared checksum.                                                                                        |
| D2  | **Env-variant _config_ is baked in at convert time; env-variant _secrets_ are not.**            | The stored artifact is secret-free. Secrets are applied by a separate post-deploy step.                                                                                           |
| D3  | **The stored artifact is the deployed artifact, byte for byte.**                                | Build converts to MDAPI format and freezes; deploy consumes `--metadata-dir` and never regenerates source.                                                                        |
| D4  | **Delta base is per environment, tracked by a `deployed/<env>` git tag.**                       | An org that skips a release catches up automatically on its next deploy.                                                                                                          |
| D5  | **Credentials live in GitHub Environment secrets; artifacts live in GitHub Actions artifacts.** | No cloud billing account is required to run the pipeline. Rollback window is capped by GitHub's artifact retention. Google Cloud becomes a Phase 8 extension, not a prerequisite. |

### 2.1 Why D2 and D3 need each other

Salesforce string replacement ([SFDX docs][repl]) fires when **source format is converted to
metadata format**. The documentation states two facts that together force this design:

> You can't use string replacements with `project deploy start --metadata-dir`.

> The changes that result from string replacement are never written to your project source;
> they apply only to the deployed or packaged files.

Replacements are honored by `sf project deploy start` (source-format), `sf package version
create`, and `sf project convert source` **only when `SF_APPLY_REPLACEMENTS_ON_CONVERT=true`**.

Therefore: deploying a stored zip (`--metadata-dir`) and using replacements are mutually
exclusive _unless_ the conversion is done explicitly with that environment variable set. That
explicit convert is what lets the artifact be frozen before deployment while still carrying
environment-specific values.

[repl]: https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_string_replace.htm

### 2.2 What D5 costs

GitHub Actions artifact retention is **90 days by default**; a repository may configure
**1–90 days for public repositories** and **1–400 days for private/internal repositories**.
Retention can also be set per upload via `actions/upload-artifact`'s `retention-days` input.

Consequences, stated plainly:

- **The rollback window equals the retention window.** On a public repository that is at most
  90 days. Redeploying an artifact older than that is not possible until Phase 8 adds Cloud
  Storage, where the lifecycle rule is 365 days.
- **Artifacts are repository-scoped.** There is no cross-repository or out-of-band audit copy
  until Phase 8.
- **Immutability is by convention, not by IAM.** GCS `objectCreator` would make overwriting an
  existing artifact impossible at the permission layer; GitHub artifacts have no equivalent
  control. The pipeline's deterministic artifact naming and checksum verification are what
  stand in for it.

These are acceptable for Phases 0–7 because the pipeline's correctness does not depend on them
— only its retention horizon does.

### 2.3 Rejected alternatives

- **One byte-identical artifact for all envs, env config applied post-deploy.** Cleaner
  checksum story, but pushes Named Credential endpoints and org-specific config into a second
  deployment, splitting one logical change across two units.
- **Quick Deploy validation IDs as the promotion unit.** A validation ID is bound to the org
  that produced it; it cannot cross from integration to production. Quick Deploy remains
  usable _within_ an environment but cannot be the promotion mechanism.
- **Bake secrets into the artifact and encrypt at rest.** Requires a KMS; not free, and D2
  removes the need entirely.
- **Fixed delta base pair per release.** Produces provably identical component sets across
  envs, but an org that skips a release silently never receives the missing components.
- **Google Cloud from Phase 2.** Rejected as a starting point because Always Free access
  requires a Cloud Billing account, and the Free Trial deletes resources after a 90-day plus
  30-day grace period unless upgraded. The GCP design is retained in full as Phase 8.

---

## 3. Repository split

Implementation is distributed across three existing repositories. No new repository is created.

| Repository              | Owns                                                             | Rationale                                                                                     |
| ----------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `sf-docker-images`      | The pinned runtime image `sf-ci`                                 | Already exists, multi-arch, test-gated, digest-pinned                                         |
| `shared-github-actions` | L1 capability actions, L2 reusable workflows, `infra/terraform/` | ADR 0002 establishes L1–L4; this infrastructure is org-wide and reusable by any consumer repo |
| `sf-develop-demo`       | L4 thin caller workflows, `config/environments/`, docs           | Consumer repo                                                                                 |

**Invariant:** no `sf` CLI invocation appears in `sf-develop-demo`. Any step that shells out to
the Salesforce CLI belongs in an L1 action in `shared-github-actions`. This is what keeps the
consumer repo thin and the capability layer reusable.

**Layer rules** (inherited from `shared-github-actions/docs/adr/0002-naming-and-repo-structure.md`):
L1 never calls L1. L3 inlines no Salesforce logic. No pass-through layer that forwards inputs
unchanged. Nesting caps at 4.

---

## 4. Environment model

Two long-lived Salesforce orgs, two GitHub Environments, plus the existing Dev Hub for
scratch-org-based PR validation.

| GitHub Environment | Salesforce org                         | Trigger                         | Approval          | Delta base tag         |
| ------------------ | -------------------------------------- | ------------------------------- | ----------------- | ---------------------- |
| —                  | `gabor_dev` (Dev Hub)                  | PR → `main`                     | none              | n/a (scratch org)      |
| `integration`      | `DEMO-INTEGRATION` (Developer Edition) | push → `main`                   | none              | `deployed/integration` |
| `production`       | `DEMO-PROD` (Developer Edition)        | `workflow_dispatch` or tag `v*` | required reviewer | `deployed/production`  |

Both target orgs are Developer Edition signups, deliberately not sandboxes. The demo proves the
CI/CD architecture, not Salesforce sandbox lifecycle management.

**Repository visibility is a real decision here**, because it trades two things against each
other:

|                              | Public repo | Private repo on GitHub Free | Private repo on Pro/Team |
| ---------------------------- | ----------- | --------------------------- | ------------------------ |
| Environment protection rules | ✅ free     | ❌ unavailable              | ✅                       |
| Max artifact retention       | 90 days     | 400 days                    | 400 days                 |

A public repository is recommended: it makes the work reviewable as a portfolio piece and
gives the `production` approval gate for free. The 90-day rollback ceiling is the price, and
Phase 8 removes it.

---

## 5. Phase 0 — manual prerequisites

Everything in this section is done by hand, once, before any pipeline code runs. Nothing later
in this spec works until Phase 0 is complete and verified.

**No cloud provider account is required.** Salesforce orgs and GitHub are the only external
dependencies.

### 5.1 Salesforce orgs

#### 5.1.1 Sign up the two target orgs

Sign up at <https://developer.salesforce.com/signup>. Use plus-addressing so both orgs reach
the same inbox:

| Org                | Signup email                                   | Purpose                           |
| ------------------ | ---------------------------------------------- | --------------------------------- |
| `DEMO-INTEGRATION` | `gabor.demeter+demo-int@gforceinnovation.com`  | integration deployment target     |
| `DEMO-PROD`        | `gabor.demeter+demo-prod@gforceinnovation.com` | production-like deployment target |

Plus-addressing requires the mail provider behind `gforceinnovation.com` to support it (Google
Workspace and Microsoft 365 both do). If a signup is rejected, fall back to distinct addresses
or aliases — nothing downstream depends on the address shape.

Record the resulting **username** for each (it is not the signup email — it looks like
`gabor.demeter+demo-int@gforceinnovation.com` only if you chose it, otherwise Salesforce
generates one). Retrieve it from Setup → Users.

The Dev Hub (`gabor_dev`) already exists. Verify Dev Hub is enabled:
Setup → Dev Hub → _Enable Dev Hub_ is on.

#### 5.1.2 Generate a JWT key pair per org

Do this three times — once for `devhub`, once for `integration`, once for `production`.

```bash
ENV=integration          # repeat for: devhub, production
mkdir -p ~/.sf-jwt/$ENV && cd ~/.sf-jwt/$ENV

openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "/C=ES/ST=Malaga/L=Malaga/O=Gforce Innovation Kft/CN=sf-devops-$ENV"
openssl x509 -req -sha256 -days 730 -in server.csr -signkey server.key -out server.crt

# macOS base64 — single line, no wrapping
base64 -i server.key | tr -d '\n' > server.key.b64

chmod 600 server.key server.key.b64
```

`server.crt` is uploaded to the Connected App. `server.key.b64` becomes the `SF_JWT_KEY_B64`
GitHub Environment secret. `server.key` never leaves your machine.

#### 5.1.3 Create the Connected App in each org

In each org (Dev Hub, `DEMO-INTEGRATION`, `DEMO-PROD`):

1. Setup → **App Manager** → _New Connected App_ → choose the classic Connected App form
   (not External Client App).
2. **Basic Information**
   - Connected App Name: `SF DevOps CI <ENV>`
   - Contact Email: your email
3. **API (Enable OAuth Settings)**
   - ✅ Enable OAuth Settings
   - Callback URL: `http://localhost:1717/OauthRedirect`
     _(unused by the JWT bearer flow, but the form requires a value)_
   - ✅ **Use digital signatures** → upload `server.crt`
   - Selected OAuth Scopes:
     - `Manage user data via APIs (api)`
     - `Perform requests at any time (refresh_token, offline_access)`
     - `Manage user data via Web browsers (web)`
4. **Save.**

> **Wait 2–10 minutes before the first login attempt.** Connected App changes propagate
> asynchronously. A `JWT_AUTH_ERROR` / `invalid_client_id` immediately after saving is expected
> and is not a misconfiguration.

5. Reopen the app → **Manage** → _Edit Policies_
   - Permitted Users: **Admin approved users are pre-authorized**
   - IP Relaxation: **Relax IP restrictions**
   - Save.
6. Still under **Manage** → _Manage Profiles_ → add **System Administrator**
   (or _Manage Permission Sets_ → a dedicated `SF_DevOps_CI` permission set assigned to the
   integration user).

   This step is mandatory. With "Admin approved users are pre-authorized" and no profile or
   permission set assigned, every JWT login fails with `user hasn't approved this consumer`.

7. **View** the app → copy the **Consumer Key**. This is `SF_CLIENT_ID`.

#### 5.1.4 Verify JWT login locally — before touching CI

```bash
sf org login jwt \
  --username "<the org username>" \
  --jwt-key-file ~/.sf-jwt/integration/server.key \
  --client-id "<consumer key>" \
  --instance-url "https://login.salesforce.com" \
  --alias demo-integration

sf org display --target-org demo-integration
```

> **`INSTANCE_URL` means the _login_ URL, not the My Domain URL.**
> Use `https://login.salesforce.com` for Developer Edition and production orgs, and
> `https://test.salesforce.com` for sandboxes. This is the JWT audience claim. Passing a
> `*.my.salesforce.com` URL is the single most common cause of a failing JWT login in CI.

Repeat for `devhub` and `production`. Do not proceed until all three succeed.

#### 5.1.5 Assemble the credential payloads

For each of the three environments, write `~/.sf-jwt/<env>/payload.json`. Terraform reads these
files directly in §8; keep them local, `chmod 600`, and never in the repository.

```json
{
  "JWT_KEY_B64": "<contents of server.key.b64>",
  "USERNAME": "<org username>",
  "CLIENT_ID": "<connected app consumer key>",
  "INSTANCE_URL": "https://login.salesforce.com"
}
```

For `integration` and `production` only, add the application secrets:

```json
  "GITHUB_APP_KEY_B64": "<base64 of the GitHub App private key .pem>",
  "OWM_API_KEY":        "<OpenWeatherMap API key>"
```

### 5.2 GitHub

#### 5.2.1 Repository visibility

Decide per §4. Public is recommended. If staying private, ensure the account is on GitHub Pro,
otherwise environment protection rules — and therefore the `production` approval gate — are
unavailable.

#### 5.2.2 A token for Terraform

Terraform manages the environments and their secrets via the GitHub provider, so it needs a
token. Create a **fine-grained personal access token** scoped to `sf-develop-demo` with:

| Permission     | Access       |
| -------------- | ------------ |
| Administration | Read & write |
| Environments   | Read & write |
| Secrets        | Read & write |
| Variables      | Read & write |

Export it for the Terraform run; do not put it in a `.tfvars` file:

```bash
export GITHUB_TOKEN=github_pat_...
```

A classic PAT with the `repo` scope also works.

#### 5.2.3 Actions permissions

Settings → Actions → General → Workflow permissions: the deploy job needs `contents: write` to
push the `deployed/<env>` tag. This is granted per job in the workflow; ensure the repository
policy does not force read-only.

#### 5.2.4 Artifact retention

Settings → Actions → General → Artifact and log retention: set to the maximum your visibility
allows (90 days public, 400 private). This directly sets the rollback window per §2.2.

**Everything else about the environments — creating them, their protection rules, their
secrets and variables — is done by Terraform in §8, not by hand.**

### 5.3 Local repository

```bash
cd ~/gforce/sf-develop-demo
git submodule update --init --recursive
```

Without this, the fflib submodule directories are empty and the Apex build does not compile.

### 5.4 Phase 0 exit criteria

- [ ] `sf org login jwt` succeeds for all three orgs from a clean shell
- [ ] Connected App in each org shows Permitted Users = _Admin approved users are pre-authorized_
      with System Administrator assigned
- [ ] `~/.sf-jwt/{devhub,integration,production}/payload.json` exist and are `chmod 600`
- [ ] A fine-grained PAT with the four permissions above is exported as `GITHUB_TOKEN`
- [ ] Repository visibility decided; artifact retention set to the maximum
- [ ] `git submodule status` shows both fflib submodules checked out

---

## 6. Pipeline architecture

### 6.1 The engine — `reusable-sf-org-deploy.yml` (L2)

One reusable workflow, parameterized by environment. Two jobs; the job boundary is the artifact
boundary.

```
┌─ build ─────────────────── environment: <env> ────────────────────────────┐
│  actions/checkout  fetch-depth: 0, submodules: recursive                   │
│  load config/environments/<env>.json → $GITHUB_ENV   (non-secret only)     │
│  sf-source-delta   from: deployed/<env>   to: <release-sha>                │
│      └─ has-changes == false → mark deployed, exit clean                   │
│  sf-apex-test-select → selected test classes                               │
│  sf-artifact-build:                                                        │
│      SF_APPLY_REPLACEMENTS_ON_CONVERT=true                                 │
│      sf project convert source --manifest delta/package/package.xml        │
│                                --output-dir build/mdapi                    │
│      zip → sha256 → deployment.json          ⇐ ARTIFACT FROZEN             │
│  gitleaks scan of build/  → BLOCK on any hit                               │
│  actions/upload-artifact  retention-days: <max>                            │
└────────────────────────────────────────────────────────────────────────────┘
                             ↓  artifact only — no source, no git history
┌─ deploy ────────────────── environment: <env>  (approval fires here) ──────┐
│  actions/download-artifact                                                 │
│  sf-artifact-deploy:                                                       │
│      verify sha256 against deployment.json  → fail on mismatch             │
│      sf-org-login (credential-source: github-env)                          │
│      sf project deploy start --metadata-dir build/mdapi                    │
│                             --test-level <policy> --tests <selected>       │
│  sf-env-config-apply  → upsert secret-bearing CMDT from env secrets        │
│  smoke check                                                               │
│  git tag -f deployed/<env> <sha> && git push --force origin <tag>          │
│  finalize deployment.json → artifact + $GITHUB_STEP_SUMMARY                │
└────────────────────────────────────────────────────────────────────────────┘

concurrency:
  group: sf-org-deploy-<env>
  cancel-in-progress: false
```

**The `deploy` job runs no `actions/checkout`.** It structurally cannot regenerate the
deployment source, which is what enforces "build once, deploy the same artifact" rather than
merely documenting it.

Every job runs in `container: gforceinnovation/sf-ci:1.8.0` with `options: --user 1001`.

The `build` job declares `environment: <env>` so that it can read that environment's non-secret
variables. It reads no secrets. In Phase 8 this becomes load-bearing — see §10.

### 6.2 Deployment modes

| Mode    | Manifest source                                  | Trigger                                                        |
| ------- | ------------------------------------------------ | -------------------------------------------------------------- |
| `delta` | `sfdx-git-delta` from `deployed/<env>` to head   | default                                                        |
| `full`  | all package directories, generated `package.xml` | `workflow_dispatch` input `mode: full`; bootstrap and recovery |

Both modes produce an identical artifact shape. Only the manifest generation differs, so the
full path is exercised by the same downstream code.

### 6.3 PR validation — `ci.yml` (L4)

Calls existing `reusable-sf-pr-validate.yml` (scratch org via Dev Hub, deploy, permset, Apex
tests, Jest) and `reusable-sf-code-analyze.yml`. No deployment to a long-lived org.

---

## 7. Component inventory

### 7.1 `sf-docker-images` — `sf-ci:1.8.0`

Changes to the existing image:

- Pin `@salesforce/cli` to an exact version instead of `2.*`
- Pin `sfdx-git-delta` to an exact version
- Add Python 3 (Code Analyzer dependency)
- Add `@salesforce/plugin-code-analyzer`
- Add `gitleaks`
- Emit a machine-readable version manifest at `/opt/sf-ci/versions.json` so
  `sf-artifact-build` can embed exact tool versions in `deployment.json`

Unchanged: digest-pinned Ubuntu base, dual UID 1000/1001, XDG data dir handling, multi-arch.

### 7.2 `shared-github-actions` — L1 actions

| Action                | Status     | Key inputs                                                                                                              | Key outputs                                                              |
| --------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `sf-org-login`        | **extend** | `credential-source: aws \| github-env` (new); with `github-env`: `jwt-key-b64`, `username`, `client-id`, `instance-url` | unchanged: `org-id`, `username`, `instance-url`, `access-token`          |
| `sf-source-delta`     | reuse      | `from-ref`, `to-ref`, `source-dir`                                                                                      | `package-path`, `has-changes`, `component-count`                         |
| `sf-apex-test-select` | reuse      | `package-xml`, `source-dir`                                                                                             | `tests`, `test-count`, `has-apex`                                        |
| `sf-artifact-build`   | **new**    | `manifest-path`, `mode`, `environment`, `output-dir`                                                                    | `artifact-path`, `artifact-sha256`, `manifest-sha256`, `component-count` |
| `sf-artifact-deploy`  | **new**    | `artifact-path`, `expected-sha256`, `org-alias`, `test-level`, `tests`                                                  | `deploy-id`, `status`, `tests-run`, `coverage`                           |
| `sf-env-config-apply` | **new**    | `environment`, `config-dir`, `org-alias`                                                                                | `records-applied`                                                        |

Deferred to Phase 8: `gcp-secret-get`, `gcs-artifact-upload`, and a `credential-source: gcp`
branch on `sf-org-login`. The `credential-source` input is introduced in Phase 3 precisely so
that adding `gcp` later is an additive change with no caller churn.

The existing `aws-secret-get` action and the `aws` credential source remain in
`shared-github-actions` for other consumers. This pipeline does not use them.

### 7.3 `shared-github-actions` — L2 workflows

| Workflow                       | Status  | Change                                                                                                                                                                                    |
| ------------------------------ | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reusable-sf-org-deploy.yml`   | **new** | The engine in §6.1                                                                                                                                                                        |
| `reusable-sf-code-analyze.yml` | **fix** | Currently `runs-on: ubuntu-latest` with `setup-node`/`setup-java`/`setup-python`. Move into `container: sf-ci:1.8.0` and drop the setup steps — the image is the source of tool versions. |
| `reusable-sf-pr-validate.yml`  | reuse   | Add `credential-source` passthrough                                                                                                                                                       |

### 7.4 `sf-develop-demo` — L4

| File                                                    | Action                                                                                  |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`                              | **new** — PR gate; calls `reusable-sf-pr-validate.yml` + `reusable-sf-code-analyze.yml` |
| `.github/workflows/org-deploy-integration.yml`          | **new** — push `main` → `reusable-sf-org-deploy.yml` with `environment: integration`    |
| `.github/workflows/org-deploy-production.yml`           | **new** — tag `v*` / dispatch → same, `environment: production`                         |
| `.github/workflows/org-rollback.yml`                    | **new** — Phase 7; redeploy a prior artifact by run id                                  |
| `.github/workflows/feature-validation.yml`              | **delete** — fully superseded                                                           |
| `.github/workflows/test-aws-secrets.yml`                | **delete** — AWS is out of scope                                                        |
| `config/environments/integration.json`                  | **new** — non-secret replacement values                                                 |
| `config/environments/production.json`                   | **new** — non-secret replacement values                                                 |
| `sfdx-project.json`                                     | **modify** — extend `replacements`                                                      |
| `.github/workflows/dispatch-*.yml`, `*-runner-test.yml` | **do not touch**                                                                        |
| `github-action-service/`, `weather-app/`                | **do not touch** — Apex/LWC source is out of scope                                      |
| `fflib-apex-*/`                                         | **never touch** — read-only submodules                                                  |

Each L4 deploy workflow is roughly 20 lines: triggers, permissions, one `uses:` and its inputs.

### 7.5 Environment config and replacements

`config/environments/<env>.json` holds **non-secret** values only, and is committed:

```json
{
  "SF_NAMED_CRED_GITHUB_ENDPOINT": "https://api.github.com",
  "SF_NAMED_CRED_OWM_ENDPOINT": "https://api.openweathermap.org",
  "SF_ENV_LABEL": "DEMO-INTEGRATION"
}
```

`sfdx-project.json` `replacements` reference these via `replaceWithEnv`, with
`allowUnsetEnvVariable` left at its default `false` so a missing value fails the build rather
than silently deploying a placeholder.

The existing `GITHUB_PRIVATE_KEY_BASE64` replacement is **removed** from `replacements` per D2.
That value is a secret; it is applied post-deploy by `sf-env-config-apply`, which reads the
`GITHUB_APP_KEY_B64` environment secret and upserts the `GitHub_App_Settings__mdt` record
directly. The same applies to `OWM_API_KEY`.

---

## 8. Terraform — `shared-github-actions/infra/terraform/`

```
infra/terraform/
├── modules/
│   └── github-sf-environments/    environments, protection rules, secrets, variables
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
├── examples/
│   └── sf-develop-demo/
│       ├── main.tf
│       ├── terraform.tfvars.example
│       └── .gitignore
└── README.md
```

Phase 8 adds three sibling modules — `github-oidc`, `sf-env-secrets`, `artifact-store` — under
the same `modules/` directory. The layout anticipates them; nothing about this module needs to
change when they arrive.

### 8.1 What the module manages

Provider: `integrations/github`, authenticated from `GITHUB_TOKEN` (§5.2.2). Never a token in a
variable or `.tfvars`.

| Resource                                          | Purpose                                                               |
| ------------------------------------------------- | --------------------------------------------------------------------- |
| `github_repository_environment`                   | Creates `integration` and `production`                                |
| `github_repository_environment` → `reviewers`     | Required approver on `production` only                                |
| `github_repository_environment_deployment_policy` | Restricts `production` to `main` and tag `v*`                         |
| `github_actions_environment_secret`               | `SF_JWT_KEY_B64`, `SF_CLIENT_ID`, `GITHUB_APP_KEY_B64`, `OWM_API_KEY` |
| `github_actions_environment_variable`             | `SF_USERNAME`, `SF_INSTANCE_URL`, `SF_ENV_LABEL`                      |

Secrets versus variables is a deliberate split: key material and API keys are secrets; the org
username and login URL are operational facts that should stay readable in the Actions UI for
debugging.

### 8.2 Where the values come from

The module reads the `payload.json` files produced in §5.1.5 directly, so the runbook and the
IaC share one source of truth:

```hcl
locals {
  envs = {
    for e in var.environments :
    e => jsondecode(file("${var.credentials_dir}/${e}/payload.json"))
  }
}

resource "github_actions_environment_secret" "jwt_key" {
  for_each        = local.envs
  repository      = var.repository
  environment     = github_repository_environment.env[each.key].environment
  secret_name     = "SF_JWT_KEY_B64"
  plaintext_value = each.value.JWT_KEY_B64
}
```

> **Verify at implementation time.** The exact argument names and the
> `plaintext_value` / `encrypted_value` optionality for
> `github_actions_environment_secret` were not confirmed against the provider documentation
> during design (the Terraform Registry page is JavaScript-rendered and the provider's
> markdown source could not be retrieved). Confirm before writing the module; the design does
> not depend on which of the two is used.

### 8.3 State handling — the one real hazard

**Terraform writes every value into state, including those marked sensitive.** `sensitive = true`
suppresses console output; it does not encrypt state. A `plaintext_value` therefore lands in
`terraform.tfstate` in the clear.

Mitigations, in order of preference:

1. **Pre-encrypt.** Seal each value with the repository's public key (libsodium sealed box) and
   pass `encrypted_value` instead. State then holds only ciphertext. Costs a small helper
   script.
2. **Local state, locked down.** `terraform.tfstate` stays on the workstation, `chmod 600`, and
   `.gitignore` covers `*.tfstate*` and `*.tfvars` (excluding `*.example`). No remote backend.

Phase 8 dissolves this problem: once Secret Manager holds the credentials, Terraform manages
secret _containers_ and IAM only, and the GitHub environment secrets are no longer needed.

The example root module ships a `.gitignore` containing:

```
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
.terraform/
```

### 8.4 Outputs

`environment_names`, `production_reviewers`, `secret_names` (names only — never values).

---

## 9. Artifact and manifest

### 9.1 Artifact layout

```
artifact/
├── mdapi/                  metadata-format output of `sf project convert source`
│   ├── package.xml
│   └── <metadata folders>
├── destructiveChanges/     destructiveChangesPost.xml when the delta contains deletions
├── deployment.json         the manifest, §9.2
├── checksums.txt           sha256 of every file in the artifact
└── components.md           human-readable component table (from sf-source-delta)
```

Naming: `org-based-<env>-<mode>-<short-sha>-<run-id>`, e.g.
`org-based-production-delta-a81c921-1842`. Deterministic naming is what makes an artifact
findable for rollback without an external index.

### 9.2 `deployment.json`

Written at build time with `status: "built"`, then finalized by the deploy job.

```json
{
  "schemaVersion": "1.0",
  "repository": "Gforce-Innovation-Kft/sf-develop-demo",
  "commit": "a81c921...",
  "baseCommit": "7f2e100...",
  "branch": "main",
  "tag": "v1.4.0",
  "pullRequest": null,
  "workflow": "org-deploy-production.yml",
  "runId": "1842",
  "runUrl": "https://github.com/.../actions/runs/1842",
  "actor": "gambe94",
  "environment": "production",
  "targetOrgId": "00D...",
  "deploymentMode": "delta",
  "dockerImage": "gforceinnovation/sf-ci:1.8.0",
  "toolVersions": {
    "salesforceCli": "2.x.y",
    "sfdxGitDelta": "6.x.y",
    "codeAnalyzer": "5.x.y",
    "node": "24.x.y",
    "java": "17.x.y"
  },
  "componentCount": 12,
  "artifactSha256": "…",
  "manifestSha256": "…",
  "artifactName": "org-based-production-delta-a81c921-1842",
  "artifactRetentionDays": 90,
  "salesforceDeployId": "0Af…",
  "testLevel": "RunSpecifiedTests",
  "testsRun": ["WeatherServiceImplTest", "WeatherReportsTest"],
  "startedAt": "2026-08-13T09:14:02Z",
  "completedAt": "2026-08-13T09:21:44Z",
  "status": "success"
}
```

`manifestSha256` is the checksum of `package.xml` alone. Because it is independent of
environment-specific replacements, it is comparable across environments and answers "did
integration and production receive the same component set?".

Phase 8 adds `artifactGcsUri` to this schema; `schemaVersion` becomes `1.1`.

### 9.3 Job summary

Every deployment writes a `$GITHUB_STEP_SUMMARY` containing environment, mode, commit, actor,
image tag, the component table, validation results, Salesforce deploy ID, and a clickable link
to the run and the artifact.

---

## 10. Security model

- Secrets are never committed, never written into workflow YAML, never printed. Every secret
  consumed in a job is registered with `::add-mask::` before first use.
- Secrets do not enter the stored artifact (D2). A `gitleaks` scan of the build output runs
  before upload and blocks on any hit.
- GitHub Environment secrets are scoped per environment; the `integration` deploy job cannot
  read `production`'s credentials.
- JWT key material exists only as the `SF_JWT_KEY_B64` environment secret and as a `chmod 600`
  temporary file inside the job, removed by an `if: always()` cleanup step.
- Terraform state is the one place plaintext can accumulate — see §8.3 for the mitigations.
- No long-lived cloud credentials exist, because no cloud provider is in the loop until
  Phase 8.

**Stated limitation — build/deploy credential separation.** The `build` job needs no secrets
(it reads only non-secret variables from `config/environments/` and the environment's
variables), so ideally it would run with no secret access at all. GitHub Environment secrets
are granted to any job declaring that `environment:`, and there is no per-job scoping within an
environment. The separation is therefore by convention: the build job simply does not
reference any `secrets.*`. Splitting further would require separate environments per job
(`integration-build` / `integration-deploy`), doubling the approval surface for no real gain,
since a compromised build job could request the deploy environment anyway.

This limitation is identical in shape under Phase 8's Workload Identity Federation, where both
jobs would present the same `repo_env` OIDC claim.

---

## 11. Failure handling and rollback

Every stage fails fast; no stage that follows a failure runs.

| Stage fails                           | Result                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- |
| Static analysis                       | no artifact built                                                      |
| Delta produces no components          | clean exit, tag moved, no deployment                                   |
| Convert / replacement (unset env var) | no artifact built                                                      |
| gitleaks hit                          | artifact not uploaded, run fails                                       |
| Checksum mismatch at deploy           | no deployment                                                          |
| Salesforce deploy                     | `deployed/<env>` tag **not** moved; next run recomputes the same delta |

**Rollback** is redeployment of a prior artifact, not reconstruction from git:

```
workflow_dispatch  →  rollback-to-run: <run-id>
   → gh run download <run-id> --name org-based-<env>-*
   → verify sha256 against its deployment.json
   → deploy --metadata-dir
   → move deployed/<env> back to that commit
```

Bounded by artifact retention (§2.2): at most 90 days on a public repository. If the target
artifact has expired, the fallback is a `mode: full` deployment from the desired commit, which
is slower and re-deploys every component but is always available.

The `deployed/<env>` tag not moving on failure is the mechanism that makes retries idempotent:
a failed deployment leaves the base unchanged, so the next attempt computes an identical delta.

---

## 12. Implementation phases

| Phase | Repo                    | Delivers                                                                                                                                           | Verified by                                                                                 |
| ----- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **0** | —                       | Manual prerequisites (§5) — Salesforce orgs, Connected Apps, GitHub token                                                                          | §5.4 exit criteria                                                                          |
| **1** | `sf-docker-images`      | `sf-ci:1.8.0` — pinned CLI, Code Analyzer, Python, gitleaks, `versions.json`                                                                       | image test suite green; manifest published                                                  |
| **2** | `shared-github-actions` | `infra/terraform/modules/github-sf-environments` + example; applied                                                                                | environments exist with correct protection; secrets present; `production` requires approval |
| **3** | `shared-github-actions` | `sf-org-login` gains `credential-source: github-env`                                                                                               | login to `DEMO-INTEGRATION` from Actions; AWS path regression-tested                        |
| **4** | `shared-github-actions` | `sf-artifact-build`, `sf-artifact-deploy`, `sf-env-config-apply`                                                                                   | integration deploy from a stored artifact; checksum verified; tampered artifact rejected    |
| **5** | `shared-github-actions` | `reusable-sf-org-deploy.yml`; `reusable-sf-code-analyze.yml` containerized                                                                         | delta and full modes both deploy; tag moves only on success                                 |
| **6** | `sf-develop-demo`       | `ci.yml`, two deploy callers, `config/environments/`, `sfdx-project.json` replacements; delete `feature-validation.yml` and `test-aws-secrets.yml` | PR gate, integration deploy, gated production deploy end-to-end                             |
| **7** | both                    | `org-rollback.yml`, gitleaks gate, `docs/` + Phase 0 runbook, `pipeline-map.md` update                                                             | rollback drill restores a prior artifact                                                    |
| **8** | both                    | **Google Cloud extension** — see §13                                                                                                               | scenarios G and H in §14                                                                    |

Phases 1 and 2 are independent and may run in parallel. 3 → 4 → 5 → 6 is a hard chain.
Phase 8 is optional and additive; Phases 0–7 are a complete, working pipeline without it.

---

## 13. Phase 8 — Google Cloud extension (deferred)

Retained in full so the work is a lift-and-apply later, not a redesign. Prerequisite: a Cloud
Billing account (mandatory for Always Free access; the card authorization is a hold, not a
charge). Note that the Free Trial deletes resources after a 90-day trial plus a 30-day grace
period unless upgraded to a paid account.

**What it adds**

| Capability                                                   | Replaces                         |
| ------------------------------------------------------------ | -------------------------------- |
| Workload Identity Federation (OIDC, no service account keys) | — (new)                          |
| Secret Manager as the credential store                       | GitHub Environment secrets       |
| Cloud Storage for artifacts, 365-day lifecycle               | 90-day GitHub artifact retention |
| `objectCreator` IAM, making overwrite impossible             | naming + checksum convention     |

**Three Terraform modules** under the same `infra/terraform/modules/`:

- **`github-oidc`** — WIF pool and provider. The critical detail: a `principalSet` cannot be
  scoped by repository _and_ environment simultaneously, so the `integration` job could
  otherwise assume the `production` service account. A **composite mapped attribute** closes
  it:

  ```hcl
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
    "attribute.repo_env"    = "assertion.repository + '::' + assertion.environment"
  }

  # Fail closed: a job declaring no `environment:` emits no environment claim
  # and cannot exchange a token at all.
  attribute_condition = <<-EOT
    assertion.repository_owner == 'Gforce-Innovation-Kft' &&
    assertion.environment != ''
  EOT
  ```

  Bind with
  `principalSet://…/attribute.repo_env/Gforce-Innovation-Kft/sf-develop-demo::production`.

- **`sf-env-secrets`** — three secrets, one JSON blob per environment
  (`sf-devops-devhub`, `sf-devops-integration`, `sf-devops-production`), matching the
  `payload.json` field names already in use. Always Free allows **6 active secret versions**
  and 10,000 access operations per month; one secret per _value_ would exhaust it immediately,
  one per _environment_ uses three and leaves headroom for rotation. Terraform creates
  containers and per-secret IAM only — never `google_secret_manager_secret_version`, which
  would put plaintext in state. Versions are seeded with
  `gcloud secrets versions add … --data-file=payload.json`.

- **`artifact-store`** — GCS bucket in `US-CENTRAL1` (Always Free storage applies only to
  `us-central1`, `us-east1`, `us-west1`), uniform bucket-level access, public access
  prevention enforced, versioning on, lifecycle delete at 365 days. Deploy service accounts get
  `roles/storage.objectCreator`, **not** `objectAdmin` — `objectCreator` can create a new
  object but cannot overwrite or delete one, making immutability an enforced permission rather
  than a convention. A `google_service_usage_consumer_quota_override` caps request quota so a
  runaway loop errors instead of billing.

  Path convention:

  ```
  gs://<bucket>/org-based/<env>/<yyyy>/<mm>/<dd>/<short-sha>/<run-id>/
      artifact.zip  deployment.json  checksums.txt
      test-results.json  static-analysis.json  components.md
  ```

**Two new L1 actions:** `gcp-secret-get` (mirrors `aws-secret-get`'s contract — JSON fields
exported to `$GITHUB_ENV`, all masked) and `gcs-artifact-upload`.

**One extended action:** `sf-org-login` gains `credential-source: gcp`. Because Phase 3 already
introduced the `credential-source` input, this is additive with no caller churn.

**Manual prerequisites** at that time: create the project, link billing, enable
`iamcredentials`, `sts`, `secretmanager`, `storage`, `serviceusage`, `cloudresourcemanager`,
set a €1 budget alert, and `gcloud auth application-default login`. No service account key file
is created at any point.

---

## 14. Demonstration scenarios

| #   | Scenario                   | Path                                                                                                  | Phase |
| --- | -------------------------- | ----------------------------------------------------------------------------------------------------- | ----- |
| A   | PR validation              | PR → `main`; Jest, Code Analyzer, Prettier, scratch org deploy, Apex tests; no long-lived org touched | 6     |
| B   | Delta deployment           | change one Apex class → push `main` → delta artifact → integration                                    | 6     |
| C   | Full deployment            | `workflow_dispatch` with `mode: full` → complete artifact → integration                               | 6     |
| D   | Gated production promotion | tag `v1.4.0` → approval → delta from `deployed/production` → production                               | 6     |
| E   | Catch-up                   | production two releases behind receives a larger delta automatically                                  | 6     |
| F   | Rollback                   | dispatch `rollback-to-run` → prior artifact redeployed                                                | 7     |
| G   | Credential isolation proof | an `integration` job requesting production's credentials is denied                                    | 8     |
| H   | Immutability proof         | re-uploading an existing artifact path is rejected by `objectCreator`                                 | 8     |

Scenarios G and H are negative tests and require Phase 8's IAM controls; before that,
credential isolation rests on GitHub Environment scoping (real, but not demonstrable as a
denied API call) and immutability on convention.

---

## 15. Out of scope

- 2GP / source-based package model — deferred to a separate spec. The existing
  `reusable-sf-package-release.yml` and `sf-package-*` actions are untouched.
- The Salesforce-triggered dispatch chain (`reusable-sf-ops-dispatch.yml`,
  `dispatch-*.yml`, the Apex REST callback endpoint) — untouched.
- Salesforce Partner Business Org / Environment Hub / managed 2GP.
- Any change to Apex or LWC source under `github-action-service/` or `weather-app/`.
- AWS. `aws-secret-get` and `sf-org-login`'s `aws` credential source remain in
  `shared-github-actions` for other consumers; this pipeline does not use them.

---

## 16. Open items

| Item                                                                                                           | Owner   | Blocks  |
| -------------------------------------------------------------------------------------------------------------- | ------- | ------- |
| Repository visibility — public (free protection rules, 90-day retention) vs private on Pro (400-day retention) | Gabor   | Phase 2 |
| Exact `@salesforce/cli` version to pin in `sf-ci:1.8.0`                                                        | Phase 1 | Phase 1 |
| `github_actions_environment_secret` argument schema and `plaintext_value` vs `encrypted_value`                 | Phase 2 | Phase 2 |
| Whether the Dev Hub credential also moves to a GitHub Environment, or stays on the existing auth-URL secret    | Phase 3 | Phase 3 |

"GVT" in the source requirements is read as JWT throughout; the existing implementation is the
JWT bearer flow and no other mechanism was found in the repositories.
