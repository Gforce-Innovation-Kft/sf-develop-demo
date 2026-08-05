# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Salesforce DX project demonstrating enterprise architecture patterns (fflib) with two functional packages: a GitHub Actions integration service that dispatches repository events from Salesforce, and a weather dashboard app that fetches/stores weather data via OpenWeatherMap API.

## Commands

```bash
# Deploy all source to a scratch org
sf project deploy start --target-org <alias>

# Create a scratch org
sf org create scratch -f config/project-scratch-def.json -a <alias> --set-default

# Run all Apex tests
sf apex run test --target-org <alias> --wait 10 --code-coverage

# Run LWC unit tests
npm test                    # runs sfdx-lwc-jest
npm run test:unit:coverage  # with coverage

# Lint and format
npm run lint                # ESLint for LWC/Aura JS
npm run prettier            # format all files (Apex, XML, LWC HTML, JS, JSON)
npm run prettier:verify     # check formatting without writing
```

## Package Directory Structure

| Package | Default | Contents |
|---------|---------|----------|
| `fflib-apex-mocks/sfdx-source/apex-mocks/` | no | fflib_ApexMocks test framework (**git submodule**, not our code — never edit) |
| `fflib-apex-common/sfdx-source/apex-common/` | no | fflib core framework: Application factory, SObjectDomain, SObjectSelector, SObjectUnitOfWork, QueryFactory (**git submodule**, not our code — never edit) |
| `github-action-service/` | **yes** | GitHub integration: `GitHubDispatchService`, `GitHubAppAuthService`, event classes (`DataSyncEvent`, `DeploymentEvent`, `TestResultEvent`), `gitHubActionTrigger` LWC, Named Credentials, `GitHub_App_Settings__mdt` custom metadata |
| `weather-app/` | no | Weather demo: `Application.cls` factory, `IWeatherService`/`WeatherServiceImpl`, `WeatherReportsSelector`, `WeatherReports` domain, `WeatherDashboardController`, `weatherDashboard` LWC, `Weather_Report__c` custom object |

## fflib dependency — where to read the source

fflib is **not** vendored into this repo. It is pinned as two git submodules tracking
`apex-enterprise-patterns` upstream. After cloning, the directories are empty until you run:

```bash
git submodule update --init --recursive
```

**When you need fflib context** (base-class signatures, why `Application.cls` wires the way it
does, what `fflib_QueryFactory` supports), read it on disk — do not guess from memory and do not
fetch it from the web:

| Need | Read |
|------|------|
| `fflib_Application` (factory base: UnitOfWork/Service/Selector/Domain) | `fflib-apex-common/sfdx-source/apex-common/main/classes/fflib_Application.cls` |
| `fflib_SObjectSelector`, `fflib_QueryFactory` | same dir, `fflib_SObjectSelector.cls` / `fflib_QueryFactory.cls` |
| `fflib_SObjectDomain`, `fflib_SObjectUnitOfWork` | same dir |
| Mocking API (`fflib_ApexMocks`, `fflib_IDGenerator`, matchers) | `fflib-apex-mocks/sfdx-source/apex-mocks/main/classes/` |
| Worked examples of the patterns | `fflib-apex-common/sfdx-source/apex-common/test/classes/` |

**Rules:**
- Treat both submodules as **read-only third-party source**. Fixes go upstream, not here.
- To move fflib forward: `git -C fflib-apex-common pull origin master`, then commit the new
  submodule pointer in this repo. Re-run scratch-org validation after any bump.
- CI checks out with `submodules: recursive`; without it the Apex build fails to compile.

## fflib Enterprise Architecture Pattern

All business logic in `weather-app` follows the fflib Apex Enterprise Patterns. The central wiring point is `weather-app/main/default/classes/Application.cls`.

**Application Factory** (`Application.cls`) registers four factories:
- `Application.UnitOfWork` -- wraps DML; call `Application.UnitOfWork.newInstance()`, then `registerNew/registerDirty/registerDeleted`, then `commitWork()`
- `Application.Service` -- maps `IWeatherService.class => WeatherServiceImpl.class`; obtain via `(IWeatherService) Application.Service.newInstance(IWeatherService.class)`
- `Application.Selector` -- maps `Weather_Report__c.SObjectType => WeatherReportsSelector.class`
- `Application.Domain` -- maps `Weather_Report__c.SObjectType => WeatherReports.Constructor.class`

**Layer responsibilities:**
- **Service** (`IWeatherService` / `WeatherServiceImpl`): orchestrates business operations, calls selectors for queries and UoW for DML
- **Selector** (`WeatherReportsSelector extends fflib_SObjectSelector`): all SOQL via `fflib_QueryFactory`; provides `newInstance()` static factory method
- **Domain** (`WeatherReports extends fflib_SObjectDomain`): trigger logic, field validation, in-memory filtering; uses inner `Constructor` class implementing `fflib_SObjectDomain.IConstructable`
- **Controller** (`WeatherDashboardController`): thin `@AuraEnabled` methods that delegate to Service/Selector; no direct SOQL or DML

When adding a new SObject, register it in all four factory maps in `Application.cls`.

## Testing

