# AI Guidance

Use this guide when prompting Copilot so it stays consistent with the patterns in this repo.

## Recommended workflow
1) Open the relevant package folder in VS Code and keep related Apex/LWC files in view.
2) Open `docs/architecture.md` and the template that matches your task.
3) Open one or two local reference files (see below) so Copilot mirrors real code.
4) Ask Copilot for small, focused changes (one class or one feature at a time).

## Context boosters (open these when relevant)
- `weather-app/main/default/classes/Application.cls` (factory wiring)
- `weather-app/main/default/classes/WeatherReportsSelector.cls` (selector pattern)
- `weather-app/main/default/classes/WeatherReports.cls` (domain pattern)
- `weather-app/main/default/classes/WeatherServiceImpl.cls` (service pattern)
- `weather-app/main/default/classes/WeatherDashboardController.cls` (controller pattern)
- `weather-app/main/default/lwc/weatherDashboard/` (LWC pattern)
- `apex-mocks/test/classes/fflib_ApexMocksTest.cls` (ApexMocks usage)

## Good prompt shape
- State the target package: `github-action-service` or `weather-app`
- State the pattern: service, selector, domain, controller, LWC
- State the data and behavior: objects, fields, validations, and API needs
- State test expectations: success and failure paths

Example
"Create a selector for Account in weather-app using fflib_SObjectSelector, include fields Id, Name, Type, and a selectByName method. Add a test using fflib_ApexMocks for the service that uses the selector."

## Prompt checklist
- Name the exact file or folder to edit
- State the pattern to use (service/selector/domain/controller/LWC)
- List required fields and behavior
- Ask for a test and tell which template to start from

## What Copilot should follow here
- Bulk safe Apex and no SOQL/DML inside loops
- LWC uses `@wire` for reads and imperative calls for actions
- Use Unit of Work for DML and selectors for queries
- Use apex-mocks for unit tests

## Templates
Use the templates under `docs/templates/` as starting points for new Apex and LWC code.
