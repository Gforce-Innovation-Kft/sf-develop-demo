# Salesforce Org-Based DevOps — Design

**Status:** Approved design / implementation blueprint
**Date:** 2026-08-13
**Scope:** Org-based development model only. 2GP source-based model is explicitly out of scope
and deferred to a later spec.

---

## 1. Objective

Build a reproducible, auditable deployment pipeline that promotes Salesforce metadata from git
to two long-lived orgs through immutable artifacts, containerized tooling, environment-scoped
credentials held in Google Secret Manager, and durable artifact retention in Google Cloud
Storage — with no AWS, no paid compute, and no long-lived cloud credentials.

The pipeline must demonstrate, in a form a reviewer can read from the repository itself:
source control, immutable artifacts, reproducible builds, containerized tooling, environment
isolation, JWT authentication, full and delta deployments, metadata transformation, automated
testing, static analysis, deployment traceability, promotion gates, rollback, artifact
retention, and auditability.

---

## 2. Decisions

Four decisions were settled during design. They constrain everything below.

| #   | Decision                                                                             | Consequence                                                                                                                                      |
| --- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | **Promote one artifact per environment, transformed per environment.**               | Each env gets its own zip; promotion identity is the source commit, not a shared checksum.                                                       |
| D2  | **Env-variant _config_ is baked in at convert time; env-variant _secrets_ are not.** | The stored artifact is secret-free and may be uploaded to GCS. Secrets are applied by a separate post-deploy step reading Google Secret Manager. |
| D3  | **The stored artifact is the deployed artifact, byte for byte.**                     | Build converts to MDAPI format and freezes; deploy consumes `--metadata-dir` and never regenerates source.                                       |
| D4  | **Delta base is per environment, tracked by a `deployed/<env>` git tag.**            | An org that skips a release catches up automatically on its next deploy.                                                                         |

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

### 2.2 Rejected alternatives

- **One byte-identical artifact for all envs, env config applied post-deploy.** Cleaner
  checksum story, but pushes Named Credential endpoints and org-specific config into a second
  deployment, splitting one logical change across two units.
- **Quick Deploy validation IDs as the promotion unit.** A validation ID is bound to the org
  that produced it; it cannot cross from integration to production. Quick Deploy remains
  usable _within_ an environment but cannot be the promotion mechanism.
- **Bake secrets into the artifact and encrypt for GCS.** Requires GCP KMS, which is not in the
  Always Free tier, and violates the project's no-paid-services constraint.
- **Fixed delta base pair per release.** Produces provably identical component sets across
  envs, but an org that skips a release silently never receives the missing components.

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

GitHub Environments require a **public repository, or GitHub Pro/Team/Enterprise** for
protection rules on a private repository. The `production` approval gate depends on this.

---

## 5. Phase 0 — manual prerequisites

Everything in this section is done by hand, once, before any pipeline code runs. Nothing later
in this spec works until Phase 0 is complete and verified.

### 5.1 Salesforce orgs

#### 5.1.1 Sign up the two target orgs

Sign up at <https://developer.salesforce.com/signup>. Use plus-addressing so both orgs reach
the same inbox:

| Org                | Signup email                         | Purpose                           |
| ------------------ | ------------------------------------ | --------------------------------- |
| `DEMO-INTEGRATION` | `demetergabor94+demo-int@gmail.com`  | integration deployment target     |
| `DEMO-PROD`        | `demetergabor94+demo-prod@gmail.com` | production-like deployment target |

Record the resulting **username** for each (it is not the signup email — it looks like
`demetergabor94+demo-int@gmail.com` only if you chose it, otherwise Salesforce generates one).
Retrieve it from Setup → Users.

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

`server.crt` is uploaded to the Connected App. `server.key.b64` becomes the `JWT_KEY_B64` field
in that environment's Secret Manager payload. `server.key` never leaves your machine.

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

7. **View** the app → copy the **Consumer Key**. This is `CLIENT_ID`.

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

#### 5.1.5 Record the credential payloads

