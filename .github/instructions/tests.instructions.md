---
applyTo: "**/test/classes/**/*.cls"
---
- Use `@isTest` and keep tests isolated; avoid `SeeAllData=true`.
- Use `fflib_ApexMocks` for dependencies and `Application.Service.setMock` when stubbing services.
- Wrap the main action in `Test.startTest()` / `Test.stopTest()` when appropriate.
- Assert both positive and negative paths with clear `System.assert*` messages.
