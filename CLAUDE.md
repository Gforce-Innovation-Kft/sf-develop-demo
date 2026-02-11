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
| `apex-mocks/` | no | fflib_ApexMocks test framework (vendored) |
| `apex-common/` | no | fflib core framework: Application factory, SObjectDomain, SObjectSelector, SObjectUnitOfWork, QueryFactory (vendored) |
| `github-action-service/` | **yes** | GitHub integration: `GitHubDispatchService`, `GitHubAppAuthService`, event classes (`DataSyncEvent`, `DeploymentEvent`, `TestResultEvent`), `gitHubActionTrigger` LWC, Named Credentials, `GitHub_App_Settings__mdt` custom metadata |
| `weather-app/` | no | Weather demo: `Application.cls` factory, `IWeatherService`/`WeatherServiceImpl`, `WeatherReportsSelector`, `WeatherReports` domain, `WeatherDashboardController`, `weatherDashboard` LWC, `Weather_Report__c` custom object |

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

## Naming Conventions

- Custom objects: `Snake_Case__c` (e.g., `Weather_Report__c`)
- Custom fields: `Snake_Case__c` (e.g., `City__c`, `Report_Date_Time__c`)
- Apex classes: PascalCase; selectors end in `Selector`, domains are plural noun, services end in `Service`/`ServiceImpl`, interfaces prefixed with `I`
- LWC components: camelCase directory and file names (e.g., `weatherDashboard`)
- Custom metadata: `Snake_Case__mdt` (e.g., `GitHub_App_Settings__mdt`)

## CI/CD

GitHub Actions workflow `feature-validation.yml` runs on PRs to `main`/`develop`:
1. **Code quality job**: ESLint + Prettier checks
2. **Validate feature job**: creates scratch org, deploys all source, assigns `Weather_Dashboard_Demo_Access` permset, runs Apex tests, validates metadata, then deletes the scratch org