For each of the three environments, assemble the JSON that will be seeded into Secret Manager
in §5.2.5. Keep it in a local scratch file, never in the repository:

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

### 5.2 Google Cloud

#### 5.2.1 Project and billing

```bash
gcloud projects create gforce-sf-devops --name="GForce SF DevOps"
gcloud config set project gforce-sf-devops
gcloud billing projects link gforce-sf-devops --billing-account=<BILLING_ACCOUNT_ID>
```

A billing account must be attached even for Always Free usage. Attaching it does not incur
charges while usage stays within the free allowances.

#### 5.2.2 Enable APIs

```bash
gcloud services enable \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com
```

#### 5.2.3 Budget alert

Independent of the quota override applied by Terraform in §8.3, set a low budget alert as a
second line of defence:

Billing → Budgets & alerts → Create budget → scope to `gforce-sf-devops`, amount **€1**,
alert thresholds at 50% / 90% / 100%.

#### 5.2.4 Terraform credentials

For this demo, Terraform runs locally against your own identity:

```bash
gcloud auth application-default login
```

No service account key file is created at any point.

#### 5.2.5 Seed the secret versions

Run **after** `terraform apply` has created the secret containers (§8.2). Terraform
deliberately does not manage secret versions — a `google_secret_manager_secret_version`
resource with a real value writes that plaintext into `terraform.tfstate`.

```bash
for ENV in devhub integration production; do
  gcloud secrets versions add "sf-devops-$ENV" \
    --data-file="$HOME/.sf-jwt/$ENV/payload.json"
done
```

Verify, and confirm exactly one active version per secret:

```bash
gcloud secrets versions list sf-devops-integration
```

### 5.3 GitHub

1. **Repository visibility**: make `sf-develop-demo` public, or ensure the account is on
   GitHub Pro. Environment protection rules on a private repository require a paid plan.
2. **Create environments** — Settings → Environments:
   - `integration` — no protection rules.
   - `production` — ✅ Required reviewers (yourself); Deployment branches: **Selected
     branches and tags** → `main` and `v*`.
3. **Environment variables** per environment (Variables, not Secrets — none of these are
   sensitive):

   | Variable                         | Example                                                                          |
   | -------------------------------- | -------------------------------------------------------------------------------- |
   | `GCP_PROJECT_ID`                 | `gforce-sf-devops`                                                               |
   | `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/123.../locations/global/workloadIdentityPools/github/providers/github` |
   | `GCP_SERVICE_ACCOUNT`            | `sf-devops-integration@gforce-sf-devops.iam.gserviceaccount.com`                 |
   | `SF_SECRET_NAME`                 | `sf-devops-integration`                                                          |
   | `GCS_ARTIFACT_BUCKET`            | `gforce-sf-devops-artifacts-<project-number>`                                    |

   The provider path, service account email and bucket name are Terraform outputs from §8.

4. **Actions permissions** — Settings → Actions → General → Workflow permissions: the deploy
   job needs `contents: write` to push the `deployed/<env>` tag. This is granted per-job in
   the workflow; ensure the repository policy does not force read-only.

### 5.4 Local repository

```bash
cd ~/gforce/sf-develop-demo
git submodule update --init --recursive
```

Without this, the fflib submodule directories are empty and the Apex build does not compile.

### 5.5 Phase 0 exit criteria

- [ ] `sf org login jwt` succeeds for all three orgs from a clean shell
- [ ] Connected App in each org shows Permitted Users = _Admin approved users are pre-authorized_
      with System Administrator assigned
- [ ] `gcloud secrets versions list` shows exactly one active version for each of the three secrets
- [ ] GitHub environments `integration` and `production` exist, with `production` gated
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
│  google-github-actions/auth (WIF/OIDC)  → GCS write scope only             │
│  sf-source-delta   from: deployed/<env>   to: <release-sha>                │
│      └─ has-changes == false → mark deployed, exit clean                   │
│  sf-apex-test-select → selected test classes                               │
│  sf-artifact-build:                                                        │
│      SF_APPLY_REPLACEMENTS_ON_CONVERT=true                                 │
│      sf project convert source --manifest delta/package/package.xml        │
│                                --output-dir build/mdapi                    │
│      zip → sha256 → deployment.json          ⇐ ARTIFACT FROZEN             │
│  gitleaks scan of build/  → BLOCK on any hit                               │
│  upload: actions/upload-artifact + gcs-artifact-upload                     │
└────────────────────────────────────────────────────────────────────────────┘
                             ↓  artifact only — no source, no git history