**Apex tests** use `fflib_ApexMocks` for mocking:
- Mock services: `Application.Service.setMock(IWeatherService.class, mockService)`
- Mock UoW: `Application.UnitOfWork.setMock(mockUow)` to avoid real DML
- Mock selectors: `Application.Selector.setMock(mockSelector)`

**LWC tests** use `@salesforce/sfdx-lwc-jest`:
- Place test files adjacent to components as `<component>.test.js`
- `lint-staged` automatically runs related LWC tests on commit

## Code Quality & Pre-commit

**Prettier** (`.prettierrc`): uses `prettier-plugin-apex` for `.cls`/`.trigger` and `@prettier/plugin-xml` for XML metadata. LWC HTML uses the `lwc` parser. `trailingComma: "none"`.

**Husky + lint-staged**: pre-commit hook runs Prettier on all supported files, ESLint on LWC/Aura JS, and `sfdx-lwc-jest --findRelatedTests` on changed LWC files.

## Salesforce Configuration

- **API Version**: 65.0 (`sourceApiVersion` in `sfdx-project.json`)
- **Scratch Org Edition**: Developer (`config/project-scratch-def.json`)

## 2GP Packaging

Three **unlocked packages** are built from Dev Hub `gabor_dev`, chained by declared
dependencies in `sfdx-project.json`:

| Package | Package Id (`0Ho`) | 0.1.0-1 (`04t`) | Depends on |
|---------|--------------------|-----------------|------------|
| `fflib-apex-mocks`  | `0HogL000000421dSAA` | `04tgL000000M0arQAC` | — |
| `fflib-apex-common` | `0HogL000000423FSAQ` | `04tgL000000M0cTQAS` | mocks |
| `weather-app`       | `0HogL000000426TSAQ` | `04tgL000000M26PQAS` | mocks + common |

```bash
# build a new version (validated — draws on the 6/day Dev Hub limit)
sf package version create --package weather-app --installation-key-bypass \
  --wait 45 --target-dev-hub gabor_dev

# install — dependencies first, in this order
sf package install --package 04tgL000000M0arQAC --target-org <alias> --wait 20 --no-prompt
sf package install --package 04tgL000000M0cTQAS --target-org <alias> --wait 20 --no-prompt
sf package install --package weather-app@0.1.0-1 --target-org <alias> --wait 20 --no-prompt
```

**2GP dependencies are not transitive.** Salesforce installs exactly what a package declares —
it does not walk the graph. `weather-app` therefore lists *both* fflib packages in install
order; declaring only `fflib-apex-common` fails the build with "Install package
'fflib-apex-mocks' ... before you install 'fflib-apex-common'".

fflib is packaged from our own Dev Hub because upstream `apex-enterprise-patterns` publishes no
`04t` version IDs (no releases, no `packageAliases`) — there is nothing official to depend on.

**`sf package create` rewrites `sfdx-project.json` and silently drops the `dependencies` block**
of the entry it touches. Re-add it after creating or recreating any package.

Org-dependent unlocked packages are **not** usable here: Salesforce rejects them with
"Org-dependent unlocked packages can't have dependencies on other packages."

To discover a version's flattened dependency chain (install order) without parsing the project
file:

```bash
sf data query --use-tooling-api --target-org gabor_dev \
  --query "SELECT Dependencies FROM SubscriberPackageVersion WHERE Id = '04tgL000000M26PQAS'"
```

## Naming Conventions

- Custom objects: `Snake_Case__c` (e.g., `Weather_Report__c`)
- Custom fields: `Snake_Case__c` (e.g., `City__c`, `Report_Date_Time__c`)
- Apex classes: PascalCase; selectors end in `Selector`, domains are plural noun, services end in `Service`/`ServiceImpl`, interfaces prefixed with `I`
- LWC components: camelCase directory and file names (e.g., `weatherDashboard`)
- Custom metadata: `Snake_Case__mdt` (e.g., `GitHub_App_Settings__mdt`)

## CI/CD

GitHub Actions workflow `feature-validation.yml` runs on PRs to `main`:
1. **Code quality job**: ESLint + Prettier checks
2. **Validate feature job**: creates scratch org, deploys all source, assigns `Weather_Dashboard_Demo_Access` permset, runs Apex tests, validates metadata, then deletes the scratch org

<!-- skills-tooling -->
## Skills & AI tooling

**External skills** (lockfile-managed — update with `npx skills check` / `npx skills update`):
- `dx-org-manage` — from forcedotcom/sf-skills (scratch org + snapshot lifecycle)
- `dx-org-permission-set-assign` — from forcedotcom/sf-skills
- `dx-pkg-post-install-configure` — from forcedotcom/sf-skills (post-install org setup)
- `experience-lwc-generate` — from forcedotcom/sf-skills
- `github-actions-templates` — from wshobson/agents (workflow authoring)
- `platform-apex-logs-debug` — from forcedotcom/sf-skills
- `platform-apex-test-run` — from forcedotcom/sf-skills
- `platform-docs-get` — from forcedotcom/sf-skills (authoritative SF CLI / platform docs)
- `platform-metadata-deploy` — from forcedotcom/sf-skills

**Global tooling available in every session:** lean-ctx (prefer `ctx_*` MCP tools for reads/search/shell — token-compressed), superpowers process skills, and graphify (no graph built for this repo).
<!-- /skills-tooling -->
