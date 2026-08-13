# Salesforce Org-Based DevOps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a containerized, artifact-based Salesforce deployment pipeline that promotes metadata from git to two long-lived orgs (`DEMO-INTEGRATION`, `DEMO-PROD`) with per-environment delta calculation, immutable artifacts, environment-scoped credentials, approval gates, and rollback.

**Architecture:** Three repositories, three layers. `sf-docker-images` owns the pinned runtime (`sf-ci:1.8.0`). `shared-github-actions` owns L1 capability actions (each shells out to `sf`), one L2 reusable workflow (`reusable-sf-org-deploy.yml`) that orchestrates them, and a Terraform module that provisions the GitHub Environments. `sf-develop-demo` owns only thin L4 caller workflows. The build job freezes an MDAPI artifact; the deploy job has no `actions/checkout` and therefore cannot regenerate it.

**Tech Stack:** Docker (Ubuntu 22.04), Salesforce CLI v2, `sfdx-git-delta`, GitHub Actions (composite actions + reusable workflows), Terraform (`integrations/github` provider), pytest + testinfra, actionlint, gitleaks.

**Source spec:** `docs/superpowers/specs/2026-08-13-salesforce-org-based-devops-design.md`

## Global Constraints

- Salesforce API version **65.0** (`sourceApiVersion` in `sfdx-project.json`).
- Container image tag for all pipeline jobs: **`gforceinnovation/sf-ci:1.8.0`**, run with **`options: --user 1001`**.
- **No `sf` CLI invocation may appear in `sf-develop-demo`.** Any step shelling out to `sf` belongs in an L1 action in `shared-github-actions`.
- **L1 never calls L1.** L3 inlines no Salesforce logic. No pass-through layer forwarding inputs unchanged. Nesting caps at 4 (ADR 0002).
- Action naming: `<domain>-<object>-<verb>` (`sf-artifact-build`, `sf-env-config-apply`). Reusable workflows are prefixed `reusable-`.
- Consumer refs pin `@v2` (never `@main`): `Gforce-Innovation-Kft/shared-github-actions/.github/actions/<name>@v2`.
- `fflib-apex-common/` and `fflib-apex-mocks/` are **read-only submodules** — never edit.
- Every checkout that feeds a delta uses `fetch-depth: 0` and `submodules: recursive`.
- Secrets: never committed, never in workflow YAML, never printed. Every secret consumed is registered with `::add-mask::` before first use. Temp credential files are `chmod 600` and removed by an `if: always()` step.
- Terraform state holds sensitive values in plaintext — state stays local, `chmod 600`, gitignored.
- Deployment artifacts must contain **no secrets** (D2). `gitleaks` gates upload.

## Prerequisite gate — Phase 0 (manual, not a task)

Do not start Task 3 until §5.4 of the spec passes:

- [ ] `sf org login jwt` succeeds for `devhub`, `integration`, `production` from a clean shell
- [ ] Each Connected App: Permitted Users = _Admin approved users are pre-authorized_, System Administrator assigned
- [ ] `~/.sf-jwt/{devhub,integration,production}/payload.json` exist, `chmod 600`
- [ ] Fine-grained PAT (Administration / Environments / Secrets / Variables = Read & write) exported as `GITHUB_TOKEN`
- [ ] Repository visibility decided; artifact retention set to max
- [ ] `git submodule status` shows both fflib submodules checked out

Tasks 1–2 (`sf-docker-images`) have no Phase 0 dependency and may start immediately.

---

## File Structure

### `sf-docker-images`

| File                  | Responsibility                                                                      |
| --------------------- | ----------------------------------------------------------------------------------- |
| `sf-ci/Dockerfile`    | Modify — pin tool versions, add Python/Code Analyzer/gitleaks, emit `versions.json` |
| `sf-ci/README.md`     | Modify — document the pinned versions                                               |
| `tests/test_sf_ci.py` | Modify — assert pinned versions and new tooling                                     |

### `shared-github-actions`

| File                                                                                     | Responsibility                                              |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `infra/terraform/modules/github-sf-environments/{main,variables,outputs}.tf`             | Create — environments, protection rules, secrets, variables |
| `infra/terraform/examples/sf-develop-demo/{main.tf,terraform.tfvars.example,.gitignore}` | Create — root module for this repo                          |
| `.github/actions/sf-org-login/action.yml`                                                | Modify — add `credential-source` with a `github-env` branch |
| `.github/actions/sf-artifact-build/action.yml`                                           | Create — convert, zip, checksum, manifest                   |
| `.github/actions/sf-artifact-deploy/action.yml`                                          | Create — verify checksum, deploy `--metadata-dir`           |
| `.github/actions/sf-env-config-apply/action.yml`                                         | Create — render secret-bearing CMDT and deploy it           |
| `.github/workflows/reusable-sf-org-deploy.yml`                                           | Create — the two-job engine                                 |
| `.github/workflows/reusable-sf-code-analyze.yml`                                         | Modify — move into the container                            |
| `.github/workflows/ci-sf-artifact-smoke.yml`                                             | Create — org-free smoke test for the artifact actions       |
| `examples/reusable-sf-org-deploy.yml`                                                    | Create — runnable caller example                            |

### `sf-develop-demo`

| File                                                       | Responsibility                                  |
| ---------------------------------------------------------- | ----------------------------------------------- |
| `config/environments/{integration,production}.json`        | Create — non-secret replacement values          |
| `config/secret-templates/customMetadata/*.md-meta.xml.tpl` | Create — deploy-time secret injection templates |
| `sfdx-project.json`                                        | Modify — retarget `replacements`                |
| `.github/workflows/ci.yml`                                 | Create — PR gate                                |
| `.github/workflows/org-deploy-integration.yml`             | Create — push `main` → integration              |
| `.github/workflows/org-deploy-production.yml`              | Create — tag `v*` → production, gated           |
| `.github/workflows/org-rollback.yml`                       | Create — redeploy a prior artifact              |
| `.github/workflows/feature-validation.yml`                 | Delete                                          |
| `.github/workflows/test-aws-secrets.yml`                   | Delete                                          |
| `docs/devops/`                                             | Create — runbook + architecture                 |

## Task dependency graph

```
Task 1 ─→ Task 2                      (sf-docker-images, independent)
Task 3 ─→ Task 4                      (terraform, needs Phase 0)
Task 5                                (sf-org-login, needs Task 2 image)
Task 6 ─→ Task 7 ─→ Task 8            (artifact actions)
        └─────────→ Task 9 ─→ Task 10 (engine)
Task 9 ─→ Task 11 ─→ Task 12 ─→ Task 13 ─→ Task 14 ─→ Task 15 ─→ Task 16
```

---

## Task 1: Pin the sf-ci toolchain and emit a version manifest

Reproducibility requires exact versions. `@salesforce/cli@2.*` resolves to whatever is newest at build time, so two builds of the same Dockerfile can ship different CLIs. This task pins them and publishes a machine-readable manifest that `sf-artifact-build` later embeds in `deployment.json`.

**Files:**

- Modify: `sf-docker-images/sf-ci/Dockerfile`
- Modify: `sf-docker-images/tests/test_sf_ci.py`
- Modify: `sf-docker-images/sf-ci/README.md`

**Interfaces:**

- Consumes: nothing
- Produces: `/opt/sf-ci/versions.json` inside the image, with keys `salesforceCli`, `sfdxGitDelta`, `node`, `java`, `codeAnalyzer`, `python`, `gitleaks`. Every value is a string. Task 6's `sf-artifact-build` reads this file.

- [ ] **Step 1: Resolve the versions to pin**

```bash
cd ~/gforce/sf-docker-images
docker run --rm --entrypoint sh gforceinnovation/sf-ci:1.7.0 -c \
  'sf version --json | head -20; sf plugins --json'
```

Record the `@salesforce/cli` version and the `sfdx-git-delta` version. Use those exact values below in place of `2.106.6` and `6.15.0`.

- [ ] **Step 2: Write the failing tests**

Append to `sf-docker-images/tests/test_sf_ci.py`:

```python
import json

# Keep in sync with the ARG defaults in sf-ci/Dockerfile.
EXPECTED_SF_CLI = "2.106.6"
EXPECTED_SGD = "6.15.0"


def test_sf_cli_version_is_pinned(host):
    """An exact CLI version, not a floating 2.* range.

    A floating range means two builds of the same Dockerfile can ship
    different CLIs, which defeats `git commit + image tag = reproducible`.
    """
    out = host.run("sf version --json")
    assert out.rc == 0
    payload = json.loads(out.stdout)
    assert payload["cliVersion"] == f"@salesforce/cli/{EXPECTED_SF_CLI}", payload["cliVersion"]


def test_sgd_plugin_version_is_pinned(host):
    out = host.run("sf plugins --json")
    assert out.rc == 0
    plugins = {p["name"]: p["version"] for p in json.loads(out.stdout)}
    assert plugins.get("sfdx-git-delta") == EXPECTED_SGD, plugins


def test_versions_manifest_exists_and_is_valid_json(host):
    """sf-artifact-build reads this to stamp deployment.json."""
    manifest = host.file("/opt/sf-ci/versions.json")
    assert manifest.exists
    payload = json.loads(manifest.content_string)
    for key in (
        "salesforceCli",
        "sfdxGitDelta",
        "node",
        "java",
        "codeAnalyzer",
        "python",
        "gitleaks",
    ):
        assert key in payload, f"{key} missing from versions.json"
        assert isinstance(payload[key], str) and payload[key], f"{key} is empty"


def test_versions_manifest_matches_reality(host):
    """A stale manifest is worse than none — it lies in the audit record."""
    payload = json.loads(host.file("/opt/sf-ci/versions.json").content_string)
    assert payload["salesforceCli"] == EXPECTED_SF_CLI
    assert payload["sfdxGitDelta"] == EXPECTED_SGD
    assert host.run("node --version").stdout.strip() == f"v{payload['node']}"
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd ~/gforce/sf-docker-images
python3 -m venv .venv && . .venv/bin/activate
pip install -r tests/requirements.txt
docker build -t sf-ci:test ./sf-ci
pytest tests/test_sf_ci.py -k "pinned or manifest" -v
```

Expected: FAIL — `test_versions_manifest_exists_and_is_valid_json` fails because `/opt/sf-ci/versions.json` does not exist; the pin tests fail unless the floating range happens to match.

- [ ] **Step 4: Pin the versions in the Dockerfile**

In `sf-ci/Dockerfile`, add build args directly after the `ENV DEBIAN_FRONTEND=noninteractive` line:

```dockerfile
# Exact versions, not ranges. A floating range makes two builds of the same
# Dockerfile ship different tools, which breaks the reproducibility claim
# (git commit + image tag = reproducible pipeline). Bump deliberately and
# update EXPECTED_* in tests/test_sf_ci.py in the same commit.
ARG SF_CLI_VERSION=2.106.6
ARG SGD_VERSION=6.15.0
```

Replace the `npm install -g @salesforce/cli@2.*` fragment with:

```dockerfile
    && npm install -g "@salesforce/cli@${SF_CLI_VERSION}" \
```

Replace the plugin install line with:

```dockerfile
RUN echo y | sf plugins install "sfdx-git-delta@${SGD_VERSION}"
```

- [ ] **Step 5: Emit the version manifest**

Insert immediately before the final `WORKDIR /workspace` line, as `root`:

```dockerfile
# Machine-readable toolchain manifest.
#
# sf-artifact-build copies these values into deployment.json so an audit
# record names the exact tools that produced the artifact. Generated at build
# time from the tools themselves rather than hardcoded, so it cannot drift.
USER root
RUN set -eux; \
    mkdir -p /opt/sf-ci; \
    printf '%s' "$( \
      node -e '
        const { execSync } = require("child_process");
        const run = (c) => execSync(c, { encoding: "utf8" }).trim();
        const plugins = JSON.parse(run("sf plugins --json"));
        const sgd = plugins.find((p) => p.name === "sfdx-git-delta");
        console.log(JSON.stringify({
          salesforceCli: run("sf version --json | node -pe \x27JSON.parse(require(\"fs\").readFileSync(0,\"utf8\")).cliVersion.split(\"/\")[1]\x27"),
          sfdxGitDelta: sgd ? sgd.version : "",
          node: process.versions.node,
          java: run("java -version 2>&1 | head -1").replace(/.*\"([^\"]+)\".*/, "$1"),
          codeAnalyzer: "",
          python: "",
          gitleaks: "",
        }, null, 2));
      ' \
    )" > /opt/sf-ci/versions.json; \
    chmod 644 /opt/sf-ci/versions.json; \
    cat /opt/sf-ci/versions.json
USER ci
```

> `codeAnalyzer`, `python` and `gitleaks` are intentionally empty strings here — Task 2 installs those tools and fills them in. The keys exist from the start so `sf-artifact-build` never has to branch on their presence.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd ~/gforce/sf-docker-images
docker build -t sf-ci:test ./sf-ci
pytest tests/test_sf_ci.py -v
```

Expected: PASS, all tests including the pre-existing ones.

- [ ] **Step 7: Document the pins**

Add to `sf-ci/README.md` under the existing contents:

```markdown
## Pinned versions

| Tool           | Version   | Where                |
| -------------- | --------- | -------------------- |
| Salesforce CLI | `2.106.6` | `ARG SF_CLI_VERSION` |
| sfdx-git-delta | `6.15.0`  | `ARG SGD_VERSION`    |

Both are exact, not ranges — a floating range makes two builds of the same
Dockerfile ship different tools. To bump: change the `ARG`, update
`EXPECTED_SF_CLI` / `EXPECTED_SGD` in `tests/test_sf_ci.py`, and ship both in
one commit.

The image also publishes `/opt/sf-ci/versions.json`, generated at build time
from the installed tools. `sf-artifact-build` copies it into every
`deployment.json` so deployments record the toolchain that produced them.
```

- [ ] **Step 8: Commit**

```bash
cd ~/gforce/sf-docker-images
git checkout -b feat/sf-ci-1.8.0
git add sf-ci/Dockerfile sf-ci/README.md tests/test_sf_ci.py
git commit -m "feat(sf-ci): pin CLI and sgd versions, emit versions.json

A floating @salesforce/cli@2.* range meant two builds of the same
Dockerfile could ship different CLIs, defeating the reproducibility
claim. Pin both tools via build args and generate a machine-readable
toolchain manifest at /opt/sf-ci/versions.json for sf-artifact-build to
stamp into deployment.json."
```

---

## Task 2: Add Code Analyzer, Python and gitleaks to sf-ci

Static analysis and the secret-scan gate must run inside the pinned image, not on `ubuntu-latest` — otherwise the runner becomes the source of tool versions and §2.3 of the spec is violated.

**Files:**

- Modify: `sf-docker-images/sf-ci/Dockerfile`
- Modify: `sf-docker-images/tests/test_sf_ci.py`
- Modify: `sf-docker-images/sf-ci/README.md`

**Interfaces:**

- Consumes: `/opt/sf-ci/versions.json` from Task 1
- Produces: `sf code-analyzer run` available; `gitleaks` on `PATH`; `python3` on `PATH`; `versions.json` keys `codeAnalyzer`, `python`, `gitleaks` populated with non-empty strings

- [ ] **Step 1: Write the failing tests**

Append to `sf-docker-images/tests/test_sf_ci.py`:

```python
EXPECTED_GITLEAKS = "8.21.2"