┌─ deploy ────────────────── environment: <env>  (approval fires here) ──────┐
│  actions/download-artifact                                                 │
│  sf-artifact-deploy:                                                       │
│      verify sha256 against deployment.json  → fail on mismatch             │
│      sf-org-login (credential-source: gcp)                                 │
│      sf project deploy start --metadata-dir build/mdapi                    │
│                             --test-level <policy> --tests <selected>       │
│  sf-env-config-apply  → upsert secret-bearing CMDT from Secret Manager     │
│  smoke check                                                               │
│  git tag -f deployed/<env> <sha> && git push --force origin <tag>          │
│  finalize deployment.json → GCS + $GITHUB_STEP_SUMMARY                     │
└────────────────────────────────────────────────────────────────────────────┘

concurrency:
  group: sf-org-deploy-<env>
  cancel-in-progress: false
```

**The `deploy` job runs no `actions/checkout`.** It structurally cannot regenerate the
deployment source, which is what enforces "build once, deploy the same artifact" rather than
merely documenting it.

Every job runs in `container: gforceinnovation/sf-ci:1.8.0` with `options: --user 1001`.

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

| Action                | Status     | Key inputs                                                                                                                    | Key outputs                                                              |
| --------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `sf-org-login`        | **extend** | `credential-source: aws\|gcp` (new), `gcp-project-id`, `gcp-workload-identity-provider`, `gcp-service-account`, `secret-name` | unchanged: `org-id`, `username`, `instance-url`, `access-token`          |
| `sf-source-delta`     | reuse      | `from-ref`, `to-ref`, `source-dir`                                                                                            | `package-path`, `has-changes`, `component-count`                         |
| `sf-apex-test-select` | reuse      | `package-xml`, `source-dir`                                                                                                   | `tests`, `test-count`, `has-apex`                                        |
| `gcp-secret-get`      | **new**    | `project-id`, `secret-name`, `workload-identity-provider`, `service-account`, `export-env`                                    | secret JSON fields exported to `$GITHUB_ENV`, all masked                 |
| `sf-artifact-build`   | **new**    | `manifest-path`, `mode`, `environment`, `output-dir`                                                                          | `artifact-path`, `artifact-sha256`, `manifest-sha256`, `component-count` |
| `sf-artifact-deploy`  | **new**    | `artifact-path`, `expected-sha256`, `org-alias`, `test-level`, `tests`                                                        | `deploy-id`, `status`, `tests-run`, `coverage`                           |
| `sf-env-config-apply` | **new**    | `environment`, `config-dir`, `org-alias`                                                                                      | `records-applied`                                                        |
| `gcs-artifact-upload` | **new**    | `bucket`, `prefix`, `source-dir`, `workload-identity-provider`, `service-account`                                             | `gcs-uri`                                                                |

`gcp-secret-get` mirrors `aws-secret-get`'s contract exactly — JSON fields exported as
environment variables, referenced as `${{ env.FIELD }}` — so `sf-org-login`'s JWT branch is
unchanged apart from which credential-fetch step runs.

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
| `.github/workflows/feature-validation.yml`              | **delete** — fully superseded                                                           |
| `.github/workflows/test-aws-secrets.yml`                | **delete** — AWS is out of scope                                                        |
| `config/environments/integration.json`                  | **new** — non-secret replacement values                                                 |
| `config/environments/production.json`                   | **new** — non-secret replacement values                                                 |
| `sfdx-project.json`                                     | **modify** — extend `replacements`                                                      |
| `.github/workflows/dispatch-*.yml`, `*-runner-test.yml` | **do not touch**                                                                        |
| `github-action-service/`, `weather-app/`                | **do not touch** — Apex/LWC source is out of scope                                      |
| `fflib-apex-*/`                                         | **never touch** — read-only submodules                                                  |

Each L4 workflow is roughly 20 lines: triggers, permissions, one `uses:` and its inputs.

### 7.5 Environment config and replacements

`config/environments/<env>.json` holds **non-secret** values only:

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
That value is a secret; it is applied post-deploy by `sf-env-config-apply`, which reads
`GITHUB_APP_KEY_B64` from Secret Manager and upserts the `GitHub_App_Settings__mdt` record
directly. The same applies to `OWM_API_KEY`.

---

## 8. Terraform — `shared-github-actions/infra/terraform/`

```
infra/terraform/
├── modules/
│   ├── github-oidc/          WIF pool + provider + per-env SA + repo::env bindings
│   ├── sf-env-secrets/       Secret Manager containers + scoped accessor IAM
│   └── artifact-store/       GCS bucket + lifecycle + quota override
├── examples/
│   └── sf-develop-demo/      root module wiring all three
│       ├── main.tf
│       ├── terraform.tfvars.example
│       └── backend.tf.example
└── README.md
```

Three modules rather than one: a consumer repo that needs only artifact storage should not be
forced to instantiate a secrets module.

State is local and gitignored for the demo. `backend.tf.example` contains a commented GCS
backend block; a state bucket fits within the same 5 GB Always Free allowance.

### 8.1 `github-oidc`

A `principalSet` cannot be scoped by repository _and_ environment simultaneously. Without
additional work, the `integration` job could assume the `production` service account. A
**composite mapped attribute** closes this:

```hcl
attribute_mapping = {
  "google.subject"        = "assertion.sub"
  "attribute.repository"  = "assertion.repository"
  "attribute.environment" = "assertion.environment"
  "attribute.repo_env"    = "assertion.repository + '::' + assertion.environment"
}

