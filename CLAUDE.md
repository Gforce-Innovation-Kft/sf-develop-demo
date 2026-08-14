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

## fflib Enterprise Architecture

Four package directories: `apex-mocks/`, `apex-common/`, `github-action-service/` (default),
`weather-app/`. Layers: Application factory → Service (interface + impl) → Selector → Domain →
Unit of Work.

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
- `gforce-github-actions` — from Gforce-Innovation-Kft/gforce-ai (L2, GForce GHA house standards)
- `github-actions-templates` — from wshobson/agents (workflow authoring)
- `platform-apex-logs-debug` — from forcedotcom/sf-skills
- `platform-apex-test-run` — from forcedotcom/sf-skills
- `platform-docs-get` — from forcedotcom/sf-skills (authoritative SF CLI / platform docs)
- `platform-metadata-deploy` — from forcedotcom/sf-skills
- `salesforce-developer` — from Gforce-Innovation-Kft/gforce-ai (L2, house Apex/LWC standards;
  overridden by [`.claude/references/local-standards.md`](.claude/references/local-standards.md))

**Global tooling available in every session:** lean-ctx (prefer `ctx_*` MCP tools for reads/search/shell — token-compressed), superpowers process skills, and graphify (no graph built for this repo).

<!-- /skills-tooling -->