def test_python3_installed(host):
    """Salesforce Code Analyzer's engines require a Python runtime."""
    out = host.run("python3 --version")
    assert out.rc == 0
    assert out.stdout.startswith("Python 3.")


def test_code_analyzer_plugin_installed(host):
    out = host.run("sf plugins --json")
    assert out.rc == 0
    plugins = {p["name"]: p["version"] for p in json.loads(out.stdout)}
    assert "@salesforce/plugin-code-analyzer" in plugins, plugins


def test_code_analyzer_runs(host):
    """Presence is not enough — the plugin must actually execute."""
    out = host.run("sf code-analyzer rules --output-file /tmp/rules.json")
    assert out.rc == 0, out.stderr[:400]


def test_gitleaks_installed_and_pinned(host):
    out = host.run("gitleaks version")
    assert out.rc == 0
    assert EXPECTED_GITLEAKS in out.stdout, out.stdout


def test_gitleaks_detects_a_planted_secret(host):
    """The secret-scan gate is load-bearing: it blocks artifact upload.

    A gitleaks that runs but detects nothing would let a secret-bearing
    artifact through while reporting success, so assert a real detection
    rather than just a zero exit code.
    """
    planted = (
        "mkdir -p /tmp/leak && cd /tmp/leak && "
        "printf 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\\n' > creds.txt && "
        "gitleaks dir /tmp/leak --no-banner"
    )
    out = host.run(planted)
    assert out.rc != 0, "gitleaks must exit non-zero when it finds a secret"


def test_versions_manifest_includes_new_tools(host):
    payload = json.loads(host.file("/opt/sf-ci/versions.json").content_string)
    assert payload["gitleaks"] == EXPECTED_GITLEAKS
    assert payload["python"].startswith("3.")
    assert payload["codeAnalyzer"], "codeAnalyzer version must be populated"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/gforce/sf-docker-images
docker build -t sf-ci:test ./sf-ci
pytest tests/test_sf_ci.py -k "python3 or code_analyzer or gitleaks or new_tools" -v
```

Expected: FAIL — `python3: not found`, `gitleaks: not found`, plugin absent.

- [ ] **Step 3: Install Python and gitleaks**

In `sf-ci/Dockerfile`, add to the ARG block from Task 1:

```dockerfile
ARG GITLEAKS_VERSION=8.21.2
```

Add `python3` and `python3-venv` to the first `apt-get install` list, after `unzip` / `zip`:

```dockerfile
    # Salesforce Code Analyzer engines need a Python runtime
    python3 \
    python3-venv \
```

Add a new layer after the Node/Java/CLI layer, before the `useradd` lines:

```dockerfile
# gitleaks — the secret-scan gate that blocks artifact upload.
# Fetched as a pinned release tarball; there is no apt package.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) gl_arch=x64 ;; \
      arm64) gl_arch=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz"; \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks; \
    chmod 755 /usr/local/bin/gitleaks; \
    rm -f /tmp/gitleaks.tar.gz; \
    gitleaks version
```

- [ ] **Step 4: Install the Code Analyzer plugin**

Change the plugin install line from Task 1 to install both plugins as the `ci` user, so they land in `XDG_DATA_HOME=/opt/sf-data`:

```dockerfile
RUN echo y | sf plugins install "sfdx-git-delta@${SGD_VERSION}" \
    && echo y | sf plugins install "@salesforce/plugin-code-analyzer"
```

- [ ] **Step 5: Populate the manifest with the new tools**

In the `versions.json` generation block from Task 1, replace the three empty-string values:

```javascript
          codeAnalyzer: (plugins.find((p) => p.name === "@salesforce/plugin-code-analyzer") || {}).version || "",
          python: run("python3 --version").replace("Python ", ""),
          gitleaks: run("gitleaks version").trim(),
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd ~/gforce/sf-docker-images
docker build -t sf-ci:test ./sf-ci
pytest tests/test_sf_ci.py -v
```

Expected: PASS. If `test_minimal_footprint` or the image-size check now fails, that is a real signal — Code Analyzer is large. Record the new size in the README rather than suppressing the test.

- [ ] **Step 7: Update the README size table and pins**

In `sf-ci/README.md`, update the pinned-versions table to add gitleaks, and update the stated image size. Also update the root `README.md` size column for `sf-ci`.

```bash
docker images sf-ci:test --format '{{.Size}}'
```

- [ ] **Step 8: Commit and open the PR**

```bash
cd ~/gforce/sf-docker-images
git add sf-ci/Dockerfile sf-ci/README.md README.md tests/test_sf_ci.py
git commit -m "feat(sf-ci): add Code Analyzer, Python and gitleaks

Static analysis and the secret-scan gate must run inside the pinned
image rather than on ubuntu-latest, so the runner never becomes the
source of tool versions. gitleaks is asserted against a planted secret,
not just a zero exit code, because it gates artifact upload."
git push -u origin feat/sf-ci-1.8.0
gh pr create --fill
```

- [ ] **Step 9: Merge and tag the release**

Once `image-sf-ci.yml` is green (both E2E tiers), merge and tag:

```bash
git checkout main && git pull
git tag -a v1.8.0 -m "sf-ci 1.8.0 — pinned toolchain, Code Analyzer, gitleaks"
git push origin v1.8.0
```

Verify the published image before any downstream repo pins it:

```bash
docker pull gforceinnovation/sf-ci:1.8.0
docker run --rm gforceinnovation/sf-ci:1.8.0 cat /opt/sf-ci/versions.json
```

---

## Task 3: Terraform module — GitHub Environments and protection rules

Environments and their protection rules stop being hand-clicked. This task creates them; Task 4 adds the secrets.

**Files:**

- Create: `shared-github-actions/infra/terraform/modules/github-sf-environments/main.tf`
- Create: `shared-github-actions/infra/terraform/modules/github-sf-environments/variables.tf`
- Create: `shared-github-actions/infra/terraform/modules/github-sf-environments/outputs.tf`
- Create: `shared-github-actions/infra/terraform/modules/github-sf-environments/README.md`
- Create: `shared-github-actions/infra/terraform/examples/sf-develop-demo/main.tf`
- Create: `shared-github-actions/infra/terraform/examples/sf-develop-demo/terraform.tfvars.example`
- Create: `shared-github-actions/infra/terraform/examples/sf-develop-demo/.gitignore`
- Create: `shared-github-actions/infra/terraform/README.md`

**Interfaces:**

- Consumes: `GITHUB_TOKEN` from Phase 0 §5.2.2
- Produces: module `github-sf-environments` with inputs `repository` (string), `environments` (map of object), `credentials_dir` (string); outputs `environment_names` (list(string)), `secret_names` (map(list(string)))

- [ ] **Step 1: Verify the provider schema before writing anything**

The spec flags this as unverified (§16). Resolve it now:

```bash
cd ~/gforce/shared-github-actions
mkdir -p infra/terraform/examples/sf-develop-demo
cd infra/terraform/examples/sf-develop-demo
cat > probe.tf <<'EOF'
terraform {
  required_providers {
    github = { source = "integrations/github", version = "~> 6.0" }
  }
}
EOF
terraform init
terraform providers schema -json > /tmp/gh-schema.json
jq '.provider_schemas["registry.terraform.io/integrations/github"].resource_schemas
    | {env: .github_repository_environment.block.attributes,
       secret: .github_actions_environment_secret.block.attributes,
       var: .github_actions_environment_variable.block.attributes}' /tmp/gh-schema.json
rm probe.tf
```

Record the exact attribute names and whether `plaintext_value` / `encrypted_value` are optional. If they differ from what this plan assumes, adjust the code below and note the difference in the module README.

- [ ] **Step 2: Write the failing validation**

Create `infra/terraform/examples/sf-develop-demo/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Token comes from GITHUB_TOKEN in the environment, never from a variable —
# a variable would land in terraform.tfstate and in shell history.
provider "github" {
  owner = var.owner
}

variable "owner" {
  type        = string
  description = "GitHub org or user that owns the repository"
}

variable "repository" {
  type        = string
  description = "Repository name, without the owner prefix"
}

variable "credentials_dir" {
  type        = string
  description = "Local directory holding <env>/payload.json from spec section 5.1.5"
}

variable "production_reviewers" {
  type        = description_placeholder
  description = "GitHub user IDs (numeric) required to approve production deploys"
}

module "environments" {
  source = "../../modules/github-sf-environments"

  repository      = var.repository
  credentials_dir = var.credentials_dir

  environments = {
    integration = {
      protected            = false
      reviewer_user_ids    = []
      deployment_branches  = []
      has_app_secrets      = true
    }
    production = {
      protected            = true
      reviewer_user_ids    = var.production_reviewers
      deployment_branches  = ["main", "v*"]
      has_app_secrets      = true
    }
  }
}

output "environment_names" {
  value = module.environments.environment_names
}
```

> The `description_placeholder` on `production_reviewers` is deliberate — Step 4 replaces it with the real type once you have confirmed the reviewer ID format. Leaving it makes `terraform validate` fail loudly rather than silently accepting a wrong type.

- [ ] **Step 3: Run validation to verify it fails**

```bash
cd ~/gforce/shared-github-actions/infra/terraform/examples/sf-develop-demo
terraform init -backend=false
terraform validate
```

Expected: FAIL — `Invalid type specification` on `description_placeholder`, and `Module not found` for `../../modules/github-sf-environments`.

- [ ] **Step 4: Fix the placeholder type**

Replace the `production_reviewers` variable block:

```hcl
variable "production_reviewers" {
  type        = list(number)
  description = "GitHub user IDs (numeric, not logins) required to approve production deploys"
}
```

Get your numeric user ID:

```bash
gh api user --jq .id
```

- [ ] **Step 5: Write the module**

Create `infra/terraform/modules/github-sf-environments/variables.tf`:

```hcl
variable "repository" {
  type        = string
  description = "Repository name, without the owner prefix"
}

variable "credentials_dir" {
  type        = string
  description = <<-EOT
    Local directory holding <env>/payload.json, produced by section 5.1.5 of the
    design spec. Read with file() at plan time — these files never enter the
    repository and their values land in state, so state must stay local.
  EOT
}

variable "environments" {
  description = "Environment name -> configuration"
  type = map(object({
    protected           = bool
    reviewer_user_ids   = list(number)
    deployment_branches = list(string)
    has_app_secrets     = bool
  }))
}
```

Create `infra/terraform/modules/github-sf-environments/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

locals {
  # payload.json is the single source of truth shared with the manual runbook.
  # jsondecode at plan time means a malformed file fails before anything is
  # created, rather than half-provisioning an environment.
  payloads = {
    for name, _ in var.environments :
    name => jsondecode(file("${var.credentials_dir}/${name}/payload.json"))
  }
}

resource "github_repository_environment" "env" {
  for_each    = var.environments
  repository  = var.repository
  environment = each.key

  # A reviewers block with an empty list still creates a (satisfied) rule, so
  # it is emitted only for protected environments.
  dynamic "reviewers" {
    for_each = each.value.protected ? [1] : []
    content {
      users = each.value.reviewer_user_ids
    }
  }

  # custom_branch_policies is required when specific branches/tags are named;
  # protected_branches alone cannot express a tag pattern like v*.
  dynamic "deployment_branch_policy" {
    for_each = length(each.value.deployment_branches) > 0 ? [1] : []
    content {
      protected_branches     = false
      custom_branch_policies = true
    }
  }
}

resource "github_repository_environment_deployment_policy" "branches" {
  for_each = merge([
    for env_name, cfg in var.environments : {
      for pattern in cfg.deployment_branches :
      "${env_name}:${pattern}" => { environment = env_name, pattern = pattern }
    }
  ]...)

  repository  = var.repository
  environment = github_repository_environment.env[each.value.environment].environment
  branch_pattern = each.value.pattern
}
```

Create `infra/terraform/modules/github-sf-environments/outputs.tf`:

```hcl
output "environment_names" {
  description = "Names of the environments created"
  value       = sort([for e in github_repository_environment.env : e.environment])
}
```

- [ ] **Step 6: Run validation to verify it passes**

```bash
cd ~/gforce/shared-github-actions/infra/terraform/examples/sf-develop-demo
terraform fmt -recursive ../../
terraform init -backend=false
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Plan against the real repository**

```bash
cat > terraform.tfvars <<EOF
owner                = "Gforce-Innovation-Kft"
repository           = "sf-develop-demo"
credentials_dir      = "$HOME/.sf-jwt"
production_reviewers = [$(gh api user --jq .id)]
EOF

export GITHUB_TOKEN=<your fine-grained PAT>
terraform init
terraform plan
```

Expected: a plan creating 2 `github_repository_environment` and 2 `github_repository_environment_deployment_policy` resources. No secrets yet — that is Task 4.

- [ ] **Step 8: Write the gitignore before applying**

Create `infra/terraform/examples/sf-develop-demo/.gitignore`:

```
# State holds every value in plaintext, including anything marked sensitive.
# sensitive = true suppresses console output only; it does not encrypt state.
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Real values. Only the .example is tracked.
*.tfvars
!*.tfvars.example
```

Create `terraform.tfvars.example`:

```hcl
owner                = "Gforce-Innovation-Kft"
repository           = "sf-develop-demo"
credentials_dir      = "/Users/you/.sf-jwt"
production_reviewers = [12345678] # gh api user --jq .id
```

Confirm nothing sensitive is staged:

```bash
cd ~/gforce/shared-github-actions
git status --short infra/terraform/
git check-ignore -v infra/terraform/examples/sf-develop-demo/terraform.tfvars
```

Expected: `terraform.tfvars` is ignored; only `.example`, `.gitignore`, `.tf` and `.md` files appear as untracked.

- [ ] **Step 9: Apply and verify in the GitHub UI**

```bash
cd ~/gforce/shared-github-actions/infra/terraform/examples/sf-develop-demo
terraform apply
chmod 600 terraform.tfstate
```

Verify at Settings → Environments: `integration` exists with no rules; `production` requires your review and is limited to `main` and `v*`.

- [ ] **Step 10: Write the READMEs and commit**

Create `infra/terraform/README.md` and `infra/terraform/modules/github-sf-environments/README.md` documenting: what the module manages, the `GITHUB_TOKEN` requirement and its four permissions, the state hazard from §8.3 of the spec, and that Phase 8 adds `github-oidc`, `sf-env-secrets` and `artifact-store` as siblings.

```bash
cd ~/gforce/shared-github-actions
git checkout -b feat/terraform-github-environments
git add infra/terraform/
git commit -m "feat(terraform): provision GitHub Environments and protection rules

Environments, required reviewers and branch/tag restrictions become IaC
rather than hand-clicked settings. Token comes from GITHUB_TOKEN, never a
variable, because a variable lands in state. State is gitignored and
stays local: sensitive = true suppresses console output but does not
encrypt state."
```

---

## Task 4: Terraform module — environment secrets and variables

**Files:**

- Modify: `shared-github-actions/infra/terraform/modules/github-sf-environments/main.tf`
- Modify: `shared-github-actions/infra/terraform/modules/github-sf-environments/outputs.tf`
- Modify: `shared-github-actions/infra/terraform/modules/github-sf-environments/README.md`

**Interfaces:**

- Consumes: `local.payloads` from Task 3; `github_repository_environment.env` from Task 3
- Produces: per environment, secrets `SF_JWT_KEY_B64`, `SF_CLIENT_ID` (plus `GITHUB_APP_KEY_B64`, `OWM_API_KEY` when `has_app_secrets`), and variables `SF_USERNAME`, `SF_INSTANCE_URL`, `SF_ENV_LABEL`. Task 5's `sf-org-login` and Task 9's engine read exactly these names.