# Fail closed: a job that declares no `environment:` emits no environment claim,
# so it cannot satisfy this condition and cannot exchange a token at all.
attribute_condition = <<-EOT
  assertion.repository_owner == 'Gforce-Innovation-Kft' &&
  assertion.environment != ''
EOT
```

```hcl
resource "google_service_account_iam_member" "wif" {
  for_each           = var.environments
  service_account_id = google_service_account.env[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member = join("", [
    "principalSet://iam.googleapis.com/", local.pool_name,
    "/attribute.repo_env/", var.repository, "::", each.key,
  ])
}
```

No service account keys are created. The client side is `permissions: id-token: write` plus
`google-github-actions/auth` with the provider path and service account email.

**Outputs:** `workload_identity_provider`, `service_account_emails` (map keyed by env),
`pool_name`.

### 8.2 `sf-env-secrets`

Google Secret Manager's Always Free tier allows **6 active secret versions**. One secret per
value would exhaust it immediately. One JSON blob per environment uses three, leaving headroom
for rotation, which briefly doubles a secret's active version count.

| Secret                  | Fields                                                 |
| ----------------------- | ------------------------------------------------------ |
| `sf-devops-devhub`      | `JWT_KEY_B64`, `USERNAME`, `CLIENT_ID`, `INSTANCE_URL` |
| `sf-devops-integration` | above + `GITHUB_APP_KEY_B64`, `OWM_API_KEY`            |
| `sf-devops-production`  | above + `GITHUB_APP_KEY_B64`, `OWM_API_KEY`            |

Field names match the existing AWS payload, so `sf-org-login`'s JWT branch needs no change
beyond which fetch step populates the environment.

The module creates `google_secret_manager_secret` containers and IAM bindings only. It
**never** creates `google_secret_manager_secret_version` — that resource would place plaintext
credentials in `terraform.tfstate`. Versions are seeded out-of-band per §5.2.5.

IAM is granted per secret, not per project:

```hcl
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = var.environments
  secret_id = google_secret_manager_secret.env[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_emails[each.key]}"
}
```

The `integration` service account cannot read `sf-devops-production` even if a workflow asks.

**Outputs:** `secret_names` (map keyed by env).

### 8.3 `artifact-store`

```hcl
location                    = "US-CENTRAL1"   # Always Free region
storage_class               = "STANDARD"
uniform_bucket_level_access = true
public_access_prevention    = "enforced"
versioning { enabled = true }

