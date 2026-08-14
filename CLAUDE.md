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

| Package                                      | Default | Contents                                                                                                                                                                                                                             |
| -------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `fflib-apex-mocks/sfdx-source/apex-mocks/`   | no      | fflib_ApexMocks test framework (**git submodule**, not our code — never edit)                                                                                                                                                        |
| `fflib-apex-common/sfdx-source/apex-common/` | no      | fflib core framework: Application factory, SObjectDomain, SObjectSelector, SObjectUnitOfWork, QueryFactory (**git submodule**, not our code — never edit)                                                                            |
| `github-action-service/`                     | **yes** | GitHub integration: `GitHubDispatchService`, `GitHubAppAuthService`, event classes (`DataSyncEvent`, `DeploymentEvent`, `TestResultEvent`), `gitHubActionTrigger` LWC, Named Credentials, `GitHub_App_Settings__mdt` custom metadata |
| `weather-app/`                               | no      | Weather demo: `Application.cls` factory, `IWeatherService`/`WeatherServiceImpl`, `WeatherReportsSelector`, `WeatherReports` domain, `WeatherDashboardController`, `weatherDashboard` LWC, `Weather_Report__c` custom object          |

## fflib dependency — where to read the source

fflib is **not** vendored into this repo. It is pinned as two git submodules tracking
`apex-enterprise-patterns` upstream. After cloning, the directories are empty until you run:

```bash
git submodule update --init --recursive
```

**When you need fflib context** (base-class signatures, why `Application.cls` wires the way it
does, what `fflib_QueryFactory` supports), read it on disk — do not guess from memory and do not
fetch it from the web:

| Need                                                                   | Read                                                                           |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `fflib_Application` (factory base: UnitOfWork/Service/Selector/Domain) | `fflib-apex-common/sfdx-source/apex-common/main/classes/fflib_Application.cls` |
| `fflib_SObjectSelector`, `fflib_QueryFactory`                          | same dir, `fflib_SObjectSelector.cls` / `fflib_QueryFactory.cls`               |
| `fflib_SObjectDomain`, `fflib_SObjectUnitOfWork`                       | same dir                                                                       |
| Mocking API (`fflib_ApexMocks`, `fflib_IDGenerator`, matchers)         | `fflib-apex-mocks/sfdx-source/apex-mocks/main/classes/`                        |
| Worked examples of the patterns                                        | `fflib-apex-common/sfdx-source/apex-common/test/classes/`                      |

**Rules:**

- Treat both submodules as **read-only third-party source**. Fixes go upstream, not here.
- To move fflib forward: `git -C fflib-apex-common pull origin master`, then commit the new
  submodule pointer in this repo. Re-run scratch-org validation after any bump.
- CI checks out with `submodules: recursive`; without it the Apex build fails to compile.

## fflib Enterprise Architecture

Four package directories: `fflib-apex-mocks/`, `fflib-apex-common/` (both submodules),
`github-action-service/` (default), `weather-app/`. Layers: Application factory → Service
(interface + impl) → Selector → Domain → Unit of Work.

**Detail: [`.claude/references/fflib-architecture.md`](.claude/references/fflib-architecture.md).**
General standard: the `salesforce-developer` skill.

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

Version builds draw on a **6/day Dev Hub limit**; dependencies install in a fixed order.

**Both are easy to get wrong: [`.claude/references/2gp-packaging.md`](.claude/references/2gp-packaging.md).**

## Naming Conventions

- Custom objects: `Snake_Case__c` (e.g., `Weather_Report__c`)
- Custom fields: `Snake_Case__c` (e.g., `City__c`, `Report_Date_Time__c`)
- Apex classes: PascalCase; selectors end in `Selector`, domains are plural noun, services end in `Service`/`ServiceImpl`, interfaces prefixed with `I`
- LWC components: camelCase directory and file names (e.g., `weatherDashboard`)
- Custom metadata: `Snake_Case__mdt` (e.g., `GitHub_App_Settings__mdt`)

## CI/CD

`ci.yml` is the PR gate on `main`. It is two `uses:` and nothing else:

1. **Static analysis** — `reusable-sf-code-analyze.yml@v2` over `weather-app` and `github-action-service`
2. **Scratch org validation** — `reusable-sf-pr-validate.yml@v2`, in `gforceinnovation/sf-ci:3.0.0` as UID 1001

Ordered by cost: analysis needs no org, so a tree that fails it spends none of
the Dev Hub's 3 concurrent scratch orgs.

**No pipeline logic belongs in this repo.** `ci.yml` replaced
`feature-validation.yml`, which inlined the whole thing — installing the SF CLI
onto `ubuntu-latest`, hand-rolling a JWT login, duplicating what shared actions
own. It was retired carrying three independent defects that a thin caller cannot
have: a pinned Node 18 that could not parse the current SF CLI, a My Domain URL
passed as the JWT audience, and no `permissions` block, so the step reporting
failures could not report them.

<!-- skills-tooling -->

## Skills & AI tooling

**External skills** (lockfile-managed — update with `npx skills check` / `npx skills update`):

- `dx-org-manage` — from forcedotcom/sf-skills (scratch org + snapshot lifecycle)
- `dx-org-permission-set-assign` — from forcedotcom/sf-skills
- `dx-pkg-post-install-configure` — from forcedotcom/sf-skills (post-install org setup)
- `experience-lwc-generate` — from forcedotcom/sf-skills
- `gforce-github-actions` — from Gforce-Innovation-Kft/gforce-ai (L2, GForce GHA house standards)
- `github-actions-templates` — from wshobson/agents (workflow authoring)
- `platform-apex-logs-debug` — from forcedotcom/sf-skills
- `platform-apex-test-run` — from forcedotcom/sf-skills
- `platform-docs-get` — from forcedotcom/sf-skills (authoritative SF CLI / platform docs)
- `platform-metadata-deploy` — from forcedotcom/sf-skills
- `salesforce-developer` — from Gforce-Innovation-Kft/gforce-ai (L2, house Apex/LWC standards;
  overridden by [`.claude/references/local-standards.md`](.claude/references/local-standards.md))

**Global tooling available in every session:** rtk (Bash output compression — automatic via hook), lean-ctx (prefer `ctx_*` MCP tools for reads/search — token-compressed), and superpowers process skills.

<!-- /skills-tooling -->