- [ ] **Step 1: Write the failing plan assertion**

Add to `infra/terraform/examples/sf-develop-demo/main.tf`:

```hcl
output "secret_names" {
  value = module.environments.secret_names
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/gforce/shared-github-actions/infra/terraform/examples/sf-develop-demo
terraform validate
```

Expected: FAIL — `Unsupported attribute: This object does not have an attribute named "secret_names"`.

- [ ] **Step 3: Add the secret and variable resources**

Append to `infra/terraform/modules/github-sf-environments/main.tf`:

```hcl
# Secrets vs variables is a deliberate split. Key material and API keys are
# secrets. The org username and login URL are operational facts that should
# stay readable in the Actions UI, because a wrong INSTANCE_URL is the single
# most common JWT failure and masking it makes that undebuggable.

locals {
  core_secrets = {
    for name, payload in local.payloads :
    name => {
      SF_JWT_KEY_B64 = payload.JWT_KEY_B64
      SF_CLIENT_ID   = payload.CLIENT_ID
    }
  }

  app_secrets = {
    for name, cfg in var.environments :
    name => cfg.has_app_secrets ? {
      GITHUB_APP_KEY_B64 = local.payloads[name].GITHUB_APP_KEY_B64
      OWM_API_KEY        = local.payloads[name].OWM_API_KEY
    } : {}
  }

  # Flatten to "<env>:<SECRET_NAME>" so for_each has a stable string key.
  # Keying on the value would leak a secret into resource addresses and plan
  # output.
  all_secrets = merge([
    for env_name, secrets in {
      for k, v in local.core_secrets : k => merge(v, local.app_secrets[k])
      } : {
      for secret_name, secret_value in secrets :
      "${env_name}:${secret_name}" => {
        environment = env_name
        name        = secret_name
        value       = secret_value
      }
    }
  ]...)

  all_variables = merge([
    for env_name, payload in local.payloads : {
      "${env_name}:SF_USERNAME" = {
        environment = env_name, name = "SF_USERNAME", value = payload.USERNAME
      }
      "${env_name}:SF_INSTANCE_URL" = {
        environment = env_name, name = "SF_INSTANCE_URL", value = payload.INSTANCE_URL
      }
      "${env_name}:SF_ENV_LABEL" = {
        environment = env_name, name = "SF_ENV_LABEL", value = upper(env_name)
      }
    }
  ]...)
}

resource "github_actions_environment_secret" "this" {
  for_each = local.all_secrets

  repository      = var.repository
  environment     = github_repository_environment.env[each.value.environment].environment
  secret_name     = each.value.name
  plaintext_value = each.value.value
}

resource "github_actions_environment_variable" "this" {
  for_each = local.all_variables

  repository    = var.repository
  environment   = github_repository_environment.env[each.value.environment].environment
  variable_name = each.value.name
  value         = each.value.value
}
```

- [ ] **Step 4: Add the output**

Append to `infra/terraform/modules/github-sf-environments/outputs.tf`:

```hcl
output "secret_names" {
  description = "Environment -> secret names created. Names only, never values."
  value = {
    for env_name, _ in var.environments :
    env_name => sort([
      for k, v in local.all_secrets : v.name if v.environment == env_name
    ])
  }
}
```

- [ ] **Step 5: Run validate and plan to verify they pass**

```bash
cd ~/gforce/shared-github-actions/infra/terraform/examples/sf-develop-demo
terraform fmt -recursive ../../
terraform validate
terraform plan
```

Expected: `Success!`, then a plan adding 8 secrets (4 per environment) and 6 variables (3 per environment). Secret values must show as `(sensitive value)` in the plan output — if any plaintext appears, stop and fix before applying.

- [ ] **Step 6: Apply and verify**

```bash
terraform apply
chmod 600 terraform.tfstate
terraform output secret_names
```

Verify in Settings → Environments → `production`: four secrets and three variables, with variable values visible and secret values hidden.

- [ ] **Step 7: Confirm the state hazard is contained**

```bash
grep -c "BEGIN RSA PRIVATE KEY\|JWT_KEY_B64" terraform.tfstate || true
git check-ignore -v terraform.tfstate
ls -l terraform.tfstate
```

Expected: the grep finds matches (this is the documented §8.3 hazard, not a bug), the file is gitignored, and the mode is `600`.

- [ ] **Step 8: Document and commit**

Add to the module README a "State hazard" section quoting the finding from Step 7, and stating the two mitigations from spec §8.3 (pre-encrypt with `encrypted_value`, or local locked-down state) and that Phase 8 dissolves the problem.

```bash
cd ~/gforce/shared-github-actions
git add infra/terraform/
git commit -m "feat(terraform): manage environment secrets and variables

Reads the same payload.json the manual runbook produces, so the runbook
and the IaC share one source of truth. Key material and API keys are
secrets; username and login URL are variables so they stay readable in
the Actions UI, because a wrong INSTANCE_URL is the most common JWT
failure and masking it makes that undebuggable.

for_each keys on <env>:<NAME> rather than the value, so no secret
reaches a resource address or plan output."
git push -u origin feat/terraform-github-environments
gh pr create --fill
```

---

## Task 5: Add `credential-source: github-env` to sf-org-login

Introduces the `credential-source` input now so Phase 8's `gcp` branch is additive with zero caller churn. The existing `aws` path must keep working byte-identically.

**Files:**

- Modify: `shared-github-actions/.github/actions/sf-org-login/action.yml`
- Create: `shared-github-actions/.github/workflows/ci-sf-org-login-smoke.yml`
- Modify: `shared-github-actions/README.md`

**Interfaces:**

- Consumes: secrets `SF_JWT_KEY_B64`, `SF_CLIENT_ID` and variables `SF_USERNAME`, `SF_INSTANCE_URL` from Task 4
- Produces: `sf-org-login` accepting `credential-source: aws | github-env`; with `github-env` it takes `jwt-key-b64`, `username`, `client-id`, `instance-url`. Outputs unchanged: `org-id`, `username`, `instance-url`, `access-token`. Tasks 7 and 9 call it with `credential-source: github-env`.

- [ ] **Step 1: Install actionlint for a local failing-test loop**

```bash
brew install actionlint
actionlint --version
```

- [ ] **Step 2: Write the failing smoke workflow**

Create `shared-github-actions/.github/workflows/ci-sf-org-login-smoke.yml`:

```yaml
---
# Smoke test for sf-org-login's github-env credential source.
#
# Composite actions have no unit-test harness, so the gate is a real run.
# This one authenticates against the Dev Hub using environment credentials
# and asserts the action's outputs, which is the whole contract downstream
# actions depend on.
name: ci-sf-org-login-smoke

on:
  workflow_dispatch:
  pull_request:
    branches: [main]
    paths:
      - ".github/actions/sf-org-login/**"
      - ".github/workflows/ci-sf-org-login-smoke.yml"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  github-env-source:
    name: credential-source github-env
    runs-on: ubuntu-latest
    environment: integration
    container:
      image: gforceinnovation/sf-ci:1.8.0
      options: --user 1001
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7

      - name: Log in with environment credentials
        id: login
        uses: ./.github/actions/sf-org-login
        with:
          credential-source: github-env
          jwt-key-b64: ${{ secrets.SF_JWT_KEY_B64 }}
          client-id: ${{ secrets.SF_CLIENT_ID }}
          username: ${{ vars.SF_USERNAME }}
          instance-url: ${{ vars.SF_INSTANCE_URL }}
          org-alias: smoke

      - name: Assert the action's output contract
        env:
          ORG_ID: ${{ steps.login.outputs.org-id }}
          USERNAME: ${{ steps.login.outputs.username }}
          INSTANCE_URL: ${{ steps.login.outputs.instance-url }}
        run: |
          set -euo pipefail
          [ -n "$ORG_ID" ] || { echo "::error::org-id output was empty"; exit 1; }
          [ -n "$USERNAME" ] || { echo "::error::username output was empty"; exit 1; }
          [ -n "$INSTANCE_URL" ] || { echo "::error::instance-url output was empty"; exit 1; }
          case "$ORG_ID" in
            00D*) ;;
            *) echo "::error::org-id '$ORG_ID' is not a valid org id"; exit 1 ;;
          esac
          echo "✅ authenticated to $USERNAME ($ORG_ID)"

      - name: No credential file survives the job
        if: always()
        run: |
          set -euo pipefail
          for f in jwt-key.txt sfdx-auth-url.txt org-info.json; do
            [ ! -f "$f" ] || { echo "::error::$f was left on disk"; exit 1; }
          done
          echo "✅ no credential files left behind"
```

- [ ] **Step 3: Run actionlint to verify it fails**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-org-login-smoke.yml
```

Expected: FAIL — `input "credential-source" is not defined in action "Salesforce Org Login"`, plus the same for `jwt-key-b64`, `client-id`, `username`, `instance-url`.

- [ ] **Step 4: Add the new inputs**

In `.github/actions/sf-org-login/action.yml`, add to the `inputs:` map, before `auth-method`:

```yaml
credential-source:
  description: |
    Where credentials come from: 'aws' (Secrets Manager, the historical
    default) or 'github-env' (passed in directly from GitHub Environment
    secrets and variables). Phase 8 adds 'gcp'. Introduced so adding a
    source is additive and needs no caller changes.
  required: false
  default: "aws"
jwt-key-b64:
  description: "Base64 RSA private key. Required when credential-source is github-env. Always pass a secret, never a literal."
  required: false
  default: ""
username:
  description: "Salesforce username. Required when credential-source is github-env."
  required: false
  default: ""
client-id:
  description: "Connected App consumer key. Required when credential-source is github-env."
  required: false
  default: ""
instance-url:
  description: |
    JWT audience — the LOGIN url, not the My Domain url.
    https://login.salesforce.com for DE/production, https://test.salesforce.com
    for sandboxes. Passing a *.my.salesforce.com url here is the single most
    common cause of a failing JWT login in CI.
  required: false
  default: "https://login.salesforce.com"
```

- [ ] **Step 5: Add validation for the new source**

In the `Validate inputs` step, add `CREDENTIAL_SOURCE`, `JWT_KEY_B64_IN`, `USERNAME_IN` and `CLIENT_ID_IN` to its `env:` block, then extend the validation before the existing `case "$AUTH_METHOD"`:

```bash
        case "$CREDENTIAL_SOURCE" in
          aws|github-env) ;;
          *)
            echo "::error::credential-source must be 'aws' or 'github-env', got '$CREDENTIAL_SOURCE'." >&2
            exit 1
            ;;
        esac

        if [ "$CREDENTIAL_SOURCE" = "github-env" ]; then
          for PAIR in "jwt-key-b64:$JWT_KEY_B64_IN" "username:$USERNAME_IN" "client-id:$CLIENT_ID_IN"; do
            NAME="${PAIR%%:*}"
            VALUE="${PAIR#*:}"
            if [ -z "$VALUE" ]; then
              echo "::error::credential-source 'github-env' needs $NAME." >&2
              exit 1
            fi
          done
        fi
```

- [ ] **Step 6: Gate the AWS fetch and add the github-env branch**

Change the `if:` on the _Get Salesforce credentials from AWS Secrets Manager_ step so it no longer fires for the new source:

```yaml
if: ${{ inputs.auth-method == 'jwt' && inputs.credential-source == 'aws' }}
```

Insert a new step immediately before the existing _Salesforce JWT login_ step:

```yaml
# Publishes the same four env vars the AWS path exports, so the login step
# below is shared by both sources and there is exactly one place that
# knows how to run `sf org login jwt`.
- name: Stage credentials from the GitHub environment
  if: ${{ inputs.auth-method == 'jwt' && inputs.credential-source == 'github-env' }}
  shell: bash
  env:
    JWT_KEY_B64_IN: ${{ inputs.jwt-key-b64 }}
    USERNAME_IN: ${{ inputs.username }}
    CLIENT_ID_IN: ${{ inputs.client-id }}
    INSTANCE_URL_IN: ${{ inputs.instance-url }}
  run: |
    set -euo pipefail
    # Mask before these can reach any later log line.
    echo "::add-mask::$JWT_KEY_B64_IN"
    echo "::add-mask::$CLIENT_ID_IN"
    {
      echo "JWT_KEY_B64=$JWT_KEY_B64_IN"
      echo "USERNAME=$USERNAME_IN"
      echo "CLIENT_ID=$CLIENT_ID_IN"
      echo "INSTANCE_URL=$INSTANCE_URL_IN"
    } >> "$GITHUB_ENV"
```

- [ ] **Step 7: Run actionlint to verify it passes**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-org-login-smoke.yml
npm run all
```

Expected: actionlint silent; `npm run all` passes.

- [ ] **Step 8: Run the smoke workflow against the real org**

```bash
git add -A && git commit -m "wip: sf-org-login github-env source"
git push -u origin feat/sf-org-login-github-env
gh workflow run ci-sf-org-login-smoke.yml --ref feat/sf-org-login-github-env
gh run watch --exit-status
```

Expected: PASS, with `✅ authenticated to ...` and `✅ no credential files left behind`.

- [ ] **Step 9: Verify the AWS path did not regress**

```bash
gh workflow run ci-sf-ops-dispatch-smoke.yml --ref feat/sf-org-login-github-env
gh run watch --exit-status
```

Expected: PASS. The `aws` default must behave exactly as before.

- [ ] **Step 10: Document and commit**

Update the `sf-org-login` bullet in `README.md` to describe both credential sources and the `instance-url` gotcha.

```bash
git add .github/actions/sf-org-login/action.yml .github/workflows/ci-sf-org-login-smoke.yml README.md
git commit -m "feat(sf-org-login): add credential-source github-env

Credentials can now come straight from GitHub Environment secrets and
variables, not just AWS Secrets Manager. Both sources converge on the
same four env vars so there stays exactly one place that knows how to
run sf org login jwt.

credential-source is introduced now so Phase 8's gcp branch is additive
with no caller churn. The aws default is unchanged and regression-tested."
gh pr create --fill
```

---

## Task 6: `sf-artifact-build` — freeze the deployment artifact

The artifact boundary. Converts source to MDAPI format with replacements applied, then checksums and manifests it. After this action runs, nothing may modify the artifact.

**Files:**

- Create: `shared-github-actions/.github/actions/sf-artifact-build/action.yml`
- Create: `shared-github-actions/.github/workflows/ci-sf-artifact-smoke.yml`

**Interfaces:**

- Consumes: `/opt/sf-ci/versions.json` (Task 1); a `package.xml` path from `sf-source-delta`
- Produces: action `sf-artifact-build` with inputs `manifest-path` (required), `mode` (required, `delta|full`), `environment` (required), `output-dir` (default `artifact`), `base-commit`, `head-commit`; outputs `artifact-path` (string dir), `artifact-name` (string), `artifact-sha256` (hex string), `manifest-sha256` (hex string), `component-count` (integer string). Writes `<output-dir>/deployment.json` with `status: "built"`. Task 7 consumes `artifact-path` and `artifact-sha256`.

- [ ] **Step 1: Write the failing smoke workflow**

Create `shared-github-actions/.github/workflows/ci-sf-artifact-smoke.yml`:

```yaml
---
# Org-free smoke test for sf-artifact-build.
#
# Building an artifact needs no Salesforce org — it is convert + zip +
# checksum — so this runs on every PR without spending org quota. It builds a
# throwaway sfdx project so the test does not depend on any real repo layout.
name: ci-sf-artifact-smoke

on:
  workflow_dispatch:
  pull_request:
    branches: [main]
    paths:
      - ".github/actions/sf-artifact-build/**"
      - ".github/workflows/ci-sf-artifact-smoke.yml"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-artifact:
    name: sf-artifact-build produces a verifiable artifact
    runs-on: ubuntu-latest
    container:
      image: gforceinnovation/sf-ci:1.8.0
      options: --user 1001
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7

      - name: Create a throwaway sfdx project
        run: |
          set -euo pipefail
          git config --global --add safe.directory '*'
          mkdir -p fixture/force-app/main/default/classes
          cd fixture
          cat > sfdx-project.json <<'JSON'
          {
            "packageDirectories": [{ "path": "force-app", "default": true }],
            "namespace": "",
            "sourceApiVersion": "65.0",
            "replacements": [
              {
                "filename": "force-app/main/default/classes/Probe.cls",
                "stringToReplace": "ENDPOINT_PLACEHOLDER",
                "replaceWithEnv": "SF_PROBE_ENDPOINT"
              }
            ]
          }
          JSON
          cat > force-app/main/default/classes/Probe.cls <<'CLS'
          public with sharing class Probe {
              public static final String ENDPOINT = 'ENDPOINT_PLACEHOLDER';
          }
          CLS
          cat > force-app/main/default/classes/Probe.cls-meta.xml <<'META'
          <?xml version="1.0" encoding="UTF-8"?>
          <ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
              <apiVersion>65.0</apiVersion>
              <status>Active</status>
          </ApexClass>
          META
          mkdir -p manifest
          cat > manifest/package.xml <<'XML'
          <?xml version="1.0" encoding="UTF-8"?>
          <Package xmlns="http://soap.sforce.com/2006/04/metadata">
              <types><members>Probe</members><name>ApexClass</name></types>
              <version>65.0</version>
          </Package>
          XML

      - name: Build the artifact
        id: build
        uses: ./.github/actions/sf-artifact-build
        with:
          manifest-path: manifest/package.xml
          source-dir: fixture
          mode: full
          environment: smoke
          output-dir: artifact
          base-commit: 0000000
          head-commit: ${{ github.sha }}
        env:
          SF_PROBE_ENDPOINT: https://smoke.example.com

      - name: Replacement was applied inside the artifact
        run: |
          set -euo pipefail
          CLS="fixture/artifact/mdapi/classes/Probe.cls"
          [ -f "$CLS" ] || { echo "::error::converted class missing at $CLS"; exit 1; }
          grep -q "https://smoke.example.com" "$CLS" \
            || { echo "::error::replacement did not fire"; cat "$CLS"; exit 1; }
          ! grep -q "ENDPOINT_PLACEHOLDER" "$CLS" \
            || { echo "::error::placeholder survived conversion"; exit 1; }
          echo "✅ replacement applied at convert time"

      - name: Checksum output matches the artifact on disk
        env:
          CLAIMED: ${{ steps.build.outputs.artifact-sha256 }}
        run: |
          set -euo pipefail
          cd fixture/artifact
          ACTUAL=$(find mdapi -type f -print0 | sort -z \
            | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
          [ "$ACTUAL" = "$CLAIMED" ] \
            || { echo "::error::sha mismatch: claimed $CLAIMED, actual $ACTUAL"; exit 1; }
          echo "✅ artifact-sha256 is honest"

      - name: Manifest is complete and well-formed
        env:
          NAME: ${{ steps.build.outputs.artifact-name }}
          COUNT: ${{ steps.build.outputs.component-count }}
        run: |
          set -euo pipefail
          M=fixture/artifact/deployment.json
          node -e "JSON.parse(require('fs').readFileSync('$M','utf8'))"
          for KEY in schemaVersion environment deploymentMode dockerImage \
                     toolVersions componentCount artifactSha256 manifestSha256 \
                     artifactName status startedAt; do
            node -pe "
              const m = JSON.parse(require('fs').readFileSync('$M','utf8'));
              if (m['$KEY'] === undefined) { console.error('missing $KEY'); process.exit(1); }
              ''"
          done
          STATUS=$(node -pe "JSON.parse(require('fs').readFileSync('$M','utf8')).status")
          [ "$STATUS" = "built" ] || { echo "::error::status should be 'built', got $STATUS"; exit 1; }
          CLI=$(node -pe "JSON.parse(require('fs').readFileSync('$M','utf8')).toolVersions.salesforceCli")
          [ -n "$CLI" ] || { echo "::error::toolVersions.salesforceCli is empty"; exit 1; }
          [ "$COUNT" = "1" ] || { echo "::error::expected 1 component, got $COUNT"; exit 1; }
          echo "✅ deployment.json complete — name=$NAME cli=$CLI"

      - name: Artifact name is deterministic
        env:
          NAME: ${{ steps.build.outputs.artifact-name }}
        run: |
          set -euo pipefail
          case "$NAME" in
            org-based-smoke-full-*) echo "✅ $NAME" ;;
            *) echo "::error::unexpected artifact name: $NAME"; exit 1 ;;
          esac
```

- [ ] **Step 2: Run actionlint to verify it fails**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-artifact-smoke.yml
```

Expected: FAIL — `action ".github/actions/sf-artifact-build" does not exist`.

- [ ] **Step 3: Write the action**

Create `shared-github-actions/.github/actions/sf-artifact-build/action.yml`:

```yaml
name: "Salesforce Artifact Build"
description: "Convert source to metadata format with replacements applied, then checksum and manifest it"
author: "GForce Innovation"

# THE ARTIFACT BOUNDARY. After this action returns, the contents of
# output-dir are immutable — sf-artifact-deploy verifies the checksum before
# deploying and fails on any mismatch.
#
# Why an explicit convert instead of deploying source directly:
# Salesforce string replacement fires when source format is converted to
# metadata format, and the docs state you cannot use replacements with
# `project deploy start --metadata-dir`. Converting here with
# SF_APPLY_REPLACEMENTS_ON_CONVERT=true is what lets the artifact be frozen
# before deployment while still carrying environment-specific values.
#
# Caller permissions: none beyond the checkout.

inputs:
  manifest-path:
    description: "Path to the package.xml describing what to convert, relative to source-dir"
    required: true
  source-dir:
    description: "sfdx project root containing sfdx-project.json"
    required: false
    default: "."
  mode:
    description: "delta or full — recorded in the manifest and the artifact name"
    required: true
  environment:
    description: "Target environment name, e.g. integration"
    required: true
  output-dir:
    description: "Directory the artifact is written to, relative to source-dir"
    required: false
    default: "artifact"
  destructive-manifest:
    description: |
      Path to destructiveChanges.xml relative to source-dir, or empty when the
      delta contains no deletions. Without this, a component deleted in git is
      silently never removed from the org — the additive manifest simply stops
      mentioning it, and the org keeps it forever.
    required: false
    default: ""
  base-commit:
    description: "Commit the delta was calculated from. Use 0000000 for full mode."
    required: false
    default: "0000000"
  head-commit:
    description: "Commit being deployed"
    required: false
    default: ""

outputs:
  artifact-path:
    description: "Directory holding the frozen artifact"
    value: ${{ steps.build.outputs.artifact-path }}
  artifact-name:
    description: "Deterministic artifact name — org-based-<env>-<mode>-<sha>-<run>"
    value: ${{ steps.build.outputs.artifact-name }}
  artifact-sha256:
    description: "Checksum over every file in mdapi/, order-independent"
    value: ${{ steps.build.outputs.artifact-sha256 }}
  manifest-sha256:
    description: "Checksum of package.xml alone. Comparable across environments because it is independent of env-specific replacements."
    value: ${{ steps.build.outputs.manifest-sha256 }}
  component-count:
    description: "Number of <members> entries in the manifest"
    value: ${{ steps.build.outputs.component-count }}