lifecycle_rule { condition { age = 365 }                          action { type = "Delete" } }
lifecycle_rule { condition { days_since_noncurrent_time = 30 }    action { type = "Delete" } }
lifecycle_rule { condition { age = 7 } action { type = "AbortIncompleteMultipartUpload" } }
```

**Immutability is enforced by IAM, not convention.** Deploy service accounts are granted
`roles/storage.objectCreator`, **not** `objectAdmin`. `objectCreator` permits creating a new
object but not overwriting or deleting an existing one, so a re-run cannot silently mutate a
stored artifact.

Path convention:

```
gs://<bucket>/org-based/<env>/<yyyy>/<mm>/<dd>/<short-sha>/<run-id>/
    artifact.zip
    deployment.json
    checksums.txt
    test-results.json
    static-analysis.json
    components.md
```

Budget safeguard: a `google_service_usage_consumer_quota_override` caps
`storage.googleapis.com` request quota, so a runaway loop produces a quota error rather than a
bill.

Sizing against Always Free (5 GB-months, 5,000 Class A, 50,000 Class B per month): roughly six
objects and a few MB per deployment leaves headroom for approximately 800 deployments per
month.

**Outputs:** `bucket_name`, `bucket_url`.

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
`org-based-production-delta-a81c921-1842`.

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
  "artifactGcsUri": "gs://…/artifact.zip",
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

### 9.3 Job summary

Every deployment writes a `$GITHUB_STEP_SUMMARY` containing environment, mode, commit, actor,
image tag, the component table, validation results, Salesforce deploy ID, and clickable links
to the run and the GCS artifact path.

---

## 10. Security model

- No long-lived cloud credentials. GCP access is OIDC + Workload Identity Federation only.
- Secrets are never committed, never written into workflow YAML, never printed. Every field
  read from Secret Manager is registered with `::add-mask::` before first use.
- Secrets do not enter the stored artifact (D2). A `gitleaks` scan of the build output runs
  before any upload and blocks on any hit.
- Secret Manager IAM is per-secret and per-environment.
- Terraform state contains no secret values.
- JWT key material exists only as `JWT_KEY_B64` in Secret Manager and as a
  `chmod 600` temporary file inside the job, removed by an `if: always()` cleanup step.
- Deploy service accounts hold `objectCreator` on GCS, so a compromised job cannot destroy the
  artifact history it would need to falsify.

**Stated limitation — build/deploy credential separation.** The `build` job needs no Secret
Manager access (it reads only non-secret config from `config/environments/`), so ideally it
would assume a storage-only service account. This is **not achievable** with the environment
claim alone: both jobs declare the same `environment:`, so both present an identical
`repo_env` assertion and either could assume either service account. GitHub's OIDC token
carries no job-level claim to discriminate on. The design therefore uses **one service account
per environment**, and the separation is by convention — the build job simply does not call
`gcp-secret-get`. Splitting further would require separate GitHub Environments per job
(e.g. `integration-build` / `integration-deploy`), which would double the approval surface for
no real gain, since a compromised build job in the same environment could request the deploy
environment's token anyway.

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
workflow_dispatch  →  rollback-to: <short-sha>
   → fetch gs://…/<env>/…/<sha>/artifact.zip
   → verify sha256 against its deployment.json
   → deploy --metadata-dir
   → move deployed/<env> back to that sha
```

The `deployed/<env>` tag not moving on failure is the mechanism that makes retries idempotent:
a failed deployment leaves the base unchanged, so the next attempt computes an identical delta.

---

## 12. Implementation phases

