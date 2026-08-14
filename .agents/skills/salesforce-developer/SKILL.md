---
name: salesforce-developer
description: >
  GForce Salesforce house standards — fflib architecture, NebulaLogger, bulkification,
  governor limits, boundary testing, and the 90% coverage gate.
  TRIGGER when: writing, reviewing, or refactoring Apex classes, triggers, LWC components,
  batch/queueable jobs, test classes, SOQL, selectors, services, or domains; or deciding
  where Salesforce logic belongs.
  DO NOT TRIGGER when: writing Ansible, GitHub Actions, Terraform, or TypeScript/Node
  tooling that merely mentions Salesforce; or when the task is CI/CD plumbing, not org
  metadata.
version: 1.2.0
tags: [salesforce, apex, lwc, fflib, development, technical]
---

# GForce Salesforce Developer Skill

Load this skill for any Salesforce technical task: Apex classes, LWC components, triggers, batch jobs, test classes, SOQL, selectors, services, domains.

**This is the canonical GForce Salesforce standard.** It lives in `Gforce-Innovation-Kft/gforce-ai`
and is installed per repo via `npx skills add Gforce-Innovation-Kft/gforce-ai@salesforce-developer`,
tracked in that repo's `skills-lock.json`. Repo-specific rules go in
`.claude/references/local-standards.md` and win over this file.

---

## Step 0 — Read the right reference file first

Do NOT skip. The reference files contain authoritative patterns with code examples.

Paths below are **relative to this skill directory**, so they resolve wherever the skill is
loaded from. `references/` ships as real files inside this skill.

| What you're building | Read first |
|---|---|
| Any Apex class | `references/apex-coding-rules.md` |
| fflib layer (domain / selector / service / UoW / application factory) | `references/apex-patterns.md` |
| Any test class | `references/testing-testdatafactory.md` |
| Any LWC component | `references/lwc-coding-rules.md` |
| SOQL queries or selector methods | `references/soql-optimization.md` |
| Sharing model, FLS, CRUD, Named Credentials | `references/security-sharing.md` |
| Branching, CI/CD pipeline, deploy strategy | `references/deployment-devops.md` |
| Any Logger.* usage | invoke skill `using-nebula-logger` |
| **Always, last** | `.claude/references/local-standards.md` **in the current repo, if it exists** |

**L3 override.** If the current repo has `.claude/references/local-standards.md`, read it **last**
and treat it as authoritative: it is repo-specific and **wins** on any conflict with the rules in
this skill. Say explicitly which rule you followed and why. Never copy this skill into a repo to
customize it — that breaks `npx skills update` and drifts silently.

And read the matching template in `assets/` before authoring:

| Building | Template |
|---|---|
| Selector | `assets/AccountsSelector.cls` |
| Service | `assets/IAccountsService.cls` + `assets/AccountsServiceImpl.cls` |
| Domain | `assets/Accounts.cls` |
| Test | `assets/AccountsServiceTest.cls` |
| Application.cls registration | `assets/README.md` |

---

## Step 1 — Establish volume context before writing code

Ask or confirm before generating any Apex:

- **Record volumes**: How many records of the primary SObject? (e.g. "~50K Accounts")
- **Trigger batch size**: Always design for 200 (trigger default); Batch `execute()` can receive up to 2000
- **Growth trajectory**: Will this need to handle 10× volume in 12–24 months?

If the user has not stated volumes, **assume high-volume production scale (>10K records)** and generate accordingly. State this assumption explicitly so the user can correct it.

---

## Step 2 — Architecture layer check

Before writing a line, confirm:

- [ ] Which layer is this? → Trigger / TriggerHandler / Domain / Selector / Service / Batch / Queueable / Gateway / LWC
- [ ] SOQL lives only in Selectors — never in Domain, Service, or triggers
- [ ] DML lives only in Unit of Work (`uow.commitWork()`) — never direct `insert`/`update`/`delete`
- [ ] `with sharing` is the default — `without sharing` requires an explicit comment explaining why
- [ ] Does `Application.cls` need updating? (register new SObjects in Service, Selector, Domain, UoW maps)
- [ ] Every new Selector's constructor passes `DataAccess.USER_MODE` — **fflib does not enforce
      FLS by default**, so a selector without it silently runs with FLS unenforced (CRUD is
      still checked, and `with sharing` still applies)

