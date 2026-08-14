# fflib architecture in this repo

Detail behind `CLAUDE.md`. The general GForce fflib standard lives in the
`salesforce-developer` skill; this file covers only what is specific to this repo.

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