| Phase | Repo                    | Delivers                                                                                                                                           | Verified by                                                                                     |
| ----- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| **0** | —                       | Manual prerequisites (§5)                                                                                                                          | §5.5 exit criteria                                                                              |
| **1** | `sf-docker-images`      | `sf-ci:1.8.0` — pinned CLI, Code Analyzer, Python, gitleaks, `versions.json`                                                                       | image test suite green; manifest published                                                      |
| **2** | `shared-github-actions` | `infra/terraform/` three modules + example; applied; secrets seeded                                                                                | a throwaway workflow reads one secret via OIDC and fails when it targets the other env's secret |
| **3** | `shared-github-actions` | `gcp-secret-get`; `sf-org-login` gains `credential-source: gcp`                                                                                    | login to `DEMO-INTEGRATION` from Actions; AWS path regression-tested                            |
| **4** | `shared-github-actions` | `sf-artifact-build`, `sf-artifact-deploy`, `sf-env-config-apply`, `gcs-artifact-upload`                                                            | integration deploy from a stored zip; checksum verified; object overwrite rejected              |
| **5** | `shared-github-actions` | `reusable-sf-org-deploy.yml`; `reusable-sf-code-analyze.yml` containerized                                                                         | delta and full modes both deploy; tag moves only on success                                     |
| **6** | `sf-develop-demo`       | `ci.yml`, two deploy callers, `config/environments/`, `sfdx-project.json` replacements; delete `feature-validation.yml` and `test-aws-secrets.yml` | PR gate, integration deploy, gated production deploy end-to-end                                 |
| **7** | both                    | Rollback-by-sha workflow, gitleaks gate, `docs/` + Phase 0 runbook, `pipeline-map.md` update                                                       | rollback drill restores a prior artifact from GCS                                               |

Phases 1 and 2 are independent and may run in parallel. 3 → 4 → 5 → 6 is a hard chain.

---

## 13. Demonstration scenarios

| #   | Scenario                   | Path                                                                                                  |
| --- | -------------------------- | ----------------------------------------------------------------------------------------------------- |
| A   | PR validation              | PR → `main`; Jest, Code Analyzer, Prettier, scratch org deploy, Apex tests; no long-lived org touched |
| B   | Delta deployment           | change one Apex class → push `main` → delta artifact → integration                                    |
| C   | Full deployment            | `workflow_dispatch` with `mode: full` → complete artifact → integration                               |
| D   | Gated production promotion | tag `v1.4.0` → approval → delta from `deployed/production` → production                               |
| E   | Catch-up                   | production two releases behind receives a larger delta automatically                                  |
| F   | Rollback                   | dispatch `rollback-to: <sha>` → prior artifact from GCS → redeployed                                  |
| G   | Isolation proof            | an `integration` job requesting `sf-devops-production` is denied by IAM                               |
| H   | Immutability proof         | re-uploading an existing GCS object path is rejected by `objectCreator`                               |

Scenarios G and H are negative tests and are part of Phase 2 and Phase 4 acceptance
respectively.

---

## 14. Out of scope

- 2GP / source-based package model — deferred to a separate spec. The existing
  `reusable-sf-package-release.yml` and `sf-package-*` actions are untouched.
- The Salesforce-triggered dispatch chain (`reusable-sf-ops-dispatch.yml`,
  `dispatch-*.yml`, the Apex REST callback endpoint) — untouched.
- Salesforce Partner Business Org / Environment Hub / managed 2GP.
- Any change to Apex or LWC source under `github-action-service/` or `weather-app/`.
- AWS. `aws-secret-get` remains in `shared-github-actions` for other consumers; this pipeline
  does not use it.

---

## 15. Open items

| Item                                                                                        | Owner   | Blocks  |
| ------------------------------------------------------------------------------------------- | ------- | ------- |
| GitHub plan — repository must be public or account on Pro for `production` protection rules | Gabor   | Phase 6 |
| Exact `@salesforce/cli` version to pin in `sf-ci:1.8.0`                                     | Phase 1 | Phase 1 |
| Whether the Dev Hub credential moves from AWS to GCP, or both remain available              | Phase 3 | Phase 3 |

"GVT" in the source requirements is read as JWT throughout; the existing implementation is the
JWT bearer flow and no other mechanism was found in the repositories.
