# Architecture Notes

This repo follows Apex Enterprise Patterns from fflib (apex-common) and uses fflib_ApexMocks for tests (apex-mocks).

## Package layout
- apex-common: fflib core framework classes
- apex-mocks: fflib_ApexMocks test utilities
- github-action-service: GitHub integration package
- weather-app: sample application using the patterns

## Enterprise patterns used here
- Application factory: `weather-app/main/default/classes/Application.cls`
- Domain layer: extend `fflib_SObjectDomain` for trigger logic and validation
- Selector layer: extend `fflib_SObjectSelector` with `fflib_QueryFactory`
- Service layer: interface + implementation wired in `Application.Service`
- Unit of Work: `Application.UnitOfWork.newInstance()` for DML

## LWC and controllers
- LWC calls controller methods with `@AuraEnabled` APIs
- Controllers should delegate to services and selectors (no SOQL/DML inside controllers)
- Use `@AuraEnabled(cacheable=true)` for read-only methods

## Testing patterns
- Use `fflib_ApexMocks` for interface and dependency stubs
- Use `Application.Service.setMock` to inject service mocks in tests
- Use `Application.UnitOfWork.setMock` when you need to avoid real DML

## Callouts and configuration
- Use Named Credentials for any external callouts
- Do not hardcode secrets, org IDs, or endpoints

## Templates
See `docs/templates/README.md` for copy-and-fill templates that match these patterns.