## Step 2a — Templates and API version

- **Read the matching file in `assets/` before authoring.** They are real, compiling examples of
  the layer you are about to write; adapt them rather than inventing a shape.
- **Take the API version from the repo**, not from memory: `sfdx-project.json` →
  `sourceApiVersion`. Consuming repos differ — check the value in the repo you're actually in
  rather than assuming one; `platform-apex-generate` defaults to 66.0 unless you override it.
  State the version you are using when you invoke that skill.

---

## Step 3 — Governor limit mental pass

Before finalising any method, check each:

| Check | If yes |
|---|---|
| SOQL inside a loop? | Stop. Move query to Selector, call before loop, build a Map |
| DML inside a loop? | Stop. Use `uow.registerDirty/registerNew`, call `commitWork()` after loop |
| Unconstrained query without LIMIT? | Add LIMIT or use Batch for >10K rows |
| Nested loop over large collections? | Refactor to `Map<Id, SObject>` for O(1) lookup |
| Multiple queries that could be combined? | Consolidate into one Selector method |

---

## Step 4 — Boundary condition checklist

Every generated method must handle:

- [ ] Null or empty input → `if (records == null || records.isEmpty()) return;` at entry
- [ ] Max trigger batch (200 records) — test explicitly with 200 records
- [ ] Missing related records — `Map.get()` can return null; always null-check before use
- [ ] Duplicate IDs in the input set — use `Set<Id>` not `List<Id>`
- [ ] DML partial failure — log each `Database.SaveResult` error when using `allOrNone = false`
- [ ] Callout timeout — always set `req.setTimeout()`, always catch `System.CalloutException`
- [ ] Recursive trigger guard — ensure domain/handler has a re-entry guard if needed

---

## Step 5 — Test class requirements

- `@isTest` + `@TestSetup` on every test class
- Use `{Object}TestFactory` — never construct SObjects inline in test methods
- **One positive test + one bulk test (200 records minimum)** per public method
- One negative / error-path test per method
- Coverage target: **90%** — this is the CI gate
- No `SeeAllData = true`
- No `System.debug` — not even in tests (use `Logger.*` or omit)
- Unit tests: mock with `fflib_ApexMocks` (`Application.Selector.setMock()`, `Application.UnitOfWork.setMock()`)
- Integration tests: use real DML only when testing the full stack end-to-end

---

## Hard stops — never generate code containing these

- SOQL inside any loop (`for`, `while`, `do-while`) — zero tolerance
- DML inside any loop — zero tolerance
- A Selector constructed without `DataAccess.USER_MODE` (or an equivalent explicit opt-in)
- `WITH SECURITY_ENFORCED` in new code — use `WITH USER_MODE`; it enforces CRUD and sharing too
- `System.debug` anywhere — use `Logger.*` (NebulaLogger)
- Logic inside a trigger file — one line to handler only
- Hardcoded IDs, profile names, org URLs, or credentials
- `SeeAllData = true` in any test
- `SELECT *` — enumerate fields explicitly
- `without sharing` without a comment explaining the exception
- Catch `Exception e` without logging and re-throwing (never swallow silently)

---

## Related skills

| Task | Skill |
|---|---|
| Generate Apex class | `platform-apex-generate` |
| Generate test class | `platform-apex-test-generate` |
| Generate LWC | `experience-lwc-generate` |
| Run Apex tests | `platform-apex-test-run` |
| SOQL query help | `platform-soql-query` |
| NebulaLogger details | `using-nebula-logger` |
| Debug Apex logs | `platform-apex-logs-debug` |
| Deploy metadata | `platform-metadata-deploy` |