runs:
  using: "composite"
  steps:
    - name: Validate inputs
      shell: bash
      env:
        MODE: ${{ inputs.mode }}
        SOURCE_DIR: ${{ inputs.source-dir }}
        MANIFEST_PATH: ${{ inputs.manifest-path }}
      run: |
        set -euo pipefail
        case "$MODE" in
          delta|full) ;;
          *) echo "::error::mode must be 'delta' or 'full', got '$MODE'." >&2; exit 1 ;;
        esac
        [ -f "$SOURCE_DIR/sfdx-project.json" ] \
          || { echo "::error::no sfdx-project.json in '$SOURCE_DIR'." >&2; exit 1; }
        [ -f "$SOURCE_DIR/$MANIFEST_PATH" ] \
          || { echo "::error::manifest '$MANIFEST_PATH' not found under '$SOURCE_DIR'." >&2; exit 1; }

    - name: Convert, checksum and manifest
      id: build
      shell: bash
      working-directory: ${{ inputs.source-dir }}
      env:
        MANIFEST_PATH: ${{ inputs.manifest-path }}
        MODE: ${{ inputs.mode }}
        ENVIRONMENT: ${{ inputs.environment }}
        OUTPUT_DIR: ${{ inputs.output-dir }}
        BASE_COMMIT: ${{ inputs.base-commit }}
        HEAD_COMMIT: ${{ inputs.head-commit }}
        DESTRUCTIVE_MANIFEST: ${{ inputs.destructive-manifest }}
      run: |
        set -euo pipefail

        STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        HEAD_SHA="${HEAD_COMMIT:-$GITHUB_SHA}"
        SHORT_SHA="${HEAD_SHA:0:7}"
        ARTIFACT_NAME="org-based-${ENVIRONMENT}-${MODE}-${SHORT_SHA}-${GITHUB_RUN_ID}"

        rm -rf "$OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"

        # The whole point of this action. Without this env var the replacements
        # block is silently ignored on convert and placeholders ship to the org.
        export SF_APPLY_REPLACEMENTS_ON_CONVERT=true
        sf project convert source \
          --manifest "$MANIFEST_PATH" \
          --output-dir "$OUTPUT_DIR/mdapi"

        cp "$MANIFEST_PATH" "$OUTPUT_DIR/mdapi/package.xml"

        # Deletions. `convert source` only ever emits the additive manifest, so
        # without this a component deleted in git is never removed from the org.
        # destructiveChangesPost.xml (not ...Pre) so deletions apply after the
        # additive changes — a component being replaced must exist while its
        # replacement deploys.
        if [ -n "$DESTRUCTIVE_MANIFEST" ] && [ -f "$DESTRUCTIVE_MANIFEST" ]; then
          if grep -q "<members>" "$DESTRUCTIVE_MANIFEST"; then
            cp "$DESTRUCTIVE_MANIFEST" "$OUTPUT_DIR/mdapi/destructiveChangesPost.xml"
            DESTRUCTIVE_COUNT=$(grep -c "<members>" "$DESTRUCTIVE_MANIFEST" || true)
            echo "::notice::Artifact includes $DESTRUCTIVE_COUNT deletion(s)."
          else
            DESTRUCTIVE_COUNT=0
          fi
        else
          DESTRUCTIVE_COUNT=0
        fi

        # Order-independent so the same content always yields the same digest
        # regardless of filesystem traversal order.
        ARTIFACT_SHA=$(cd "$OUTPUT_DIR" && find mdapi -type f -print0 | sort -z \
          | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
        MANIFEST_SHA=$(sha256sum "$MANIFEST_PATH" | cut -d' ' -f1)
        COMPONENT_COUNT=$(grep -c "<members>" "$MANIFEST_PATH" || true)

        (cd "$OUTPUT_DIR" && find mdapi -type f -print0 | sort -z \
          | xargs -0 sha256sum > checksums.txt)

        # Toolchain versions come from the image itself, so the audit record
        # names what actually ran rather than what someone believed was pinned.
        VERSIONS_FILE=/opt/sf-ci/versions.json
        [ -f "$VERSIONS_FILE" ] || { echo "::error::$VERSIONS_FILE missing — needs sf-ci:1.8.0 or later." >&2; exit 1; }

        node -e '
          const fs = require("fs");
          const env = process.env;
          const manifest = {
            schemaVersion: "1.0",
            repository: env.GITHUB_REPOSITORY,
            commit: env.HEAD_SHA,
            baseCommit: env.BASE_COMMIT,
            branch: env.GITHUB_REF_NAME,
            tag: env.GITHUB_REF_TYPE === "tag" ? env.GITHUB_REF_NAME : null,
            workflow: env.GITHUB_WORKFLOW,
            runId: env.GITHUB_RUN_ID,
            runUrl: `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`,
            actor: env.GITHUB_ACTOR,
            environment: env.ENVIRONMENT,
            deploymentMode: env.MODE,
            dockerImage: "gforceinnovation/sf-ci:1.8.0",
            toolVersions: JSON.parse(fs.readFileSync(env.VERSIONS_FILE, "utf8")),
            componentCount: Number(env.COMPONENT_COUNT),
            destructiveCount: Number(env.DESTRUCTIVE_COUNT || 0),
            artifactSha256: env.ARTIFACT_SHA,
            manifestSha256: env.MANIFEST_SHA,
            artifactName: env.ARTIFACT_NAME,
            artifactRetentionDays: Number(env.RETENTION_DAYS || 90),
            salesforceDeployId: null,
            testLevel: null,
            testsRun: [],
            startedAt: env.STARTED_AT,
            completedAt: null,
            status: "built",
          };
          fs.writeFileSync(`${env.OUTPUT_DIR}/deployment.json`, JSON.stringify(manifest, null, 2));
        '

        {
          echo "artifact-path=$OUTPUT_DIR"
          echo "artifact-name=$ARTIFACT_NAME"
          echo "artifact-sha256=$ARTIFACT_SHA"
          echo "manifest-sha256=$MANIFEST_SHA"
          echo "component-count=$COMPONENT_COUNT"
        } >> "$GITHUB_OUTPUT"

        {
          echo "### Artifact built"
          echo ""
          echo "| | |"
          echo "|---|---|"
          echo "| Name | \`$ARTIFACT_NAME\` |"
          echo "| Mode | $MODE |"
          echo "| Components | $COMPONENT_COUNT |"
          echo "| Artifact sha256 | \`$ARTIFACT_SHA\` |"
          echo "| Manifest sha256 | \`$MANIFEST_SHA\` |"
        } >> "$GITHUB_STEP_SUMMARY"
      # HEAD_SHA, ARTIFACT_NAME, ARTIFACT_SHA, MANIFEST_SHA, COMPONENT_COUNT,
      # STARTED_AT and VERSIONS_FILE are shell locals promoted for the node
      # heredoc above via the export below.
```

> **Implementation note for the executor:** the `node -e` block reads shell locals through the environment. Add
> `export HEAD_SHA ARTIFACT_NAME ARTIFACT_SHA MANIFEST_SHA COMPONENT_COUNT DESTRUCTIVE_COUNT STARTED_AT VERSIONS_FILE OUTPUT_DIR BASE_COMMIT ENVIRONMENT MODE`
> on the line immediately before the `node -e` invocation. Without it, every field derived from a local is `undefined` and the smoke test's manifest assertions fail.

- [ ] **Step 3b: Add a deletion test to the smoke workflow**

A deletion that silently never reaches the org is the worst kind of failure — the pipeline reports success and the org quietly diverges. Append to the `build-artifact` job in `ci-sf-artifact-smoke.yml`, after the _Create a throwaway sfdx project_ step:

```yaml
- name: Add a destructive manifest to the fixture
  run: |
    set -euo pipefail
    mkdir -p fixture/manifest
    cat > fixture/manifest/destructiveChanges.xml <<'XML'
    <?xml version="1.0" encoding="UTF-8"?>
    <Package xmlns="http://soap.sforce.com/2006/04/metadata">
        <types><members>Obsolete</members><name>ApexClass</name></types>
        <version>65.0</version>
    </Package>
    XML
```

Pass it to the build step by adding `destructive-manifest: manifest/destructiveChanges.xml` to that step's `with:` block, then add this assertion after the checksum check:

```yaml
- name: Deletions are carried into the artifact
  run: |
    set -euo pipefail
    D=fixture/artifact/mdapi/destructiveChangesPost.xml
    [ -f "$D" ] || { echo "::error::destructiveChangesPost.xml missing — deletions would never reach the org"; exit 1; }
    grep -q "<members>Obsolete</members>" "$D" \
      || { echo "::error::deletion member missing from $D"; exit 1; }
    COUNT=$(node -pe "JSON.parse(require('fs').readFileSync('fixture/artifact/deployment.json','utf8')).destructiveCount")
    [ "$COUNT" = "1" ] || { echo "::error::destructiveCount should be 1, got $COUNT"; exit 1; }
    echo "✅ deletions carried into the artifact and recorded in the manifest"
```

- [ ] **Step 4: Run actionlint and the smoke workflow**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-artifact-smoke.yml
git checkout -b feat/sf-artifact-actions
git add .github/actions/sf-artifact-build .github/workflows/ci-sf-artifact-smoke.yml
git commit -m "feat(sf-artifact-build): freeze the deployment artifact"
git push -u origin feat/sf-artifact-actions
gh workflow run ci-sf-artifact-smoke.yml --ref feat/sf-artifact-actions
gh run watch --exit-status
```

Expected: PASS on all five assertion steps.

- [ ] **Step 5: Verify the replacement gate actually fails when it should**

Temporarily set `allowUnsetEnvVariable` behaviour by removing `SF_PROBE_ENDPOINT` from the smoke workflow's `env:` block, push, and re-run.

Expected: the build step FAILS. This confirms a missing environment value stops the build rather than shipping a placeholder to an org. Restore the `env:` block afterwards.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test(sf-artifact-build): confirm unset replacement env fails the build"
```

---

## Task 7: `sf-artifact-deploy` — verify then deploy

**Files:**

- Create: `shared-github-actions/.github/actions/sf-artifact-deploy/action.yml`
- Modify: `shared-github-actions/.github/workflows/ci-sf-artifact-smoke.yml`

**Interfaces:**

- Consumes: `artifact-path` and `artifact-sha256` from Task 6; an authenticated org alias from Task 5
- Produces: action `sf-artifact-deploy` with inputs `artifact-path` (required), `expected-sha256` (required), `org-alias` (required), `test-level` (default `RunLocalTests`), `tests` (default `""`), `wait` (default `30`); outputs `deploy-id` (string), `status` (string). Updates `deployment.json` in place with `salesforceDeployId`, `testLevel`, `testsRun`, `completedAt`, `status`.

- [ ] **Step 1: Write the failing tamper test**

Append a job to `ci-sf-artifact-smoke.yml`:

```yaml
reject-tampered-artifact:
  name: sf-artifact-deploy rejects a tampered artifact
  runs-on: ubuntu-latest
  container:
    image: gforceinnovation/sf-ci:1.8.0
    options: --user 1001
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@v7

    - name: Build a minimal artifact directory
      run: |
        set -euo pipefail
        mkdir -p art/mdapi/classes
        echo 'public class A {}' > art/mdapi/classes/A.cls
        cat > art/deployment.json <<'JSON'
        { "schemaVersion": "1.0", "status": "built", "testsRun": [] }
        JSON
        GOOD=$(cd art && find mdapi -type f -print0 | sort -z \
          | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
        echo "GOOD_SHA=$GOOD" >> "$GITHUB_ENV"

    - name: Tamper with the artifact after checksumming
      run: echo 'public class Evil {}' > art/mdapi/classes/Evil.cls

    - name: Deploy must refuse the tampered artifact
      id: deploy
      continue-on-error: true
      uses: ./.github/actions/sf-artifact-deploy
      with:
        artifact-path: art
        expected-sha256: ${{ env.GOOD_SHA }}
        org-alias: nonexistent
        test-level: NoTestRun

    - name: Assert it failed on the checksum, not on the org
      run: |
        set -euo pipefail
        [ "${{ steps.deploy.outcome }}" = "failure" ] \
          || { echo "::error::tampered artifact was accepted"; exit 1; }
        echo "✅ checksum mismatch blocked the deploy"
```

- [ ] **Step 2: Run actionlint to verify it fails**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-artifact-smoke.yml
```

Expected: FAIL — `action ".github/actions/sf-artifact-deploy" does not exist`.

- [ ] **Step 3: Write the action**

Create `shared-github-actions/.github/actions/sf-artifact-deploy/action.yml`:

```yaml
name: "Salesforce Artifact Deploy"
description: "Verify a frozen artifact's checksum, then deploy it with --metadata-dir"
author: "GForce Innovation"

# The consuming half of the artifact boundary. This action deliberately has no
# access to source: it takes a directory built by sf-artifact-build and
# deploys exactly those bytes. The checksum check is what makes "the artifact
# deployed is the artifact stored" an enforced property rather than a claim.
#
# Caller permissions: none. Requires a prior sf-org-login.

inputs:
  artifact-path:
    description: "Directory produced by sf-artifact-build"
    required: true
  expected-sha256:
    description: "artifact-sha256 emitted by sf-artifact-build"
    required: true
  org-alias:
    description: "Alias of an already-authenticated org"
    required: true
  test-level:
    description: "NoTestRun | RunSpecifiedTests | RunLocalTests | RunAllTestsInOrg"
    required: false
    default: "RunLocalTests"
  tests:
    description: "Space-separated test classes. Required when test-level is RunSpecifiedTests."
    required: false
    default: ""
  wait:
    description: "Minutes to wait for the deployment"
    required: false
    default: "30"

outputs:
  deploy-id:
    description: "Salesforce deployment id (0Af...)"
    value: ${{ steps.deploy.outputs.deploy-id }}
  status:
    description: "Succeeded or Failed"
    value: ${{ steps.deploy.outputs.status }}

runs:
  using: "composite"
  steps:
    # Runs before anything touches an org, so a tampered artifact costs no
    # deployment slot and cannot partially apply.
    - name: Verify the artifact checksum
      shell: bash
      env:
        ARTIFACT_PATH: ${{ inputs.artifact-path }}
        EXPECTED: ${{ inputs.expected-sha256 }}
      run: |
        set -euo pipefail
        [ -d "$ARTIFACT_PATH/mdapi" ] \
          || { echo "::error::no mdapi/ directory in '$ARTIFACT_PATH'." >&2; exit 1; }
        ACTUAL=$(cd "$ARTIFACT_PATH" && find mdapi -type f -print0 | sort -z \
          | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
        if [ "$ACTUAL" != "$EXPECTED" ]; then
          echo "::error::Artifact checksum mismatch. Expected $EXPECTED, got $ACTUAL. The artifact was modified after it was built; refusing to deploy." >&2
          exit 1
        fi
        echo "✅ artifact checksum verified: $ACTUAL"

    - name: Deploy the artifact
      id: deploy
      shell: bash
      env:
        ARTIFACT_PATH: ${{ inputs.artifact-path }}
        ORG_ALIAS: ${{ inputs.org-alias }}
        TEST_LEVEL: ${{ inputs.test-level }}
        TESTS: ${{ inputs.tests }}
        WAIT: ${{ inputs.wait }}
      run: |
        set -euo pipefail

        ARGS=(
          --metadata-dir "$ARTIFACT_PATH/mdapi"
          --target-org "$ORG_ALIAS"
          --test-level "$TEST_LEVEL"
          --wait "$WAIT"
          --json
        )
        if [ "$TEST_LEVEL" = "RunSpecifiedTests" ]; then
          if [ -z "$TESTS" ]; then
            echo "::error::test-level RunSpecifiedTests needs a non-empty 'tests' input." >&2
            exit 1
          fi
          for T in $TESTS; do ARGS+=(--tests "$T"); done
        fi

        set +e
        sf project deploy start "${ARGS[@]}" > deploy-result.json
        DEPLOY_RC=$?
        set -e

        DEPLOY_ID=$(node -pe "
          try { JSON.parse(require('fs').readFileSync('deploy-result.json','utf8')).result.id ?? '' }
          catch (e) { '' }")
        STATUS=$(node -pe "
          try { JSON.parse(require('fs').readFileSync('deploy-result.json','utf8')).result.status ?? 'Failed' }
          catch (e) { 'Failed' }")

        {
          echo "deploy-id=$DEPLOY_ID"
          echo "status=$STATUS"
        } >> "$GITHUB_OUTPUT"

        if [ "$DEPLOY_RC" -ne 0 ] || [ "$STATUS" != "Succeeded" ]; then
          echo "::error::Deployment $DEPLOY_ID finished with status '$STATUS'." >&2
          node -pe "
            try {
              const r = JSON.parse(require('fs').readFileSync('deploy-result.json','utf8'));
              (r.result.details?.componentFailures ?? [])
                .map(f => \`\${f.componentType} \${f.fullName}: \${f.problem}\`).join('\n')
            } catch (e) { '' }" >&2
          exit 1
        fi
        echo "✅ deployed $DEPLOY_ID"

    # Finalises the audit record. Runs on failure too, so a failed deployment
    # is recorded rather than leaving the manifest stuck at "built".
    - name: Finalise the deployment manifest
      if: always()
      shell: bash
      env:
        ARTIFACT_PATH: ${{ inputs.artifact-path }}
        DEPLOY_ID: ${{ steps.deploy.outputs.deploy-id }}
        STATUS: ${{ steps.deploy.outputs.status }}
        TEST_LEVEL: ${{ inputs.test-level }}
        TESTS: ${{ inputs.tests }}
      run: |
        set -euo pipefail
        M="$ARTIFACT_PATH/deployment.json"
        [ -f "$M" ] || exit 0
        node -e '
          const fs = require("fs");
          const p = process.env.M;
          const m = JSON.parse(fs.readFileSync(p, "utf8"));
          m.salesforceDeployId = process.env.DEPLOY_ID || null;
          m.testLevel = process.env.TEST_LEVEL;
          m.testsRun = (process.env.TESTS || "").split(" ").filter(Boolean);
          m.completedAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
          m.status = process.env.STATUS === "Succeeded" ? "success" : "failed";
          fs.writeFileSync(p, JSON.stringify(m, null, 2));
        '
        rm -f deploy-result.json
      env:
        M: ${{ inputs.artifact-path }}/deployment.json
```

> **Implementation note:** a step may declare `env:` only once. Merge the two `env:` blocks on the final step into one containing `ARTIFACT_PATH`, `DEPLOY_ID`, `STATUS`, `TEST_LEVEL`, `TESTS` and `M`.

- [ ] **Step 4: Run actionlint and the smoke workflow**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/ci-sf-artifact-smoke.yml
git add .github/actions/sf-artifact-deploy .github/workflows/ci-sf-artifact-smoke.yml
git commit -m "feat(sf-artifact-deploy): verify checksum before deploying"
git push
gh workflow run ci-sf-artifact-smoke.yml --ref feat/sf-artifact-actions
gh run watch --exit-status
```

Expected: PASS. `reject-tampered-artifact` must show `✅ checksum mismatch blocked the deploy`.

---

## Task 8: `sf-env-config-apply` — inject secrets after deployment

Custom Metadata records are metadata, not data, so they cannot be upserted through the Data API. This action renders a template with the environment's secrets and deploys just that file, then shreds the rendered copy.

**Files:**

- Create: `shared-github-actions/.github/actions/sf-env-config-apply/action.yml`

**Interfaces:**

- Consumes: an authenticated org alias (Task 5); environment secrets exposed as env vars by the caller
- Produces: action `sf-env-config-apply` with inputs `template-dir` (required), `org-alias` (required), `api-version` (default `65.0`); output `records-applied` (integer string)

- [ ] **Step 1: Write the failing local render test**

Create a scratch harness to drive the render logic without an org:

```bash
cd ~/gforce/shared-github-actions
mkdir -p /tmp/cfg-test/customMetadata
cat > /tmp/cfg-test/customMetadata/Probe.Demo.md-meta.xml.tpl <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Demo</label>
    <values><field>Secret__c</field><value xsi:type="xsd:string">${DEMO_SECRET}</value></values>
</CustomMetadata>
EOF
DEMO_SECRET=s3cr3t envsubst < /tmp/cfg-test/customMetadata/Probe.Demo.md-meta.xml.tpl | grep -q s3cr3t \
  && echo "envsubst available" || echo "FAIL: install gettext"
```

Expected: `envsubst available`. If not, the action must fall back to `sed`; note it in Step 3.

- [ ] **Step 2: Write the action**

Create `shared-github-actions/.github/actions/sf-env-config-apply/action.yml`:

```yaml
name: "Salesforce Environment Config Apply"
description: "Render secret-bearing Custom Metadata from templates and deploy it"
author: "GForce Innovation"

# Why this exists rather than baking secrets into the artifact:
# the deployment artifact is uploaded and retained, so anything inside it is
# retained too. Custom Metadata records are metadata, not data, so they cannot
# be upserted through the Data API — they have to be deployed. This action
# renders templates with the environment's secrets, deploys only those files,
# and shreds the rendered copies.
#
# Templates are *.md-meta.xml.tpl with ${VAR} placeholders. Values come from
# the environment, which the caller populates from GitHub Environment secrets.
#
# Caller permissions: none. Requires a prior sf-org-login.

inputs:
  template-dir:
    description: "Directory containing customMetadata/*.md-meta.xml.tpl"
    required: true
  org-alias:
    description: "Alias of an already-authenticated org"
    required: true
  api-version:
    description: "Metadata API version for the generated package.xml"
    required: false
    default: "65.0"

outputs:
  records-applied:
    description: "Number of custom metadata records deployed"
    value: ${{ steps.apply.outputs.records-applied }}

runs:
  using: "composite"
  steps:
    - name: Render and deploy
      id: apply
      shell: bash
      env:
        TEMPLATE_DIR: ${{ inputs.template-dir }}
        ORG_ALIAS: ${{ inputs.org-alias }}
        API_VERSION: ${{ inputs.api-version }}
      run: |
        set -euo pipefail
        umask 077

        if [ ! -d "$TEMPLATE_DIR/customMetadata" ]; then
          echo "No customMetadata templates in '$TEMPLATE_DIR' — nothing to apply."
          echo "records-applied=0" >> "$GITHUB_OUTPUT"
          exit 0
        fi

        RENDER_DIR=$(mktemp -d)
        # Shred on every exit path, including failure. These files hold real
        # secrets in plaintext for the duration of the deploy.
        trap 'rm -rf "$RENDER_DIR"' EXIT

        mkdir -p "$RENDER_DIR/customMetadata"
        COUNT=0
        MEMBERS=""

        for TPL in "$TEMPLATE_DIR"/customMetadata/*.md-meta.xml.tpl; do
          [ -e "$TPL" ] || continue
          BASE=$(basename "$TPL" .tpl)
          envsubst < "$TPL" > "$RENDER_DIR/customMetadata/$BASE"

          # An unresolved placeholder means a secret was not wired up. Shipping
          # a literal ${VAR} into an org is worse than failing here.
          if grep -q '\${' "$RENDER_DIR/customMetadata/$BASE"; then
            echo "::error::Unresolved placeholder in $BASE — an expected environment value is missing." >&2
            exit 1
          fi

          MEMBER="${BASE%.md-meta.xml}"
          MEMBERS="$MEMBERS    <members>$MEMBER</members>"$'\n'
          COUNT=$((COUNT + 1))
        done

        if [ "$COUNT" -eq 0 ]; then
          echo "No templates matched — nothing to apply."
          echo "records-applied=0" >> "$GITHUB_OUTPUT"
          exit 0
        fi

        cat > "$RENDER_DIR/package.xml" <<XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Package xmlns="http://soap.sforce.com/2006/04/metadata">
            <types>
        $MEMBERS        <name>CustomMetadata</name>
            </types>
            <version>$API_VERSION</version>
        </Package>
        XML

        # NoTestRun: this deploys configuration records only, and the artifact
        # deployment immediately before already ran the test policy.
        sf project deploy start \
          --metadata-dir "$RENDER_DIR" \
          --target-org "$ORG_ALIAS" \
          --test-level NoTestRun \
          --wait 10 \
          --json > /dev/null

        echo "records-applied=$COUNT" >> "$GITHUB_OUTPUT"
        echo "✅ applied $COUNT custom metadata record(s)"

    - name: Assert nothing rendered survived
      if: always()
      shell: bash
      run: |
        set -euo pipefail
        LEFT=$(find /tmp -maxdepth 2 -name '*.md-meta.xml' -newermt '-10 minutes' 2>/dev/null | wc -l | tr -d ' ')
        [ "$LEFT" = "0" ] || echo "::warning::$LEFT rendered metadata file(s) may remain under /tmp"
```

- [ ] **Step 3: Verify envsubst exists in the image**

```bash
docker run --rm gforceinnovation/sf-ci:1.8.0 bash -c 'command -v envsubst || echo MISSING'
```

If `MISSING`, add `gettext-base` to the `apt-get install` list in `sf-ci/Dockerfile`, rebuild, and ship it as a patch release `1.8.1`. Update the image tag everywhere in this plan if so.

- [ ] **Step 4: Run actionlint and commit**

```bash
cd ~/gforce/shared-github-actions
actionlint
npm run all
git add .github/actions/sf-env-config-apply
git commit -m "feat(sf-env-config-apply): deploy secret-bearing custom metadata

Keeps secrets out of the retained artifact. Custom Metadata records are
metadata, not data, so they cannot be upserted via the Data API — they
are rendered from templates and deployed, then shredded via an EXIT trap.
An unresolved placeholder fails the step rather than shipping a literal
\${VAR} into the org."
gh pr create --fill
```

---

## Task 9: `reusable-sf-org-deploy.yml` — the engine

Two jobs. The job boundary is the artifact boundary: the deploy job has no `actions/checkout` and therefore cannot regenerate the source.

**Files:**

- Create: `shared-github-actions/.github/workflows/reusable-sf-org-deploy.yml`
- Create: `shared-github-actions/examples/reusable-sf-org-deploy.yml`

**Interfaces:**

- Consumes: `sf-source-delta`, `sf-apex-test-select` (existing); `sf-artifact-build` (Task 6), `sf-artifact-deploy` (Task 7), `sf-env-config-apply` (Task 8), `sf-org-login` (Task 5)
- Produces: reusable workflow with inputs `environment` (required string), `mode` (string, default `delta`), `container-image` (string, default `gforceinnovation/sf-ci:1.8.0`), `container-user` (string, default `1001`), `source-dir` (string, default `.`), `secret-template-dir` (string, default `config/secret-templates`), `retention-days` (number, default `90`); secrets `sf-jwt-key-b64`, `sf-client-id`; outputs `artifact-name`, `deploy-id`, `component-count`

- [ ] **Step 1: Write the failing workflow skeleton**

Create `shared-github-actions/.github/workflows/reusable-sf-org-deploy.yml` with only the `on:` block and an empty `jobs:` map, then lint:

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/reusable-sf-org-deploy.yml
```

Expected: FAIL — `"jobs" section is missing or empty`.

- [ ] **Step 2: Write the build job**

```yaml
---
# The org-based deployment engine.
#
# Two jobs, and the job boundary IS the artifact boundary:
#
#   build   checkout -> delta -> convert (replacements) -> freeze -> upload
#   deploy  download -> verify checksum -> deploy -> apply secrets -> tag
#
# The deploy job runs NO actions/checkout. It structurally cannot regenerate
# the deployment source, which is what makes "build once, deploy the same
# artifact" an enforced property rather than a documented intention.
#
# The delta base is the deployed/<env> tag, force-moved only on success. A
# failed deployment therefore leaves the base unchanged and the next run
# recomputes an identical delta, which is what makes retries idempotent.
name: Salesforce Org Deploy (Reusable)

on:
  workflow_call:
    inputs:
      environment:
        description: "GitHub Environment and Salesforce target, e.g. integration"
        required: true
        type: string
      mode:
        description: "delta (from deployed/<env>) or full (every package directory)"
        required: false
        type: string
        default: "delta"
      container-image:
        required: false
        type: string
        default: "gforceinnovation/sf-ci:1.8.0"
      container-user:
        required: false
        type: string
        default: "1001"
      source-dir:
        required: false
        type: string
        default: "."
      secret-template-dir:
        required: false
        type: string
        default: "config/secret-templates"
      retention-days:
        required: false
        type: number
        default: 90
    secrets:
      sf-jwt-key-b64:
        required: true
      sf-client-id:
        required: true
    outputs:
      artifact-name:
        value: ${{ jobs.build.outputs.artifact-name }}
      component-count:
        value: ${{ jobs.build.outputs.component-count }}
      deploy-id:
        value: ${{ jobs.deploy.outputs.deploy-id }}

# One deployment per environment at a time. cancel-in-progress stays false:
# cancelling mid-deploy leaves the org partially updated with no record.
concurrency:
  group: sf-org-deploy-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  build:
    name: Build artifact for ${{ inputs.environment }}
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    container:
      image: ${{ inputs.container-image }}
      options: --user ${{ inputs.container-user }}
    permissions:
      contents: read
    outputs:
      artifact-name: ${{ steps.build.outputs.artifact-name }}
      artifact-sha256: ${{ steps.build.outputs.artifact-sha256 }}
      # From sf-artifact-build, not from the delta step — in full mode the
      # delta step is skipped and its output is empty.
      component-count: ${{ steps.build.outputs.component-count }}
      tests: ${{ steps.tests.outputs.tests }}
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          fetch-depth: 0
          submodules: recursive

      - name: Trust the workspace
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"

      # Non-secret, committed, per-environment values consumed by the
      # replacements block at convert time.
      - name: Load environment config
        env:
          ENVIRONMENT: ${{ inputs.environment }}
          SOURCE_DIR: ${{ inputs.source-dir }}
        run: |
          set -euo pipefail
          CONFIG="$SOURCE_DIR/config/environments/$ENVIRONMENT.json"
          [ -f "$CONFIG" ] || { echo "::error::missing $CONFIG"; exit 1; }
          node -e '
            const cfg = JSON.parse(require("fs").readFileSync(process.env.CONFIG, "utf8"));
            const out = require("fs").createWriteStream(process.env.GITHUB_ENV, { flags: "a" });
            for (const [k, v] of Object.entries(cfg)) out.write(`${k}=${v}\n`);
          '
          echo "✅ loaded $(node -pe "Object.keys(JSON.parse(require('fs').readFileSync('$CONFIG','utf8'))).length") value(s)"
        # CONFIG is referenced by the node script above.

      # The first deploy to a new org has no deployed/<env> tag. Falling back
      # to full is correct: an empty org needs everything anyway.
      - name: Resolve the delta base
        id: base
        env:
          ENVIRONMENT: ${{ inputs.environment }}
          MODE: ${{ inputs.mode }}
        run: |
          set -euo pipefail
          TAG="deployed/$ENVIRONMENT"
          EFFECTIVE_MODE="$MODE"
          BASE=""
          if [ "$MODE" = "delta" ]; then
            if git rev-parse --verify --quiet "refs/tags/$TAG^{commit}" > /dev/null; then
              BASE=$(git rev-parse "refs/tags/$TAG")
              echo "Delta base: $TAG ($BASE)"
            else
              echo "::notice::No $TAG tag yet — first deployment to this org, falling back to full mode."
              EFFECTIVE_MODE="full"
            fi
          fi
          {
            echo "effective-mode=$EFFECTIVE_MODE"
            echo "base-commit=${BASE:-0000000}"
          } >> "$GITHUB_OUTPUT"

      - name: Calculate the delta
        id: delta
        if: steps.base.outputs.effective-mode == 'delta'
        uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-source-delta@v2
        with:
          from-ref: ${{ steps.base.outputs.base-commit }}
          to-ref: ${{ github.sha }}
          source-dir: ${{ inputs.source-dir }}
          output-dir: delta

      - name: Generate a full manifest
        id: full
        if: steps.base.outputs.effective-mode == 'full'
        env:
          SOURCE_DIR: ${{ inputs.source-dir }}
        run: |
          set -euo pipefail
          mkdir -p delta/package
          sf project generate manifest \
            --source-dir "$SOURCE_DIR" \
            --name delta/package/package \
            --api-version 65.0
          COUNT=$(grep -c "<members>" delta/package/package.xml || true)
          echo "component-count=$COUNT" >> "$GITHUB_OUTPUT"

      - name: Stop early when nothing changed
        id: gate
        env:
          MODE: ${{ steps.base.outputs.effective-mode }}
          HAS_CHANGES: ${{ steps.delta.outputs.has-changes }}
        run: |
          set -euo pipefail
          if [ "$MODE" = "delta" ] && [ "$HAS_CHANGES" != "true" ]; then
            echo "::notice::No deployable metadata changed since the last deployment."
            echo "skip=true" >> "$GITHUB_OUTPUT"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Select the Apex tests to run
        id: tests
        if: steps.gate.outputs.skip != 'true'
        uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-apex-test-select@v2
        with:
          package-xml: delta/package/package.xml
          source-dir: ${{ inputs.source-dir }}

      - name: Build the artifact
        id: build
        if: steps.gate.outputs.skip != 'true'
        uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-artifact-build@v2
        with:
          manifest-path: delta/package/package.xml
          source-dir: ${{ inputs.source-dir }}
          mode: ${{ steps.base.outputs.effective-mode }}
          environment: ${{ inputs.environment }}
          output-dir: artifact
          base-commit: ${{ steps.base.outputs.base-commit }}
          head-commit: ${{ github.sha }}
          # sfdx-git-delta writes this whether or not there are deletions; the
          # action no-ops when the file is absent or has no members. Only the
          # delta path produces one — a full deploy deletes nothing.
          destructive-manifest: ${{ steps.base.outputs.effective-mode == 'delta' && 'delta/destructiveChanges/destructiveChanges.xml' || '' }}

      # Load-bearing: this is the gate that keeps secrets out of a retained
      # artifact. It runs before upload, never after.
      - name: Scan the artifact for secrets
        if: steps.gate.outputs.skip != 'true'
        env:
          SOURCE_DIR: ${{ inputs.source-dir }}
        run: |
          set -euo pipefail
          if gitleaks dir "$SOURCE_DIR/artifact" --no-banner --redact; then
            echo "✅ no secrets detected in the artifact"
          else
            echo "::error::gitleaks found a secret in the deployment artifact. Not uploading. A secret belongs in sf-env-config-apply, never in the artifact." >&2
            exit 1
          fi

      - name: Upload the artifact
        if: steps.gate.outputs.skip != 'true'
        uses: actions/upload-artifact@v8
        with:
          name: ${{ steps.build.outputs.artifact-name }}
          path: ${{ inputs.source-dir }}/artifact
          retention-days: ${{ inputs.retention-days }}
          if-no-files-found: error
```

- [ ] **Step 3: Write the deploy job**

Append to the same file:

```yaml
deploy:
  name: Deploy to ${{ inputs.environment }}
  needs: build
  if: needs.build.outputs.artifact-name != ''
  runs-on: ubuntu-latest
  environment:
    name: ${{ inputs.environment }}
    url: ${{ steps.login.outputs.instance-url }}
  container:
    image: ${{ inputs.container-image }}
    options: --user ${{ inputs.container-user }}
  permissions:
    contents: write # moves the deployed/<env> tag
  outputs:
    deploy-id: ${{ steps.deploy.outputs.deploy-id }}
  steps:
    # NOTE: deliberately no actions/checkout. This job must not be able to
    # regenerate the deployment source. Everything it deploys arrives as the
    # artifact built above. The only git operation is the tag move at the
    # end, which uses a bare clone rather than a working tree.
    - name: Download the artifact
      uses: actions/download-artifact@v8
      with:
        name: ${{ needs.build.outputs.artifact-name }}
        path: artifact

    - name: Authenticate
      id: login
      uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-org-login@v2
      with:
        credential-source: github-env
        auth-method: jwt
        jwt-key-b64: ${{ secrets.sf-jwt-key-b64 }}
        client-id: ${{ secrets.sf-client-id }}
        username: ${{ vars.SF_USERNAME }}
        instance-url: ${{ vars.SF_INSTANCE_URL }}
        org-alias: target

    - name: Deploy the artifact
      id: deploy
      uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-artifact-deploy@v2
      with:
        artifact-path: artifact
        expected-sha256: ${{ needs.build.outputs.artifact-sha256 }}
        org-alias: target
        test-level: ${{ needs.build.outputs.tests != '' && 'RunSpecifiedTests' || 'RunLocalTests' }}
        tests: ${{ needs.build.outputs.tests }}

    - name: Apply environment secrets
      uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-env-config-apply@v2
      with:
        template-dir: ${{ inputs.secret-template-dir }}
        org-alias: target
      env:
        GITHUB_APP_KEY_B64: ${{ secrets.GITHUB_APP_KEY_B64 }}
        OWM_API_KEY: ${{ secrets.OWM_API_KEY }}

    # Only on success. A failed deployment must leave the base where it was,
    # so the next attempt recomputes the same delta instead of skipping the
    # components that never landed.
    - name: Move the deployment marker
      env:
        ENVIRONMENT: ${{ inputs.environment }}
        GH_TOKEN: ${{ github.token }}
      run: |
        set -euo pipefail
        TAG="deployed/$ENVIRONMENT"
        git config --global --add safe.directory '*'
        git clone --bare --depth 1 \
          "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" marker.git
        cd marker.git
        git tag -f "$TAG" "$GITHUB_SHA"
        git push --force origin "refs/tags/$TAG"
        echo "✅ $TAG now points at $GITHUB_SHA"

    - name: Publish the deployment summary
      if: always()
      env:
        ENVIRONMENT: ${{ inputs.environment }}
        ARTIFACT: ${{ needs.build.outputs.artifact-name }}
        COMPONENTS: ${{ needs.build.outputs.component-count }}
        DEPLOY_ID: ${{ steps.deploy.outputs.deploy-id }}
        INSTANCE_URL: ${{ steps.login.outputs.instance-url }}
      run: |
        set -euo pipefail
        {
          echo "# Salesforce deployment — $ENVIRONMENT"
          echo ""
          echo "| | |"
          echo "|---|---|"
          echo "| Commit | \`${GITHUB_SHA:0:7}\` |"
          echo "| Actor | @$GITHUB_ACTOR |"
          echo "| Artifact | \`$ARTIFACT\` |"
          echo "| Components | ${COMPONENTS:-0} |"
          echo "| Salesforce deploy id | \`${DEPLOY_ID:-n/a}\` |"
          echo "| Org | $INSTANCE_URL |"
          echo "| Run | ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID} |"
        } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 4: Lint and verify the checkout invariant**

```bash
cd ~/gforce/shared-github-actions
actionlint .github/workflows/reusable-sf-org-deploy.yml

# The invariant that makes the artifact boundary real.
awk '/^  deploy:/,0' .github/workflows/reusable-sf-org-deploy.yml \
  | grep -q "actions/checkout" \
  && { echo "FAIL: deploy job checks out source"; exit 1; } \
  || echo "✅ deploy job has no checkout"
```

Expected: actionlint silent; `✅ deploy job has no checkout`.

- [ ] **Step 5: Write the caller example**

Create `shared-github-actions/examples/reusable-sf-org-deploy.yml` showing an integration caller and a gated production caller, matching the style of the existing `examples/reusable-sf-release.yml`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/reusable-sf-org-deploy.yml examples/reusable-sf-org-deploy.yml
git commit -m "feat(reusable-sf-org-deploy): org-based deployment engine

Two jobs where the job boundary is the artifact boundary. The deploy job
declares no actions/checkout, so it structurally cannot regenerate the
deployment source.

The deployed/<env> tag is the delta base and moves only on success, so a
failed deployment leaves the base unchanged and the next run recomputes
an identical delta. A missing tag falls back to full mode, which is what
a first deployment to an empty org needs anyway."
```

---

## Task 10: Containerize `reusable-sf-code-analyze.yml`

Static analysis currently runs on `ubuntu-latest` with `setup-node`/`setup-java`/`setup-python`, making the runner the source of tool versions. Spec §2.3 requires the image to be that source.

**Files:**

- Modify: `shared-github-actions/.github/workflows/reusable-sf-code-analyze.yml`

**Interfaces:**

- Consumes: `sf-ci:1.8.0` with Code Analyzer (Task 2)
- Produces: unchanged workflow outputs `exit-code`, `num-violations`; inputs `node-version`, `java-version`, `python-version` removed; inputs `container-image`, `container-user` added

- [ ] **Step 1: Record the current behaviour**

```bash
cd ~/gforce/shared-github-actions
gh workflow run ci.yml --ref main
gh run watch --exit-status
```

Note the current `num-violations` on a known commit so the containerized version can be compared against it.

- [ ] **Step 2: Replace the setup steps with a container**

In `reusable-sf-code-analyze.yml`: delete the `node-version`, `java-version` and `python-version` inputs; add `container-image` (default `gforceinnovation/sf-ci:1.8.0`) and `container-user` (default `1001`); add a `container:` block to the `analyze` job; delete the `actions/setup-node`, `actions/setup-java`, `actions/setup-python` steps and any step that installs the Code Analyzer plugin at runtime.

Add this comment above the `container:` block:

```yaml
# The image is the source of tool versions, not the runner. Installing
# Node/Java/Python here would mean a green run on ubuntu-latest could go
# red purely because GitHub bumped a default, with no change on our side.
```

- [ ] **Step 3: Lint and run**

```bash
actionlint .github/workflows/reusable-sf-code-analyze.yml
gh workflow run ci.yml --ref feat/containerize-code-analyze
gh run watch --exit-status
```

Expected: PASS with the same `num-violations` recorded in Step 1. A different count means the pinned Code Analyzer differs from the runner's — investigate before merging rather than accepting the new number.

- [ ] **Step 4: Check for callers passing removed inputs**

```bash
grep -rn "node-version\|java-version\|python-version" \
  --include="*.yml" .github/workflows examples/ || echo "no callers pass the removed inputs"
```

Fix any caller found.

- [ ] **Step 5: Commit, tag and release**

```bash
git add .github/workflows/reusable-sf-code-analyze.yml
git commit -m "refactor(code-analyze): run inside sf-ci instead of ubuntu-latest

The runner was the source of tool versions, so a green run could go red
because GitHub bumped a default. The pinned image is now the only source."
gh pr create --fill
```

After merge, move the floating `v2` tag so consumer `@v2` refs resolve to the new actions:

```bash
git checkout main && git pull
git tag -f v2 && git push --force origin v2
git tag -a v2.1.0 -m "Org-based deployment engine: artifact actions, github-env credentials, containerized analysis"
git push origin v2.1.0
```

---

## Task 11: Environment config and replacements in sf-develop-demo

**Files:**

- Create: `sf-develop-demo/config/environments/integration.json`
- Create: `sf-develop-demo/config/environments/production.json`
- Create: `sf-develop-demo/config/secret-templates/customMetadata/GitHub_App_Settings.demo.md-meta.xml.tpl`
- Modify: `sf-develop-demo/sfdx-project.json`

**Interfaces:**

- Consumes: nothing
- Produces: `config/environments/<env>.json` read by Task 9's build job; `config/secret-templates/` read by Task 8

- [ ] **Step 1: Record the current replacements block**

```bash
cd ~/gforce/sf-develop-demo
node -pe "JSON.stringify(require('./sfdx-project.json').replacements, null, 2)"
```

Expected: one entry replacing `GITHUB_PRIVATE_KEY_BASE64_PLACEHOLDER` from `$GITHUB_PRIVATE_KEY_BASE64`. That is a secret being baked into the artifact — exactly what D2 forbids.

- [ ] **Step 2: Write the environment config files**

`config/environments/integration.json`:

```json
{
  "SF_NAMED_CRED_GITHUB_ENDPOINT": "https://api.github.com",
  "SF_NAMED_CRED_OWM_ENDPOINT": "https://api.openweathermap.org",
  "SF_ENV_LABEL": "DEMO-INTEGRATION"
}
```

`config/environments/production.json`:

```json
{
  "SF_NAMED_CRED_GITHUB_ENDPOINT": "https://api.github.com",
  "SF_NAMED_CRED_OWM_ENDPOINT": "https://api.openweathermap.org",
  "SF_ENV_LABEL": "DEMO-PROD"
}
```

- [ ] **Step 3: Move the secret out of replacements**

Replace the `replacements` array in `sfdx-project.json`:

```json
  "replacements": [
    {
      "filename": "github-action-service/main/default/customMetadata/GitHub_App_Settings.salesforce_gforce_devhub.md-meta.xml",
      "stringToReplace": "ENV_LABEL_PLACEHOLDER",
      "replaceWithEnv": "SF_ENV_LABEL"
    }
  ]
```

> The `GITHUB_PRIVATE_KEY_BASE64` entry is removed deliberately. Per D2 a secret must not be baked into an artifact that gets uploaded and retained; it is applied after deployment by `sf-env-config-apply`. `allowUnsetEnvVariable` stays at its default `false`, so a missing `SF_ENV_LABEL` fails the build rather than shipping a placeholder.

- [ ] **Step 4: Write the secret template**

Read the existing record first — the template must keep every field it already has, or deploying it will blank them:

```bash
cd ~/gforce/sf-develop-demo
cat github-action-service/main/default/customMetadata/GitHub_App_Settings.salesforce_gforce_devhub.md-meta.xml
```

Copy it to `config/secret-templates/customMetadata/GitHub_App_Settings.salesforce_gforce_devhub.md-meta.xml.tpl`, then make exactly two changes:

1. Replace the `<value>` holding `GITHUB_PRIVATE_KEY_BASE64_PLACEHOLDER` with `${GITHUB_APP_KEY_B64}`.
2. Leave every other `<values>` block byte-identical.

The result should look like this (field names will match whatever the real file has):

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
>
    <label>salesforce gforce devhub</label>
    <protected>true</protected>
    <values>
        <field>Private_Key__c</field>
        <value xsi:type="xsd:string">${GITHUB_APP_KEY_B64}</value>
    </values>
    <!-- every other <values> block copied verbatim from the source file -->
</CustomMetadata>
```

Verify the placeholder is the only substitution point:

```bash
grep -c '\${' config/secret-templates/customMetadata/*.tpl
```

Expected: `1`. More than one means a field was templated by accident; `0` means the substitution was missed and `sf-env-config-apply` will deploy a literal placeholder.

- [ ] **Step 5: Verify the project file is still valid**

```bash
cd ~/gforce/sf-develop-demo
node -pe "JSON.parse(require('fs').readFileSync('sfdx-project.json','utf8')) && 'valid json'"
sf project convert source --manifest <(sf project generate manifest --source-dir weather-app --output-dir /tmp --name p >/dev/null && cat /tmp/p.xml) --output-dir /tmp/convert-probe 2>&1 | tail -5
```

Expected: `valid json`, and the convert probe does not error on the replacements block.

- [ ] **Step 6: Confirm no secret is left in tracked source**

```bash
grep -rn "GITHUB_PRIVATE_KEY_BASE64" --include="*.json" --include="*.xml" . \
  --exclude-dir=node_modules --exclude-dir=.git || echo "✅ no references remain"
```

- [ ] **Step 7: Commit**

```bash
git checkout -b feat/org-based-pipeline
git add config/environments config/secret-templates sfdx-project.json
git commit -m "feat(config): split env config from env secrets

Non-secret per-environment values move to config/environments/<env>.json
and are applied by the replacements block at convert time. The GitHub App
private key leaves replacements entirely: baking it in would put a secret
inside an artifact that gets uploaded and retained. It is now applied
after deployment from config/secret-templates."
```

---

## Task 12: `ci.yml` — the PR gate, and retire the fat workflow

**Files:**

- Create: `sf-develop-demo/.github/workflows/ci.yml`
- Delete: `sf-develop-demo/.github/workflows/feature-validation.yml`
- Delete: `sf-develop-demo/.github/workflows/test-aws-secrets.yml`

**Interfaces:**

- Consumes: `reusable-sf-pr-validate.yml`, `reusable-sf-code-analyze.yml` (Task 10)
- Produces: a PR gate on `main`

- [ ] **Step 1: Write ci.yml**

```yaml
---
# PR gate. Runs no deployment to a long-lived org — validation happens in a
# throwaway scratch org so a bad PR cannot touch integration or production.
#
# This replaces feature-validation.yml, which inlined the whole pipeline
# (installing the SF CLI onto ubuntu-latest, hand-rolling JWT login, and
# duplicating logic that now lives in shared actions).
name: CI

on:
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  code-analysis:
    name: Static analysis
    uses: Gforce-Innovation-Kft/shared-github-actions/.github/workflows/reusable-sf-code-analyze.yml@v2
    permissions:
      contents: read
      pull-requests: write
      actions: read
    with:
      workspace: "weather-app github-action-service"
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}

  validate:
    name: Scratch org validation
    needs: code-analysis
    uses: Gforce-Innovation-Kft/shared-github-actions/.github/workflows/reusable-sf-pr-validate.yml@v2
    permissions:
      contents: read
    with:
      checkout-submodules: true
      scratch-org-definition: config/project-scratch-def.json
    secrets:
      sfdx-auth-url: ${{ secrets.DEVHUB_SFDX_AUTH_URL }}
```

> **Resolves spec §16 open item.** The Dev Hub credential stays on the existing
> repository-level SFDX auth URL secret rather than moving to a GitHub
> Environment. PR validation must run on pull requests from forks and before any
> environment is selected, so binding it to an environment would either break
> fork PRs or require a fourth environment that gates nothing. Only the two
> deployment targets use environment-scoped credentials.
>
> If `DEVHUB_SFDX_AUTH_URL` does not exist yet, create it:
>
> ```bash
> sf org auth show-sfdx-auth-url --target-org gabor_dev --json \
>   | node -pe "JSON.parse(require('fs').readFileSync(0,'utf8')).result.sfdxAuthUrl" \
>   | gh secret set DEVHUB_SFDX_AUTH_URL
> ```

- [ ] **Step 2: Lint**

```bash
cd ~/gforce/sf-develop-demo
actionlint .github/workflows/ci.yml
```

Expected: silent. Reconcile any input-name mismatch against the real `reusable-sf-pr-validate.yml` / `reusable-sf-code-analyze.yml` signatures.

- [ ] **Step 3: Delete the superseded workflows**

```bash
git rm .github/workflows/feature-validation.yml
git rm .github/workflows/test-aws-secrets.yml
```

- [ ] **Step 4: Confirm nothing referenced them**

```bash
grep -rn "feature-validation\|test-aws-secrets" \
  --include="*.yml" --include="*.md" . \
  --exclude-dir=node_modules --exclude-dir=.git || echo "✅ no references remain"
```

Update any documentation hit — `README.md` and `CLAUDE.md` both mention `feature-validation.yml`.

- [ ] **Step 5: Push and verify on a real PR**

```bash
git add -A
git commit -m "feat(ci): thin PR gate; retire feature-validation.yml

feature-validation.yml inlined the entire pipeline — installing the SF
CLI onto ubuntu-latest, hand-rolling JWT login, duplicating logic now
owned by shared actions. Replaced by two uses: calls."
git push -u origin feat/org-based-pipeline
gh pr create --fill --draft
gh pr checks --watch
```

Expected: both jobs PASS.

---

## Task 13: `org-deploy-integration.yml`

**Files:**

- Create: `sf-develop-demo/.github/workflows/org-deploy-integration.yml`

**Interfaces:**

- Consumes: `reusable-sf-org-deploy.yml` (Task 9); `integration` environment (Task 4)
- Produces: automatic deployment to `DEMO-INTEGRATION` on push to `main`

- [ ] **Step 1: Write the caller**

```yaml
---
# Integration deployments. No approval gate — this is the fast feedback org.
#
# Thin by design: this file chooses a trigger and an environment. Everything
# it does lives in shared-github-actions (ADR 0002, L4 -> L2 -> L1).
name: Deploy — Integration

on:
  push:
    branches: [main]
    paths:
      - "weather-app/**"
      - "github-action-service/**"
      - "config/environments/**"
      - "config/secret-templates/**"
      - "sfdx-project.json"
  workflow_dispatch:
    inputs:
      mode:
        description: "Deployment mode"
        required: false
        default: delta
        type: choice
        options: [delta, full]

jobs:
  deploy:
    uses: Gforce-Innovation-Kft/shared-github-actions/.github/workflows/reusable-sf-org-deploy.yml@v2
    permissions:
      contents: write
    with:
      environment: integration
      mode: ${{ inputs.mode || 'delta' }}
      retention-days: 90
    secrets:
      sf-jwt-key-b64: ${{ secrets.SF_JWT_KEY_B64 }}
      sf-client-id: ${{ secrets.SF_CLIENT_ID }}
```

- [ ] **Step 2: Lint**

```bash
cd ~/gforce/sf-develop-demo
actionlint .github/workflows/org-deploy-integration.yml
```

- [ ] **Step 3: Bootstrap the org with a full deployment**

There is no `deployed/integration` tag yet, so the engine falls back to full mode automatically — but run it explicitly the first time so the fallback is observed rather than assumed:

```bash
git add .github/workflows/org-deploy-integration.yml
git commit -m "feat(deploy): integration caller"
git push
gh workflow run org-deploy-integration.yml --ref feat/org-based-pipeline -f mode=full
gh run watch --exit-status
```

Expected: PASS. In the summary: mode `full`, a non-zero component count, a `0Af...` deploy id.

- [ ] **Step 4: Verify the marker tag was created**

```bash
git fetch --tags --force
git rev-parse deployed/integration
git log -1 --oneline "$(git rev-parse deployed/integration)"
```

Expected: the tag exists and points at the deployed commit.

- [ ] **Step 5: Verify delta mode on a real change (Scenario B)**

```bash
printf '\n// delta probe %s\n' "$(date -u +%s)" \
  >> weather-app/main/default/classes/WeatherDashboardController.cls
git add -A && git commit -m "test: delta probe" && git push
gh run watch --exit-status
```

Expected: mode `delta`, component count `1`, and `deployed/integration` moved to the new commit.

- [ ] **Step 6: Verify the no-op path**

```bash
git commit --allow-empty -m "test: no metadata change" && git push
gh run watch --exit-status
```

Expected: the run is green, the build job reports _No deployable metadata changed_, and the deploy job is skipped.

- [ ] **Step 7: Verify a deletion actually reaches the org**

The riskiest silent failure in the whole pipeline: a deleted component that the org keeps forever while the run reports success.

```bash
cd ~/gforce/sf-develop-demo
cat > weather-app/main/default/classes/DeleteProbe.cls <<'EOF'
public with sharing class DeleteProbe {
    public static String ping() { return 'probe'; }
}
EOF
cat > weather-app/main/default/classes/DeleteProbe.cls-meta.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
EOF
git add -A && git commit -m "test: add delete probe" && git push
gh run watch --exit-status
```

Now delete it and confirm the removal propagates:

```bash
git rm weather-app/main/default/classes/DeleteProbe.cls \
       weather-app/main/default/classes/DeleteProbe.cls-meta.xml
git commit -m "test: remove delete probe" && git push
gh run watch --exit-status
```

Expected: the run summary reports a deletion, and the class is gone from the org:

```bash
gh run download --name "$(gh run list --workflow org-deploy-integration.yml \
  --status success --limit 1 --json databaseId --jq '.[0].databaseId' \
  | xargs -I{} gh api repos/:owner/:repo/actions/runs/{}/artifacts \
  --jq '.artifacts[0].name')" --dir /tmp/verify
test -f /tmp/verify/mdapi/destructiveChangesPost.xml \
  && echo "✅ deletion carried in the artifact" \
  || echo "❌ deletion missing — components will orphan in the org"
```

- [ ] **Step 8: Revert the delta probe and commit**

```bash
git revert --no-edit HEAD~2
git push
```

---

## Task 14: `org-deploy-production.yml`

**Files:**

- Create: `sf-develop-demo/.github/workflows/org-deploy-production.yml`

**Interfaces:**

- Consumes: `reusable-sf-org-deploy.yml` (Task 9); `production` environment with its approval gate (Task 3/4)
- Produces: gated deployment to `DEMO-PROD` on tag `v*`

- [ ] **Step 1: Write the caller**

```yaml
---
# Production deployments. Triggered by a version tag, gated by the production
# environment's required reviewer.
#
# The approval prompt fires on the deploy job, not the build job, so the
# artifact and its component list already exist when the reviewer decides.
# Approving a deployment whose contents are still unknown is not a review.
name: Deploy — Production

on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      mode:
        description: "Deployment mode"
        required: false
        default: delta
        type: choice
        options: [delta, full]

jobs:
  deploy:
    uses: Gforce-Innovation-Kft/shared-github-actions/.github/workflows/reusable-sf-org-deploy.yml@v2
    permissions:
      contents: write
    with:
      environment: production
      mode: ${{ inputs.mode || 'delta' }}
      retention-days: 90
    secrets:
      sf-jwt-key-b64: ${{ secrets.SF_JWT_KEY_B64 }}
      sf-client-id: ${{ secrets.SF_CLIENT_ID }}
```

- [ ] **Step 2: Lint and commit**

```bash
cd ~/gforce/sf-develop-demo
actionlint .github/workflows/org-deploy-production.yml
git add .github/workflows/org-deploy-production.yml
git commit -m "feat(deploy): gated production caller"
git push
```

- [ ] **Step 3: Merge to main, then bootstrap production (Scenario D)**

```bash
gh pr ready && gh pr merge --squash --delete-branch
git checkout main && git pull
git tag -a v0.1.0 -m "First production deployment"
git push origin v0.1.0
```

- [ ] **Step 4: Verify the gate actually blocks**

```bash
gh run list --workflow org-deploy-production.yml --limit 1
gh run view --web
```

Expected: the `build` job completes; the `deploy` job sits at _Waiting for review_. Confirm the artifact is downloadable and the component list is visible **before** approving — that is the property the gate exists for.

- [ ] **Step 5: Approve and verify**

Approve in the UI, then:

```bash
gh run watch --exit-status
git fetch --tags --force
git rev-parse deployed/production
```

Expected: PASS, and `deployed/production` points at the tagged commit.

- [ ] **Step 6: Verify the catch-up property (Scenario E)**

Push two more commits to `main` that change metadata, letting integration deploy each. Then tag `v0.2.0` and observe production's delta.

Expected: production's component count covers **both** commits, because its base is `deployed/production` rather than the previous release. This is the behaviour that makes an org that skipped a release self-heal.

---

## Task 15: `org-rollback.yml`

**Files:**

- Create: `sf-develop-demo/.github/workflows/org-rollback.yml`

**Interfaces:**

- Consumes: `sf-org-login` (Task 5), `sf-artifact-deploy` (Task 7); artifacts uploaded by Task 9
- Produces: manual rollback by run id

- [ ] **Step 1: Write the workflow**

```yaml
---
# Rollback by redeploying a previously built artifact.
#
# Deliberately NOT a git revert: reconstructing a past state from source
# re-runs the whole build and can produce different bytes. Redeploying the
# exact artifact that was known good is both faster and more honest.
#
# Bounded by artifact retention (90 days on a public repo). If the artifact
# has expired, use a full-mode deploy from the desired commit instead.
name: Rollback

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to roll back"
        required: true
        type: choice
        options: [integration, production]
      run-id:
        description: "Run id of the deployment whose artifact should be redeployed"
        required: true
        type: string

concurrency:
  group: sf-org-deploy-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  rollback:
    name: Roll back ${{ inputs.environment }}
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    container:
      image: gforceinnovation/sf-ci:1.8.0
      options: --user 1001
    permissions:
      contents: write
      actions: read
    steps:
      - name: Download the target artifact
        env:
          GH_TOKEN: ${{ github.token }}
          RUN_ID: ${{ inputs.run-id }}
          ENVIRONMENT: ${{ inputs.environment }}
        run: |
          set -euo pipefail
          NAME=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}/artifacts" \
            --jq ".artifacts[] | select(.name | startswith(\"org-based-${ENVIRONMENT}-\")) | .name" \
            | head -1)
          if [ -z "$NAME" ]; then
            echo "::error::Run ${RUN_ID} has no artifact for ${ENVIRONMENT}. It may have expired — artifacts are retained 90 days. Use a full-mode deploy instead." >&2
            exit 1
          fi
          gh run download "$RUN_ID" --repo "$GITHUB_REPOSITORY" --name "$NAME" --dir artifact
          echo "ARTIFACT_NAME=$NAME" >> "$GITHUB_ENV"

      # The stored manifest is the source of truth for what these bytes are.
      - name: Read the expected checksum from the artifact
        run: |
          set -euo pipefail
          SHA=$(node -pe "JSON.parse(require('fs').readFileSync('artifact/deployment.json','utf8')).artifactSha256")
          COMMIT=$(node -pe "JSON.parse(require('fs').readFileSync('artifact/deployment.json','utf8')).commit")
          [ -n "$SHA" ] || { echo "::error::deployment.json has no artifactSha256"; exit 1; }
          echo "EXPECTED_SHA=$SHA" >> "$GITHUB_ENV"
          echo "ROLLBACK_COMMIT=$COMMIT" >> "$GITHUB_ENV"
          echo "::notice::Rolling ${{ inputs.environment }} back to $COMMIT"

      - name: Authenticate
        uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-org-login@v2
        with:
          credential-source: github-env
          auth-method: jwt
          jwt-key-b64: ${{ secrets.SF_JWT_KEY_B64 }}
          client-id: ${{ secrets.SF_CLIENT_ID }}
          username: ${{ vars.SF_USERNAME }}
          instance-url: ${{ vars.SF_INSTANCE_URL }}
          org-alias: target

      - name: Redeploy the artifact
        uses: Gforce-Innovation-Kft/shared-github-actions/.github/actions/sf-artifact-deploy@v2
        with:
          artifact-path: artifact
          expected-sha256: ${{ env.EXPECTED_SHA }}
          org-alias: target
          test-level: RunLocalTests

      # The marker must follow the org, or the next delta is computed from a
      # state the org is no longer in and silently omits components.
      - name: Move the deployment marker back
        env:
          GH_TOKEN: ${{ github.token }}
          ENVIRONMENT: ${{ inputs.environment }}
        run: |
          set -euo pipefail
          git config --global --add safe.directory '*'
          git clone --bare --depth 1 \
            "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" marker.git
          cd marker.git
          git fetch origin "$ROLLBACK_COMMIT"
          git tag -f "deployed/$ENVIRONMENT" "$ROLLBACK_COMMIT"
          git push --force origin "refs/tags/deployed/$ENVIRONMENT"
          echo "✅ deployed/$ENVIRONMENT moved back to $ROLLBACK_COMMIT"
```

- [ ] **Step 2: Lint**

```bash
cd ~/gforce/sf-develop-demo
actionlint .github/workflows/org-rollback.yml
```

- [ ] **Step 3: Run a rollback drill against integration (Scenario F)**

```bash
git add .github/workflows/org-rollback.yml
git commit -m "feat(rollback): redeploy a prior artifact by run id"
git push
PREV=$(gh run list --workflow org-deploy-integration.yml \
  --status success --limit 5 --json databaseId --jq '.[1].databaseId')
echo "rolling back to run $PREV"
gh workflow run org-rollback.yml -f environment=integration -f run-id="$PREV"
gh run watch --exit-status
```

Expected: PASS, and `deployed/integration` moves back to the older commit.

- [ ] **Step 4: Verify the expired-artifact error path**

```bash
gh workflow run org-rollback.yml -f environment=integration -f run-id=1
gh run watch || true
```

Expected: FAIL with the explicit _may have expired_ message, not an opaque `gh run download` error.

- [ ] **Step 5: Restore integration to the current commit**

```bash
gh workflow run org-deploy-integration.yml -f mode=full
gh run watch --exit-status
```

---

## Task 16: Documentation

**Files:**

- Create: `sf-develop-demo/docs/devops/README.md`
- Create: `sf-develop-demo/docs/devops/runbook-org-setup.md`
- Modify: `sf-develop-demo/CLAUDE.md`
- Modify: `sf-develop-demo/README.md`
- Modify: `shared-github-actions/docs/pipeline-map.md`
- Modify: `shared-github-actions/README.md`

**Interfaces:**

- Consumes: everything
- Produces: a repository a reviewer can understand without undocumented manual steps (spec §1)

- [ ] **Step 1: Write the org-setup runbook**

Create `docs/devops/runbook-org-setup.md` by lifting §5 of the design spec verbatim — org signup, the `openssl` keypair commands, Connected App configuration, the propagation wait, the pre-authorization step, the `INSTANCE_URL` gotcha, and the exit criteria. This is the file someone reproducing the demo follows.

- [ ] **Step 2: Write the architecture overview**

Create `docs/devops/README.md` covering: the three-repo split and why; the build/deploy job boundary and why the deploy job has no checkout; the `deployed/<env>` marker and the catch-up property; what is in an artifact and what is deliberately not (D2); the rollback window and its 90-day limit; and a mermaid diagram of the two-job engine.

- [ ] **Step 3: Update CLAUDE.md**

Replace the CI/CD section, which still describes `feature-validation.yml`:

```markdown
## CI/CD

Four workflows, all thin callers into `shared-github-actions` (ADR 0002 — L4 orchestrates, L1/L2 implement). No `sf` CLI invocation lives in this repo.

| Workflow                     | Trigger       | Target                               |
| ---------------------------- | ------------- | ------------------------------------ |
| `ci.yml`                     | PR → `main`   | scratch org via Dev Hub              |
| `org-deploy-integration.yml` | push → `main` | `DEMO-INTEGRATION`, no gate          |
| `org-deploy-production.yml`  | tag `v*`      | `DEMO-PROD`, required reviewer       |
| `org-rollback.yml`           | manual        | redeploys a prior artifact by run id |

Deployments are artifact-based: the build job converts source to metadata
format with string replacements applied and freezes it; the deploy job has no
`actions/checkout` and deploys exactly those bytes via `--metadata-dir`.

The delta base per org is the `deployed/<env>` git tag, force-moved only on
success — so a failed deployment leaves the base unchanged and an org that
skipped a release catches up on its next deploy.

Secrets never enter an artifact. Non-secret per-environment values are baked
in at convert time from `config/environments/<env>.json`; real secrets are
applied after deployment from `config/secret-templates/`.

Design: `docs/superpowers/specs/2026-08-13-salesforce-org-based-devops-design.md`
Runbook: `docs/devops/runbook-org-setup.md`
```

- [ ] **Step 4: Update the pipeline map**

In `shared-github-actions/docs/pipeline-map.md`, add `reusable-sf-org-deploy.yml` to the L2 layer and the three artifact actions to L1, using the existing `:::new` class. Add a section for the org-based deployment chain mirroring the existing diagram style.

- [ ] **Step 5: Update the shared-github-actions README**

Add the three new actions and the new reusable workflow to the appropriate sections, matching the existing entry format (key inputs, key outputs, required permissions).

- [ ] **Step 6: Verify every documented command actually runs**

```bash
cd ~/gforce/sf-develop-demo
grep -oE '^\s*(sf|gh|git|docker|terraform|openssl) [^|]*' docs/devops/*.md | head -40
```

Walk the list and confirm each is a command you have actually run during Tasks 1–15. Fix anything aspirational — spec §1 requires no undocumented or untested manual steps.

- [ ] **Step 7: Commit**

```bash
cd ~/gforce/sf-develop-demo
git add docs/devops CLAUDE.md README.md
git commit -m "docs: org-based DevOps architecture and setup runbook"
git push

cd ~/gforce/shared-github-actions
git add docs/pipeline-map.md README.md
git commit -m "docs: add the org-based deployment chain to the pipeline map"
git push
```

- [ ] **Step 8: Final acceptance — walk every scenario**

Confirm each spec §14 scenario has been observed, not assumed:

- [ ] A — PR validation green, no long-lived org touched (Task 12 Step 5)
- [ ] B — delta deployment, one component (Task 13 Step 5)
- [ ] C — full deployment (Task 13 Step 3)
- [ ] D — production gate blocks until approved (Task 14 Step 4)
- [ ] E — catch-up delta spans two releases (Task 14 Step 6)
- [ ] F — rollback restores a prior artifact (Task 15 Step 3)
- [ ] G, H — deferred to Phase 8; note this in `docs/devops/README.md`

---

## Deferred to Phase 8

Not in this plan. Spec §13 holds the full design: Workload Identity Federation with the composite `repo_env` attribute binding, Secret Manager sized to the 6-active-version free tier, and a GCS artifact store where `roles/storage.objectCreator` makes overwriting an artifact impossible at the permission layer. Adding it touches `sf-org-login` (a `gcp` credential source), adds `gcp-secret-get` and `gcs-artifact-upload`, and bumps `deployment.json` to `schemaVersion` `1.1` with `artifactGcsUri`.
